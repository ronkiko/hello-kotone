#!/usr/bin/env python3
"""MMO package adapter and entry point for frame_tools.

Raster commands delegate to independent atomic tools; the agent owns their flow.
Validate/build use the model/frame contract. Replay verifies committed recipe
inputs and reproduces canonical outputs only inside a temporary workspace.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from frame_tools import ToolError, run, find_imagemagick, png_geometry, alpha_bbox
import frame_tools

MODEL_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ANIMATION_RE = MODEL_RE
FRAME_RE = re.compile(r"^(\d{3})\.png$")
RESOURCE_PNG_RE = re.compile(r'path="(res://[^"]+\.png)"')

GODOT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = GODOT_ROOT.parent
ASSET_ROOT = GODOT_ROOT / "assets" / "characters"
FRAME_TOOLS_PATH = GODOT_ROOT / "tools" / "frame_tools.py"
CONTRACT_PATH = GODOT_ROOT / "assets" / "mmo" / "character_sprite_frame_contract_v1.json"
PLAN_SCHEMA_PATH = GODOT_ROOT / "tools" / "character_asset_normalization_plan.schema.json"
LLM_PROTOCOL_PATH = GODOT_ROOT / "tools" / "character_asset_llm_analysis.md"
SPRITEFRAMES_BUILDER = "res://tools/build_character_spriteframes.gd"
REQUIRED_ANIMATIONS = ("idle_left", "idle_right", "walk_left", "walk_right")
DEFAULT_ANIMATION_SPECS = ("idle_left=3.333333:true", "idle_right=3.333333:true", "walk_left=8:true", "walk_right=8:true")
MODEL_ANIMATION_SPECS = {
    "yuna": ("idle_left=0.5:true", "idle_right=0.5:true", "walk_left=8:true", "walk_right=8:true"),
}


@dataclass(frozen=True)
class Contract:
    width: int
    height: int
    pivot_x: int
    pivot_y: int
    pixels_per_cm: int
    models: dict[str, int]

    def target_height_px(self, model_id: str) -> int:
        if model_id not in self.models:
            raise ToolError(f"{model_id!r}: model is not declared in metric contract")
        return self.models[model_id] * self.pixels_per_cm


def find_godot(explicit: str | None = None) -> str:
    if explicit:
        if os.sep in explicit:
            path = Path(explicit)
            if path.is_file():
                return str(path)
        else:
            resolved = shutil.which(explicit)
            if resolved:
                return resolved
        raise ToolError(f"Godot executable not found: {explicit}")
    for name in ("godot", "godot4"):
        resolved = shutil.which(name)
        if resolved:
            return resolved
    raise ToolError("Godot 4 executable not found (tried godot, godot4)")


def load_contract() -> Contract:
    value = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    contract = Contract(
        width=int(value["frame"]["width_px"]),
        height=int(value["frame"]["height_px"]),
        pivot_x=int(value["anchor"]["pivot_x_px"]),
        pivot_y=int(value["anchor"]["pivot_y_px"]),
        pixels_per_cm=int(value["metric_projection"]["canonical_pixels_per_cm"]),
        models={
            model_id: int(model["physical_height_cm"])
            for model_id, model in value["models"].items()
        },
    )
    if (contract.width, contract.height) != (256, 256):
        raise ToolError(f"unexpected frame contract: {contract.width}x{contract.height}")
    if (contract.pivot_x, contract.pivot_y) != (128, 236):
        raise ToolError(f"unexpected pivot: {(contract.pivot_x, contract.pivot_y)}")
    if contract.pixels_per_cm != 1:
        raise ToolError(
            f"unexpected raster-v1 projection: {contract.pixels_per_cm} px/cm"
        )
    return contract


def validate_id(value: str, label: str, pattern: re.Pattern[str]) -> str:
    if pattern.fullmatch(value) is None:
        raise ToolError(f"{label} has invalid syntax: {value!r}")
    return value


def frame_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        raise ToolError(f"{directory}: directory does not exist")
    pngs = sorted(path for path in directory.iterdir() if path.suffix.lower() == ".png")
    if not pngs:
        raise ToolError(f"{directory}: no PNG frames")
    indexes: list[int] = []
    for path in pngs:
        match = FRAME_RE.fullmatch(path.name)
        if match is None:
            raise ToolError(f"{path}: frame name must be NNN.png")
        indexes.append(int(match.group(1)))
    expected = list(range(len(indexes)))
    if indexes != expected:
        raise ToolError(
            f"{directory}: frame sequence must be contiguous from 000; "
            f"expected {expected}, got {indexes}"
        )
    return pngs


def ensure_empty_output(directory: Path, force: bool) -> None:
    if directory.exists():
        existing = list(directory.iterdir())
        if existing and not force:
            raise ToolError(
                f"{directory}: output directory is not empty; use --force to replace"
            )
        if force:
            for path in existing:
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
    directory.mkdir(parents=True, exist_ok=True)


def res_path(path: Path) -> str:
    return "res://" + path.resolve().relative_to(GODOT_ROOT.resolve()).as_posix()


def _repo_relative_path(value: str, label: str) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ToolError(f"{label} must be a repository-relative path")
    resolved = (REPO_ROOT / path).resolve()
    try:
        resolved.relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise ToolError(f"{label} escapes repository root") from exc
    return resolved


def _recipe_root(path: Path) -> Path:
    root = path.resolve()
    if not root.is_dir():
        raise ToolError(f"{root}: recipe directory does not exist")
    try:
        root.relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise ToolError("recipe must live inside the repository") from exc
    return root


def _tracked_repo_file(path: Path) -> bool:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(REPO_ROOT.resolve())
    except ValueError:
        return False
    process = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", relative.as_posix()],
        cwd=REPO_ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return process.returncode == 0


def _assert_temporary_recipe_output(command: list[str], temp_root: Path) -> None:
    if "--force" in command:
        raise ToolError("committed recipe replay forbids --force")
    for index, item in enumerate(command[:-1]):
        if item != "--output":
            continue
        output = Path(command[index + 1]).resolve()
        try:
            output.relative_to(temp_root.resolve())
        except ValueError as exc:
            raise ToolError("recipe output must stay inside temporary replay workspace") from exc


def _assert_recipe_inputs(
    command: list[str],
    temp_root: Path,
    recipe_root: Path,
    verified_sources: set[Path],
) -> None:
    temp_root = temp_root.resolve()
    recipe_root = recipe_root.resolve()
    verified_sources = {path.resolve() for path in verified_sources}
    for index, flag in enumerate(command[:-1]):
        if flag not in {"--source", "--frame-spec", "--plan"}:
            continue
        path = Path(command[index + 1]).resolve()
        if not path.exists():
            raise ToolError(f"recipe input is missing: {path}")
        if flag == "--source":
            if path in verified_sources:
                continue
            try:
                path.relative_to(temp_root)
            except ValueError as exc:
                raise ToolError(
                    "recipe --source must be a verified committed source or a temporary replay artifact"
                ) from exc
        elif flag == "--frame-spec":
            try:
                path.relative_to(temp_root)
            except ValueError as exc:
                raise ToolError("recipe --frame-spec must be produced inside the temporary replay workspace") from exc
        else:
            try:
                path.relative_to(recipe_root)
            except ValueError as exc:
                raise ToolError("recipe --plan must stay inside the committed recipe directory") from exc
            if not _tracked_repo_file(path):
                raise ToolError(f"{path.relative_to(REPO_ROOT)}: recipe plan is not tracked by git")


def _expand_recipe_command(command: list, values: dict[str, str]) -> list[str]:
    if not isinstance(command, list) or not command:
        raise ToolError("recipe command must be a non-empty array")
    expanded: list[str] = []
    for item in command:
        if not isinstance(item, str):
            raise ToolError("recipe command arguments must be strings")
        value = item
        for token, replacement in values.items():
            value = value.replace(token, replacement)
        if "{" in value or "}" in value:
            raise ToolError(f"unknown recipe placeholder in {item!r}")
        expanded.append(value)
    if expanded[0] not in frame_tools.OPERATIONS:
        raise ToolError(f"recipe operation is not an atomic frame tool: {expanded[0]!r}")
    return expanded


def recipe_animation_names(value: object) -> list[str]:
    if (not isinstance(value, list) or not value
            or any(not isinstance(name, str) or ANIMATION_RE.fullmatch(name) is None for name in value)
            or value != sorted(set(value))):
        raise ToolError("recipe animations must be nonempty, sorted unique animation IDs")
    return value


def recipe_frame_paths(models: list[str], animations: list[str]) -> list[Path]:
    expected = []
    for model in models:
        for animation in animations:
            for path in frame_files(ASSET_ROOT / model / animation):
                if not _tracked_repo_file(path):
                    raise ToolError(f"{path}: canonical recipe frame is not tracked by git")
                expected.append(path.relative_to(ASSET_ROOT))
    return sorted(expected)


def command_replay_recipe(args: argparse.Namespace) -> None:
    recipe = _recipe_root(args.recipe)
    manifest_path = recipe / "commands.json"
    if not manifest_path.is_file():
        raise ToolError(f"{manifest_path}: recipe manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        not isinstance(manifest, dict)
        or type(manifest.get("schema")) is not int
        or manifest.get("schema") != 2
        or not isinstance(manifest.get("models"), list)
        or not isinstance(manifest.get("sources"), list)
        or not isinstance(manifest.get("commands"), list)
    ):
        raise ToolError("invalid recipe manifest")
    animations = recipe_animation_names(manifest.get("animations"))
    models = manifest["models"]
    if (
        not models
        or any(not isinstance(model, str) or MODEL_RE.fullmatch(model) is None for model in models)
        or models != sorted(set(models))
        or models != sorted(load_contract().models)
    ):
        raise ToolError("recipe models must exactly match the metric character contract")

    verified_sources = 0
    verified_source_paths: set[Path] = set()
    for source in manifest["sources"]:
        if not isinstance(source, dict):
            raise ToolError("recipe source entry must be an object")
        raw_path = source.get("path")
        expected = source.get("sha256")
        if not isinstance(raw_path, str) or not re.fullmatch(r"[0-9a-f]{64}", str(expected)):
            raise ToolError("recipe source requires relative path and lowercase sha256")
        path = _repo_relative_path(raw_path, "source path")
        if not path.is_file():
            raise ToolError(f"{path}: committed recipe source is missing")
        if not _tracked_repo_file(path):
            raise ToolError(f"{raw_path}: recipe source is not tracked by git")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ToolError(f"{raw_path}: source sha256 mismatch")
        resolved_source = path.resolve()
        if resolved_source in verified_source_paths:
            raise ToolError(f"{raw_path}: duplicate recipe source")
        verified_source_paths.add(resolved_source)
        verified_sources += 1

    with tempfile.TemporaryDirectory(prefix="character-recipe-") as temp:
        temp_root = Path(temp)
        work = temp_root / "work"
        output = temp_root / "output"
        work.mkdir()
        output.mkdir()
        values = {
            "{repo}": str(REPO_ROOT.resolve()),
            "{work}": str(work),
            "{recipe}": str(recipe),
            "{output}": str(output),
        }
        for recipe_file in recipe.rglob("*"):
            if recipe_file.is_file() and not _tracked_repo_file(recipe_file):
                raise ToolError(f"{recipe_file.relative_to(REPO_ROOT)}: recipe input is not tracked by git")

        operations = 0
        for raw in manifest["commands"]:
            command = _expand_recipe_command(raw, values)
            _assert_temporary_recipe_output(command, temp_root)
            _assert_recipe_inputs(command, temp_root, recipe, verified_source_paths)
            process = subprocess.run(
                [sys.executable, str(FRAME_TOOLS_PATH), *command],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if process.returncode:
                raise ToolError(
                    f"recipe operation {operations} failed: {' '.join(command)}\n"
                    f"{process.stderr.strip() or process.stdout.strip()}"
                )
            operations += 1

        generated = sorted(output.rglob("*.png"))
        if not generated:
            raise ToolError("recipe generated no canonical PNG frames")
        relative = [path.relative_to(output) for path in generated]
        if any(len(path.parts) < 3 for path in relative):
            raise ToolError("recipe output has no model/animation/frame hierarchy")

        expected_paths = recipe_frame_paths(models, animations)
        if relative != expected_paths:
            raise ToolError(
                "recipe output set differs from canonical package: "
                f"generated={len(relative)} canonical={len(expected_paths)}"
            )

        identical = 0
        for rel, produced in zip(relative, generated):
            canonical = ASSET_ROOT / rel
            if hashlib.sha256(produced.read_bytes()).digest() != hashlib.sha256(canonical.read_bytes()).digest():
                raise ToolError(f"{rel}: replay output differs from committed canonical frame")
            identical += 1

    print(
        json.dumps(
            {
                "result": "PASS",
                "recipe": str(recipe.relative_to(REPO_ROOT)),
                "sources_verified": verified_sources,
                "operations": operations,
                "frames_reproduced_byte_identical": identical,
                "models": models,
                "animations": animations,
            },
            sort_keys=True,
        )
    )


def command_doctor(args: argparse.Namespace) -> None:
    contract = load_contract()
    im = find_imagemagick()
    godot = find_godot(args.godot)
    im_version = run((*im.identify, "-version"), capture=True).splitlines()[0]
    godot_version = run((godot, "--version"), capture=True).splitlines()[0]
    print(
        json.dumps(
            {
                "result": "PASS",
                "imagemagick": {"mode": im.label, "version": im_version},
                "godot": {"executable": godot, "version": godot_version},
                "contract": {
                    "frame": [contract.width, contract.height],
                    "pivot": [contract.pivot_x, contract.pivot_y],
                    "pixels_per_cm": contract.pixels_per_cm,
                    "models": contract.models,
                },
            },
            indent=2,
        )
    )


def package_animation_dirs(root: Path) -> list[Path]:
    return sorted(path for path in root.iterdir() if path.is_dir())


def validate_model_package(
    im: ImageMagick,
    contract: Contract,
    model_id: str,
    *,
    frames_only: bool,
) -> dict:
    validate_id(model_id, "character_model_id", MODEL_RE)
    contract.target_height_px(model_id)
    root = ASSET_ROOT / model_id
    if not root.is_dir():
        raise ToolError(f"{root}: model package is missing")

    directories = package_animation_dirs(root)
    names = {directory.name for directory in directories}
    missing = sorted(set(REQUIRED_ANIMATIONS) - names)
    if missing:
        raise ToolError(f"{root}: missing required animation directories: {missing}")

    canonical_frames: set[str] = set()
    animation_counts: dict[str, int] = {}
    warnings: list[str] = []
    for directory in directories:
        validate_id(directory.name, "animation_id", ANIMATION_RE)
        frames = frame_files(directory)
        animation_counts[directory.name] = len(frames)
        for frame in frames:
            width, height, bit_depth, color_type = png_geometry(frame)
            if (width, height) != (contract.width, contract.height):
                raise ToolError(
                    f"{frame}: {width}x{height}, expected "
                    f"{contract.width}x{contract.height}"
                )
            if bit_depth != 8 or color_type != 6:
                raise ToolError(
                    f"{frame}: expected 8-bit RGBA PNG, "
                    f"got depth={bit_depth} type={color_type}"
                )
            bbox = alpha_bbox(im, frame)
            if bbox is None:
                raise ToolError(f"{frame}: frame is fully transparent")
            x, y, w, h = bbox
            if x <= 0 or y <= 0 or x + w >= width or y + h >= height:
                raise ToolError(f"{frame}: visible pixels touch frame edge; clipping risk")
            canonical_frames.add(res_path(frame))

    resource = root / "sprite_frames.tres"
    if not frames_only:
        if not resource.is_file():
            raise ToolError(f"{resource}: SpriteFrames resource is missing")
        text = resource.read_text(encoding="utf-8")
        referenced = set(RESOURCE_PNG_RE.findall(text))
        prefix = res_path(root) + "/"
        foreign = sorted(path for path in referenced if not path.startswith(prefix))
        if foreign:
            raise ToolError(f"{resource}: foreign PNG references: {foreign}")
        missing_refs = sorted(canonical_frames - referenced)
        if missing_refs:
            raise ToolError(f"{resource}: canonical frames not referenced: {missing_refs}")
        stale_refs = sorted(referenced - canonical_frames)
        if stale_refs:
            raise ToolError(f"{resource}: stale/noncanonical PNG references: {stale_refs}")
        for animation in animation_counts:
            if f'"{animation}"' not in text:
                raise ToolError(f"{resource}: missing animation {animation!r}")

    return {
        "model": model_id,
        "physical_height_cm": contract.models[model_id],
        "target_body_height_px": contract.target_height_px(model_id),
        "animations": animation_counts,
        "frames": sum(animation_counts.values()),
        "sprite_frames": None if frames_only else str(resource),
        "warnings": warnings,
    }


def command_validate(args: argparse.Namespace) -> None:
    im = find_imagemagick()
    contract = load_contract()
    models = args.models
    if not models:
        models = sorted(
            path.name for path in ASSET_ROOT.iterdir()
            if path.is_dir() and MODEL_RE.fullmatch(path.name)
        )
    if not models:
        raise ToolError("no character model packages selected")
    reports = [
        validate_model_package(im, contract, model, frames_only=args.frames_only)
        for model in models
    ]
    print(json.dumps({"result": "PASS", "models": reports}, indent=2))


def animation_spec_names(specs: list[str] | tuple[str, ...]) -> list[str]:
    seen: set[str] = set()
    names: list[str] = []
    for spec in specs:
        match = re.fullmatch(
            r"([a-z0-9][a-z0-9_-]{0,63})=([0-9]+(?:\.[0-9]+)?):(true|false)",
            spec,
        )
        if not match:
            raise ToolError(
                f"invalid --animation {spec!r}; expected name=fps:true|false"
            )
        name = match.group(1)
        if name in seen:
            raise ToolError(f"duplicate animation spec: {name}")
        seen.add(name)
        names.append(name)
    missing = sorted(set(REQUIRED_ANIMATIONS) - seen)
    if missing:
        raise ToolError(f"missing required animation specs: {missing}")
    return names


def command_build_spriteframes(args: argparse.Namespace) -> None:
    contract = load_contract()
    model_id = validate_id(args.model, "character_model_id", MODEL_RE)
    contract.target_height_px(model_id)
    root = ASSET_ROOT / model_id
    if not root.is_dir():
        raise ToolError(f"{root}: model package is missing")

    specs = args.animation or list(MODEL_ANIMATION_SPECS.get(model_id, DEFAULT_ANIMATION_SPECS))
    for name in animation_spec_names(specs):
        frame_files(root / name)

    godot = find_godot(args.godot)
    command: list[str] = [
        godot,
        "--headless",
        "--path",
        str(GODOT_ROOT),
        "--script",
        SPRITEFRAMES_BUILDER,
        "--",
        "--model",
        model_id,
    ]
    for spec in specs:
        command += ["--animation", spec]
    output = run(command, capture=True)
    lines = [line for line in output.splitlines() if line.startswith("{")]
    if not lines:
        raise ToolError(f"Godot SpriteFrames builder returned no JSON result:\n{output}")
    result = json.loads(lines[-1])
    if result.get("result") != "PASS":
        raise ToolError(f"Godot SpriteFrames builder failed: {result}")
    print(json.dumps(result, indent=2))


def main(argv: list[str]) -> int:
    if argv and argv[0] in frame_tools.OPERATIONS:
        return frame_tools.main(argv)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    doctor = sub.add_parser("doctor")
    doctor.add_argument("--godot")
    doctor.set_defaults(func=command_doctor)
    replay = sub.add_parser(
        "replay-recipe",
        help="replay a committed agent recipe and compare output with canonical frames",
    )
    replay.add_argument("recipe", type=Path)
    replay.set_defaults(func=command_replay_recipe)

    validate = sub.add_parser("validate", help="validate the installed MMO character packages")
    validate.add_argument("models", nargs="*")
    validate.add_argument("--frames-only", action="store_true")
    validate.set_defaults(func=command_validate)
    build = sub.add_parser("build-spriteframes")
    build.add_argument("--model", required=True)
    build.add_argument("--animation", action="append")
    build.add_argument("--godot")
    build.set_defaults(func=command_build_spriteframes)
    args = parser.parse_args(argv)
    try:
        args.func(args)
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, ToolError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
