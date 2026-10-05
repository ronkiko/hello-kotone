#!/usr/bin/env python3
"""Offline character-art pipeline for the Godot MMO client.

Canonical workflow:

    extract-grid -> inspect -> LLM/human normalization plan
                 -> normalize -> validate -> build-spriteframes

ImageMagick performs raster operations. Godot itself writes SpriteFrames.tres.
The script never infers character height or world root from bitmap heuristics:
those are explicit plan inputs and metric-contract values.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MODEL_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ANIMATION_RE = MODEL_RE
FRAME_RE = re.compile(r"^(\d{3})\.png$")
BBOX_RE = re.compile(r"^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$")
RESOURCE_PNG_RE = re.compile(r'path="(res://[^"]+\.png)"')

GODOT_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = GODOT_ROOT / "assets" / "characters"
CONTRACT_PATH = GODOT_ROOT / "assets" / "mmo" / "character_sprite_frame_contract_v1.json"
PLAN_SCHEMA_PATH = GODOT_ROOT / "tools" / "character_asset_normalization_plan.schema.json"
SPRITEFRAMES_BUILDER = "res://tools/build_character_spriteframes.gd"
REQUIRED_ANIMATIONS = ("idle", "walk_left", "walk_right")
DEFAULT_ANIMATION_SPECS = ("idle=3.333333:true", "walk_left=8:true", "walk_right=8:true")


class ToolError(RuntimeError):
    pass


@dataclass(frozen=True)
class ImageMagick:
    convert: tuple[str, ...]
    identify: tuple[str, ...]
    montage: tuple[str, ...]
    label: str


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


def run(command: Iterable[str], *, capture: bool = False) -> str:
    args = [str(part) for part in command]
    result = subprocess.run(
        args,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout or "").strip()
        raise ToolError(f"command failed ({result.returncode}): {' '.join(args)}\n{detail}")
    return (result.stdout or "").strip()


def find_imagemagick() -> ImageMagick:
    magick = shutil.which("magick")
    if magick:
        return ImageMagick(
            convert=(magick,),
            identify=(magick, "identify"),
            montage=(magick, "montage"),
            label="ImageMagick 7",
        )
    convert = shutil.which("convert")
    identify = shutil.which("identify")
    montage = shutil.which("montage")
    if convert and identify and montage:
        return ImageMagick(
            convert=(convert,),
            identify=(identify,),
            montage=(montage,),
            label="ImageMagick 6",
        )
    raise ToolError(
        "ImageMagick not found; install ImageMagick 7 (magick) or "
        "ImageMagick 6 (convert + identify + montage)"
    )


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


def png_geometry(path: Path) -> tuple[int, int, int, int]:
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 33 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ToolError(f"{path}: not a PNG with IHDR")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
    return width, height, bit_depth, color_type


def identify_geometry(im: ImageMagick, path: Path) -> tuple[int, int]:
    text = run((*im.identify, "-format", "%w %h", path), capture=True)
    try:
        width, height = (int(part) for part in text.split())
    except ValueError as exc:
        raise ToolError(f"{path}: unexpected identify output: {text!r}") from exc
    return width, height


def alpha_bbox(im: ImageMagick, path: Path) -> tuple[int, int, int, int] | None:
    text = run(
        (
            *im.convert,
            path,
            "-alpha",
            "extract",
            "-threshold",
            "0",
            "-trim",
            "-format",
            "%@",
            "info:",
        ),
        capture=True,
    )
    match = BBOX_RE.fullmatch(text.strip())
    if not match:
        return None
    width, height, x, y = (int(value) for value in match.groups())
    if width <= 0 or height <= 0:
        return None
    return x, y, width, height


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


def load_plan(path: Path, contract: Contract) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    allowed_top = {
        "schema",
        "character_model_id",
        "animation_id",
        "source_body_height_px",
        "source_cleanup",
        "analysis",
        "frames",
    }
    if not isinstance(value, dict) or set(value) - allowed_top:
        raise ToolError(f"{path}: unknown normalization-plan fields")
    if value.get("schema") != 1:
        raise ToolError(f"{path}: normalization plan schema must be 1")

    model_id = value.get("character_model_id")
    animation_id = value.get("animation_id")
    if not isinstance(model_id, str):
        raise ToolError(f"{path}: character_model_id must be a string")
    if not isinstance(animation_id, str):
        raise ToolError(f"{path}: animation_id must be a string")
    validate_id(model_id, "character_model_id", MODEL_RE)
    validate_id(animation_id, "animation_id", ANIMATION_RE)
    contract.target_height_px(model_id)

    source_height = value.get("source_body_height_px")
    if not isinstance(source_height, (int, float)) or isinstance(source_height, bool):
        raise ToolError(f"{path}: source_body_height_px must be a number")
    if not math.isfinite(float(source_height)) or float(source_height) <= 0:
        raise ToolError(f"{path}: source_body_height_px must be finite and > 0")

    cleanup = value.get("source_cleanup", {})
    if not isinstance(cleanup, dict):
        raise ToolError(f"{path}: source_cleanup must be an object")
    if set(cleanup) - {"transparent_color", "fuzz_percent"}:
        raise ToolError(f"{path}: unknown source_cleanup fields")
    if "transparent_color" in cleanup:
        color = cleanup["transparent_color"]
        if not isinstance(color, str) or re.fullmatch(r"#[0-9A-Fa-f]{6}", color) is None:
            raise ToolError(f"{path}: transparent_color must be #RRGGBB")
    if "fuzz_percent" in cleanup:
        fuzz = cleanup["fuzz_percent"]
        if (
            not isinstance(fuzz, (int, float))
            or isinstance(fuzz, bool)
            or not math.isfinite(float(fuzz))
            or not 0 <= float(fuzz) <= 25
        ):
            raise ToolError(f"{path}: fuzz_percent must be in [0,25]")
        if "transparent_color" not in cleanup:
            raise ToolError(f"{path}: fuzz_percent requires transparent_color")

    analysis = value.get("analysis", {})
    if not isinstance(analysis, dict):
        raise ToolError(f"{path}: analysis must be an object")
    if set(analysis) - {"author", "method", "confidence", "notes"}:
        raise ToolError(f"{path}: unknown analysis fields")
    if "method" in analysis and analysis["method"] not in {
        "human",
        "llm",
        "human_reviewed_llm",
    }:
        raise ToolError(f"{path}: invalid analysis.method")
    if "confidence" in analysis:
        confidence = analysis["confidence"]
        if (
            not isinstance(confidence, (int, float))
            or isinstance(confidence, bool)
            or not math.isfinite(float(confidence))
            or not 0 <= float(confidence) <= 1
        ):
            raise ToolError(f"{path}: analysis.confidence must be in [0,1]")

    frames = value.get("frames")
    if not isinstance(frames, list) or not frames:
        raise ToolError(f"{path}: frames must be a non-empty array")
    seen: set[str] = set()
    for item in frames:
        if not isinstance(item, dict):
            raise ToolError(f"{path}: every frame plan must be an object")
        if set(item) - {"file", "source_root_px", "confidence", "notes"}:
            raise ToolError(f"{path}: unknown per-frame fields")
        name = item.get("file")
        root = item.get("source_root_px")
        if not isinstance(name, str) or FRAME_RE.fullmatch(name) is None:
            raise ToolError(f"{path}: frame file must be NNN.png")
        if name in seen:
            raise ToolError(f"{path}: duplicate frame {name}")
        seen.add(name)
        if (
            not isinstance(root, list)
            or len(root) != 2
            or any(
                not isinstance(point, (int, float))
                or isinstance(point, bool)
                or not math.isfinite(float(point))
                for point in root
            )
        ):
            raise ToolError(f"{path}: {name} source_root_px must be [x,y] numbers")
        if "confidence" in item:
            confidence = item["confidence"]
            if (
                not isinstance(confidence, (int, float))
                or isinstance(confidence, bool)
                or not math.isfinite(float(confidence))
                or not 0 <= float(confidence) <= 1
            ):
                raise ToolError(f"{path}: {name} confidence must be in [0,1]")
    return value


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


def command_extract_grid(args: argparse.Namespace) -> None:
    im = find_imagemagick()
    source = args.source.resolve()
    if not source.is_file():
        raise ToolError(f"{source}: source image does not exist")
    width, height = identify_geometry(im, source)
    if args.columns <= 0 or args.rows <= 0:
        raise ToolError("--columns and --rows must be > 0")

    cell_width = math.ceil(width / args.columns)
    cell_height = math.ceil(height / args.rows)
    padded_width = cell_width * args.columns
    padded_height = cell_height * args.rows
    total = args.columns * args.rows
    frame_count = args.frame_count if args.frame_count is not None else total
    if frame_count <= 0 or frame_count > total:
        raise ToolError(f"--frame-count must be in [1,{total}]")

    output = args.output_dir.resolve()
    ensure_empty_output(output, args.force)
    pattern = output / "%03d.png"
    run(
        (
            *im.convert,
            source,
            "-alpha",
            "on",
            "-background",
            "none",
            "-gravity",
            "northwest",
            "-extent",
            f"{padded_width}x{padded_height}",
            "-crop",
            f"{cell_width}x{cell_height}",
            "+repage",
            f"PNG32:{pattern}",
        )
    )
    created = frame_files(output)
    if len(created) != total:
        raise ToolError(f"ImageMagick created {len(created)} frames, expected {total}")
    for path in created[frame_count:]:
        path.unlink()
    created = frame_files(output)
    print(
        json.dumps(
            {
                "result": "PASS",
                "source": str(source),
                "source_size": [width, height],
                "grid": [args.columns, args.rows],
                "padded_size": [padded_width, padded_height],
                "cell_size": [cell_width, cell_height],
                "frames": len(created),
                "output": str(output),
            },
            indent=2,
        )
    )


def grid_draw(width: int, height: int, step: int) -> str:
    commands: list[str] = []
    for x in range(step, width, step):
        commands.append(f"line {x},0 {x},{height - 1}")
    for y in range(step, height, step):
        commands.append(f"line 0,{y} {width - 1},{y}")
    return " ".join(commands)


def command_inspect(args: argparse.Namespace) -> None:
    im = find_imagemagick()
    contract = load_contract()
    model_id = validate_id(args.model, "character_model_id", MODEL_RE)
    animation_id = validate_id(args.animation, "animation_id", ANIMATION_RE)
    target_height = contract.target_height_px(model_id)
    source_dir = args.source_dir.resolve()
    frames = frame_files(source_dir)

    output = args.output_dir.resolve()
    ensure_empty_output(output, args.force)
    overlays = output / "frames"
    overlays.mkdir(parents=True, exist_ok=True)

    packet_frames: list[dict] = []
    overlay_paths: list[Path] = []
    for frame in frames:
        width, height = identify_geometry(im, frame)
        bbox = alpha_bbox(im, frame)
        overlay = overlays / frame.name
        draw = grid_draw(width, height, args.grid_step)
        command = [
            *im.convert,
            frame,
            "-alpha",
            "on",
            "-stroke",
            "#00FFFF66",
            "-strokewidth",
            "1",
            "-fill",
            "none",
        ]
        if draw:
            command += ["-draw", draw]
        command += [
            "-stroke",
            "#FF00FFAA",
            "-strokewidth",
            "1",
            "-draw",
            f"line {width // 2},0 {width // 2},{height - 1} "
            f"line 0,{height // 2} {width - 1},{height // 2}",
            f"PNG32:{overlay}",
        ]
        run(command)
        overlay_paths.append(overlay)
        packet_frames.append(
            {
                "file": frame.name,
                "size_px": [width, height],
                "alpha_bbox_diagnostic": list(bbox) if bbox else None,
                "analysis_overlay": str(overlay.relative_to(output)),
            }
        )

    board = output / "analysis-board.png"
    tile = f"{max(1, args.columns)}x"
    run(
        (
            *im.montage,
            *overlay_paths,
            "-tile",
            tile,
            "-geometry",
            "+8+8",
            "-background",
            "#202020",
            f"PNG32:{board}",
        )
    )

    packet = {
        "schema": 1,
        "purpose": "LLM/human source-art analysis only; alpha bbox is diagnostic, not authority",
        "character_model_id": model_id,
        "animation_id": animation_id,
        "source_dir": str(source_dir),
        "target_contract": {
            "physical_height_cm": contract.models[model_id],
            "canonical_pixels_per_cm": contract.pixels_per_cm,
            "target_body_height_px": target_height,
            "canonical_frame_px": [contract.width, contract.height],
            "canonical_root_px": [contract.pivot_x, contract.pivot_y],
        },
        "analysis_grid_step_px": args.grid_step,
        "board_order": "row-major, same order as frames array",
        "frames": packet_frames,
        "llm_instructions": [
            "Return Character Asset Normalization Plan v1 JSON.",
            "Choose one source_body_height_px for the whole animation; do not scale frames independently.",
            "source_body_height_px is anatomical model scale, not alpha bbox height and not hair/accessory extent.",
            "For each frame choose source_root_px = ground-contact center under the body in source pixel coordinates.",
            "Walking feet may separate; root is the stable world contact center, not whichever foot is furthest left/right.",
            "Use confidence/notes when a point is ambiguous. Do not edit or resample images.",
            "Optional source_cleanup may specify a matte transparent_color and fuzz_percent.",
        ],
        "plan_schema": str(PLAN_SCHEMA_PATH),
    }
    (output / "analysis-packet.json").write_text(
        json.dumps(packet, indent=2) + "\n", encoding="utf-8"
    )
    print(
        json.dumps(
            {
                "result": "PASS",
                "frames": len(frames),
                "analysis_packet": str(output / "analysis-packet.json"),
                "analysis_board": str(board),
            },
            indent=2,
        )
    )


def command_normalize(args: argparse.Namespace) -> None:
    im = find_imagemagick()
    contract = load_contract()
    plan = load_plan(args.plan.resolve(), contract)
    source_dir = args.source_dir.resolve()
    source_frames = frame_files(source_dir)
    planned_names = [item["file"] for item in plan["frames"]]
    actual_names = [path.name for path in source_frames]
    if planned_names != actual_names:
        raise ToolError(
            "normalization plan frame list must exactly match source directory: "
            f"plan={planned_names}, source={actual_names}"
        )

    model_id = plan["character_model_id"]
    target_height = contract.target_height_px(model_id)
    source_height = float(plan["source_body_height_px"])
    scale = target_height / source_height
    if not math.isfinite(scale) or scale <= 0:
        raise ToolError("computed scale is invalid")

    output = args.output_dir.resolve()
    ensure_empty_output(output, args.force)
    cleanup = plan.get("source_cleanup", {})
    warnings: list[str] = []
    results: list[dict] = []

    for item, source in zip(plan["frames"], source_frames):
        root_x, root_y = (float(value) for value in item["source_root_px"])
        source_width, source_height_px = identify_geometry(im, source)
        if not 0 <= root_x <= source_width - 1 or not 0 <= root_y <= source_height_px - 1:
            raise ToolError(
                f"{source}: source_root_px {(root_x, root_y)} is outside "
                f"{source_width}x{source_height_px}"
            )
        destination = output / source.name
        command: list[str] = [*im.convert, str(source), "-alpha", "on"]
        color = cleanup.get("transparent_color")
        if color:
            fuzz = float(cleanup.get("fuzz_percent", 0))
            command += ["-fuzz", f"{fuzz:.6g}%", "-transparent", color]
        srt = (
            f"{root_x:.8g},{root_y:.8g} "
            f"{scale:.12g} 0 "
            f"{contract.pivot_x},{contract.pivot_y}"
        )
        command += [
            "-background",
            "none",
            "-virtual-pixel",
            "transparent",
            "-filter",
            "Lanczos",
            "-define",
            f"distort:viewport={contract.width}x{contract.height}+0+0",
            "-distort",
            "SRT",
            srt,
            "+repage",
            f"PNG32:{destination}",
        ]
        run(command)

        width, height, bit_depth, color_type = png_geometry(destination)
        if (width, height) != (contract.width, contract.height):
            raise ToolError(f"{destination}: normalize produced {width}x{height}")
        if bit_depth != 8 or color_type != 6:
            raise ToolError(
                f"{destination}: normalize must produce 8-bit RGBA PNG, "
                f"got depth={bit_depth} type={color_type}"
            )
        bbox = alpha_bbox(im, destination)
        clipped = False
        if bbox:
            x, y, w, h = bbox
            clipped = x <= 0 or y <= 0 or x + w >= width or y + h >= height
            if clipped:
                warnings.append(f"{source.name}: visible pixels touch canonical frame edge")
        results.append(
            {
                "file": source.name,
                "source_root_px": [root_x, root_y],
                "canonical_root_px": [contract.pivot_x, contract.pivot_y],
                "alpha_bbox_diagnostic": list(bbox) if bbox else None,
                "edge_touch_warning": clipped,
            }
        )

    report = {
        "result": "PASS" if not warnings else "PASS_WITH_WARNINGS",
        "character_model_id": model_id,
        "animation_id": plan["animation_id"],
        "source_body_height_px": source_height,
        "target_body_height_px": target_height,
        "uniform_scale": scale,
        "canonical_frame_px": [contract.width, contract.height],
        "canonical_root_px": [contract.pivot_x, contract.pivot_y],
        "frames": results,
        "warnings": warnings,
        "output": str(output),
    }
    if args.report:
        args.report.resolve().write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    doctor = sub.add_parser("doctor", help="check ImageMagick, Godot and metric contract")
    doctor.add_argument("--godot")
    doctor.set_defaults(func=command_doctor)

    extract = sub.add_parser("extract-grid", help="extract a regular source spritesheet")
    extract.add_argument("--source", type=Path, required=True)
    extract.add_argument("--output-dir", type=Path, required=True)
    extract.add_argument("--columns", type=int, required=True)
    extract.add_argument("--rows", type=int, required=True)
    extract.add_argument("--frame-count", type=int)
    extract.add_argument("--force", action="store_true")
    extract.set_defaults(func=command_extract_grid)

    inspect = sub.add_parser(
        "inspect",
        help="prepare grid overlays + analysis packet for LLM/human review",
    )
    inspect.add_argument("--model", required=True)
    inspect.add_argument("--animation", required=True)
    inspect.add_argument("--source-dir", type=Path, required=True)
    inspect.add_argument("--output-dir", type=Path, required=True)
    inspect.add_argument("--grid-step", type=int, default=32)
    inspect.add_argument("--columns", type=int, default=4)
    inspect.add_argument("--force", action="store_true")
    inspect.set_defaults(func=command_inspect)

    normalize = sub.add_parser(
        "normalize",
        help="apply an explicit LLM/human normalization plan with ImageMagick",
    )
    normalize.add_argument("--plan", type=Path, required=True)
    normalize.add_argument("--source-dir", type=Path, required=True)
    normalize.add_argument("--output-dir", type=Path, required=True)
    normalize.add_argument("--report", type=Path)
    normalize.add_argument("--force", action="store_true")
    normalize.set_defaults(func=command_normalize)

    validate = sub.add_parser("validate", help="validate canonical character packages")
    validate.add_argument("models", nargs="*")
    validate.add_argument("--frames-only", action="store_true")
    validate.set_defaults(func=command_validate)

    build = sub.add_parser(
        "build-spriteframes",
        help="ask Godot to build sprite_frames.tres from canonical PNG folders",
    )
    build.add_argument("--model", required=True)
    build.add_argument(
        "--animation",
        action="append",
        help="name=fps:true|false; repeat for every animation",
    )
    build.add_argument("--godot")
    build.set_defaults(func=command_build_spriteframes)

    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if getattr(args, "grid_step", 1) <= 0:
            raise ToolError("--grid-step must be > 0")
        if getattr(args, "columns", 1) <= 0:
            raise ToolError("--columns must be > 0")
        args.func(args)
        return 0
    except (
        OSError,
        ValueError,
        KeyError,
        json.JSONDecodeError,
        subprocess.SubprocessError,
        ToolError,
    ) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
