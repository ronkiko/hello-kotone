#!/usr/bin/env python3
"""Build the first right-facing KTN-RC3-M03 side cutout asset set."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "godot/assets/rc3/mannequin/source/side"
BODY_SOURCE = SOURCE_DIR / "kotone_side_left_mannequin_source.png"
ARM_SOURCE = SOURCE_DIR / "kotone_side_arm_down_source.png"
OUTPUT = ROOT / "godot/assets/rc3/mannequin/parts/side/m03"

CANVAS_SIZE = (1254, 1254)
FIGURE_ALPHA_BOUNDS = (546, 54, 708, 1165)
BODY_CUTOFF_Y = 620
HIP_PIVOT = (625, 575)
KNEE_PIVOT = (625, 775)
ANKLE_PIVOT = (625, 1060)
SHOULDER_PIVOT = (620, 205)

BODY_SHA256 = "4ff6fed6b151ec3b4fe310507566a0ed7655a54b1cb5b2a58895d5629ddd2760"
ARM_SHA256 = "c57ef48c465d2f270d27674a1253363d1ce08ad4cfd19fc6efc53fb867585df5"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_source(path: Path, digest: str) -> None:
    if not path.is_file():
        raise SystemExit(f"missing source: {path}")
    if sha256(path) != digest:
        raise SystemExit(f"source hash changed: {path}")


def normalize_body() -> Image.Image:
    source = Image.open(BODY_SOURCE).convert("RGBA")
    alpha_bbox = source.getchannel("A").getbbox()
    if alpha_bbox is None:
        raise SystemExit("empty side mannequin source")
    cropped = source.crop(alpha_bbox)
    target_width = FIGURE_ALPHA_BOUNDS[2] - FIGURE_ALPHA_BOUNDS[0]
    target_height = FIGURE_ALPHA_BOUNDS[3] - FIGURE_ALPHA_BOUNDS[1]
    resized = cropped.resize((target_width, target_height), Image.Resampling.LANCZOS)
    right_facing = resized.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(right_facing, dest=FIGURE_ALPHA_BOUNDS[:2])
    return canvas


def normalize_arm() -> Image.Image:
    source = Image.open(ARM_SOURCE).convert("RGBA")
    alpha = source.getchannel("A")
    clean_alpha = alpha.point(lambda value: value if value >= 8 else 0)
    source.putalpha(clean_alpha)
    bbox = clean_alpha.getbbox()
    if bbox is None:
        raise SystemExit("empty side arm source")
    cropped = source.crop(bbox)
    target_height = 360
    target_width = round(cropped.width * target_height / cropped.height)
    return cropped.resize((target_width, target_height), Image.Resampling.LANCZOS)


def horizontal_slice(source: Image.Image, top: int, bottom: int) -> Image.Image:
    result = Image.new("RGBA", source.size, (0, 0, 0, 0))
    result.alpha_composite(source.crop((0, top, source.width, bottom)), dest=(0, top))
    return result


def save_trimmed(
    canvas: Image.Image,
    name: str,
    pivot_global: tuple[int, int],
) -> dict[str, object]:
    bbox = canvas.getchannel("A").getbbox()
    if bbox is None:
        raise SystemExit(f"empty M03 part: {name}")
    trimmed = canvas.crop(bbox)
    path = OUTPUT / f"{name}.png"
    trimmed.save(path, optimize=True)
    return {
        "name": name,
        "file": path.name,
        "offset": [bbox[0], bbox[1]],
        "size": [trimmed.width, trimmed.height],
        "pivot_global": list(pivot_global),
        "pivot_local": [pivot_global[0] - bbox[0], pivot_global[1] - bbox[1]],
        "sha256": sha256(path),
    }


def main() -> None:
    require_source(BODY_SOURCE, BODY_SHA256)
    require_source(ARM_SOURCE, ARM_SHA256)
    OUTPUT.mkdir(parents=True, exist_ok=True)

    normalized = normalize_body()
    normalized_path = OUTPUT / "kotone_side_right_normalized.png"
    normalized.save(normalized_path, optimize=True)

    body = horizontal_slice(normalized, 0, BODY_CUTOFF_Y)
    thigh = horizontal_slice(normalized, 520, 835)
    calf = horizontal_slice(normalized, 735, 1105)
    foot = horizontal_slice(normalized, 1015, FIGURE_ALPHA_BOUNDS[3])

    arm = normalize_arm()
    arm_canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    arm_left = SHOULDER_PIVOT[0] - arm.width // 2
    arm_top = SHOULDER_PIVOT[1] - 20
    arm_canvas.alpha_composite(arm, dest=(arm_left, arm_top))

    parts = [
        save_trimmed(body, "body_head_pelvis", HIP_PIVOT),
        save_trimmed(arm_canvas, "arm_near", SHOULDER_PIVOT),
        save_trimmed(thigh, "thigh", HIP_PIVOT),
        save_trimmed(calf, "calf", KNEE_PIVOT),
        save_trimmed(foot, "foot", ANKLE_PIVOT),
    ]

    manifest = {
        "schema_version": 1,
        "technical_model": "KTN-RC3-M03",
        "character": "kotone",
        "release": "rc3",
        "view": "side_right",
        "purpose": "first_side_facing_grounded_gait_prototype",
        "status": "isolated_visibility_gate_pending",
        "source_body": "../../../source/side/kotone_side_left_mannequin_source.png",
        "source_body_sha256": BODY_SHA256,
        "source_arm": "../../../source/side/kotone_side_arm_down_source.png",
        "source_arm_sha256": ARM_SHA256,
        "canvas": list(CANVAS_SIZE),
        "normalized_source": normalized_path.name,
        "normalized_source_sha256": sha256(normalized_path),
        "normalized_alpha_bounds": list(FIGURE_ALPHA_BOUNDS),
        "direction_policy": "right_source_mirror_visual_pivot_for_left",
        "construction": "static_side_body_one_rigid_near_arm_two_instances_of_one_three_segment_leg",
        "known_limitations": [
            "source_far_arm_is_foreshortened_and_remains_baked_into_body",
            "near_arm_is_rigid_at_elbow_for_first_side_gait_gate",
            "one_side_leg_art_is_reused_for_near_and_far_layers",
        ],
        "pivots": {
            "shoulder": list(SHOULDER_PIVOT),
            "hip": list(HIP_PIVOT),
            "knee": list(KNEE_PIVOT),
            "ankle": list(ANKLE_PIVOT),
        },
        "parts": parts,
        "draw_order_back_to_front": [
            "far_foot",
            "far_calf",
            "far_thigh",
            "body_head_pelvis",
            "near_foot",
            "near_calf",
            "near_thigh",
            "arm_near",
        ],
    }
    (OUTPUT / "m03_side_asset_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )
    print("KTN-RC3-M03 SIDE ASSET BUILD COMPLETE")


if __name__ == "__main__":
    main()
