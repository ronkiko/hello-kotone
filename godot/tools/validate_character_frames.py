#!/usr/bin/env python3
"""Validate canonical Godot character frame packages.

Usage:
    python godot/tools/validate_character_frames.py kotone yuna

The tool intentionally validates authoring/package structure only. It does not
infer body height from alpha bounds; physical height comes from the metric
contract and normalization tooling.
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MODEL_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
FRAME_RE = re.compile(r"^(\d{3})\.png$")
RESOURCE_PNG_RE = re.compile(r'path="(res://[^"]+\.png)"')
REQUIRED_ANIMATIONS = ("idle", "walk_left", "walk_right")

GODOT_ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = GODOT_ROOT / "assets" / "characters"
CONTRACT_PATH = GODOT_ROOT / "assets" / "mmo" / "character_sprite_frame_contract_v1.json"


class ValidationError(RuntimeError):
    pass


def load_contract() -> tuple[int, int, set[str]]:
    value = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    width = int(value["frame"]["width_px"])
    height = int(value["frame"]["height_px"])
    models = set(value["models"])
    if (width, height) != (256, 256):
        raise ValidationError(f"unexpected frame contract: {width}x{height}")
    return width, height, models


def png_geometry(path: Path) -> tuple[int, int, int, int]:
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 33 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValidationError(f"{path}: not a canonical PNG")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
    return width, height, bit_depth, color_type


def frame_files(animation_dir: Path) -> list[Path]:
    files = sorted(p for p in animation_dir.iterdir() if p.is_file())
    pngs: list[Path] = []
    indexes: list[int] = []
    for path in files:
        match = FRAME_RE.fullmatch(path.name)
        if path.suffix.lower() == ".png" and match is None:
            raise ValidationError(f"{path}: frame name must be NNN.png")
        if match is not None:
            pngs.append(path)
            indexes.append(int(match.group(1)))
    if not pngs:
        raise ValidationError(f"{animation_dir}: no canonical frame PNGs")
    if indexes != list(range(len(indexes))):
        raise ValidationError(
            f"{animation_dir}: frame sequence must be contiguous from 000, got {indexes}"
        )
    return pngs


def res_path(path: Path) -> str:
    return "res://" + path.relative_to(GODOT_ROOT).as_posix()


def validate_model(model_id: str, width: int, height: int, declared_models: set[str]) -> int:
    if MODEL_RE.fullmatch(model_id) is None:
        raise ValidationError(f"{model_id!r}: invalid character_model_id")
    if model_id not in declared_models:
        raise ValidationError(f"{model_id}: missing from metric character contract")

    root = ASSET_ROOT / model_id
    if not root.is_dir():
        raise ValidationError(f"{root}: package directory is missing")

    resource = root / "sprite_frames.tres"
    if not resource.is_file():
        raise ValidationError(f"{resource}: SpriteFrames resource is missing")

    canonical_frames: set[str] = set()
    total = 0
    for animation in REQUIRED_ANIMATIONS:
        directory = root / animation
        if not directory.is_dir():
            raise ValidationError(f"{directory}: required animation directory is missing")
        for frame in frame_files(directory):
            actual_width, actual_height, bit_depth, color_type = png_geometry(frame)
            if (actual_width, actual_height) != (width, height):
                raise ValidationError(
                    f"{frame}: {actual_width}x{actual_height}, expected {width}x{height}"
                )
            if bit_depth != 8 or color_type != 6:
                raise ValidationError(
                    f"{frame}: expected 8-bit RGBA PNG (color type 6), "
                    f"got bit_depth={bit_depth} color_type={color_type}"
                )
            canonical_frames.add(res_path(frame))
            total += 1

    tres = resource.read_text(encoding="utf-8")
    referenced = set(RESOURCE_PNG_RE.findall(tres))
    foreign = sorted(path for path in referenced if not path.startswith(res_path(root) + "/"))
    if foreign:
        raise ValidationError(f"{resource}: foreign PNG references: {foreign}")

    missing_refs = sorted(canonical_frames - referenced)
    if missing_refs:
        raise ValidationError(f"{resource}: canonical frames not referenced: {missing_refs}")

    stale_refs = sorted(referenced - canonical_frames)
    if stale_refs:
        raise ValidationError(
            f"{resource}: PNG references outside required canonical frame set: {stale_refs}"
        )

    for animation in REQUIRED_ANIMATIONS:
        if f'"{animation}"' not in tres:
            raise ValidationError(f"{resource}: missing SpriteFrames animation {animation!r}")

    print(f"PASS {model_id}: {total} canonical frames")
    return total


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: validate_character_frames.py <character_model_id> [...]", file=sys.stderr)
        return 2
    try:
        width, height, declared_models = load_contract()
        total = 0
        for model_id in argv:
            total += validate_model(model_id, width, height, declared_models)
        print(f"PASS total={total} frame={width}x{height}")
        return 0
    except (OSError, KeyError, ValueError, json.JSONDecodeError, ValidationError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
