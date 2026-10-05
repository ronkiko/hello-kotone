#!/usr/bin/env python3
"""MMO package validation/Godot build adapter and entry point for frame_tools.

Raster commands delegate to independent atomic tools; the agent owns their flow.
Only validate/build-spriteframes use this application's model/frame contract.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from frame_tools import ToolError, run, find_imagemagick, png_geometry, alpha_bbox
import frame_tools

MODEL_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ANIMATION_RE = MODEL_RE
FRAME_RE = re.compile(r"^(\d{3})\.png$")
RESOURCE_PNG_RE = re.compile(r'path="(res://[^"]+\.png)"')

GODOT_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = GODOT_ROOT / "assets" / "characters"
CONTRACT_PATH = GODOT_ROOT / "assets" / "mmo" / "character_sprite_frame_contract_v1.json"
PLAN_SCHEMA_PATH = GODOT_ROOT / "tools" / "character_asset_normalization_plan.schema.json"
LLM_PROTOCOL_PATH = GODOT_ROOT / "tools" / "character_asset_llm_analysis.md"
SPRITEFRAMES_BUILDER = "res://tools/build_character_spriteframes.gd"
REQUIRED_ANIMATIONS = ("idle", "walk_left", "walk_right")
DEFAULT_ANIMATION_SPECS = ("idle=3.333333:true", "walk_left=8:true", "walk_right=8:true")


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


def command_build_spriteframes(args: argparse.Namespace) -> None:
    contract = load_contract()
    model_id = validate_id(args.model, "character_model_id", MODEL_RE)
    contract.target_height_px(model_id)
    root = ASSET_ROOT / model_id
    if not root.is_dir():
        raise ToolError(f"{root}: model package is missing")

    specs = args.animation or list(DEFAULT_ANIMATION_SPECS)
    seen: set[str] = set()
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
