#!/usr/bin/env python3
"""Build the six KTN-RC3-M01 whole-region assets from approved cutouts."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
PARTS_DIR = ROOT / "godot/assets/rc3/mannequin/parts/front"
SOURCE = ROOT / "godot/assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png"
OUTPUT = ROOT / "godot/assets/rc3/mannequin/godot_mesh/front/m01"
MANIFEST_PATH = PARTS_DIR / "front_parts_manifest.json"

GROUPS = {
    "arm_right": ["hand_right", "forearm_right", "upper_arm_right"],
    "arm_left": ["hand_left", "forearm_left", "upper_arm_left"],
    "leg_right": ["foot_right", "calf_right", "thigh_right"],
    "leg_left": ["foot_left", "calf_left", "thigh_left"],
    "body": ["pelvis", "torso"],
    "head": ["head_neck"],
}

DRAW_ORDER = ["arm_right", "arm_left", "leg_right", "leg_left", "body", "head"]
ATLAS_POSITIONS = {
    "leg_right": (16, 16),
    "leg_left": (157, 16),
    "body": (298, 16),
    "head": (547, 16),
    "arm_right": (547, 229),
    "arm_left": (547, 337),
}
ATLAS_SIZE = (1024, 768)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    parts_manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    part_by_name = {part["name"]: part for part in parts_manifest["parts"]}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    parts_output = OUTPUT / "parts"
    parts_output.mkdir(exist_ok=True)

    built: dict[str, dict[str, object]] = {}
    full_group_images: dict[str, Image.Image] = {}

    for group_name, part_names in GROUPS.items():
        canvas = Image.new("RGBA", source.size, (0, 0, 0, 0))
        for part_name in part_names:
            part = part_by_name[part_name]
            image = Image.open(PARTS_DIR / part["file"]).convert("RGBA")
            canvas.alpha_composite(image, dest=tuple(part["offset"]))

        alpha_bbox = canvas.getchannel("A").getbbox()
        if alpha_bbox is None:
            raise SystemExit(f"empty group: {group_name}")
        trimmed = canvas.crop(alpha_bbox)
        output_path = parts_output / f"{group_name}.png"
        trimmed.save(output_path, optimize=True)
        full_group_images[group_name] = canvas
        built[group_name] = {
            "file": f"parts/{group_name}.png",
            "source_parts": part_names,
            "source_offset": [alpha_bbox[0], alpha_bbox[1]],
            "size": [trimmed.width, trimmed.height],
            "sha256": sha256(output_path),
        }

    atlas = Image.new("RGBA", ATLAS_SIZE, (0, 0, 0, 0))
    for group_name, position in ATLAS_POSITIONS.items():
        asset_path = OUTPUT / built[group_name]["file"]
        asset = Image.open(asset_path).convert("RGBA")
        x, y = position
        if x + asset.width > atlas.width or y + asset.height > atlas.height:
            raise SystemExit(f"atlas overflow: {group_name}")
        atlas.alpha_composite(asset, dest=position)
        built[group_name]["atlas_position"] = list(position)

    atlas_path = OUTPUT / "ktn_rc3_m01_front_atlas.png"
    atlas.save(atlas_path, optimize=True)

    reassembled = Image.new("RGBA", source.size, (0, 0, 0, 0))
    for group_name in DRAW_ORDER:
        reassembled.alpha_composite(full_group_images[group_name])
    reassembled_path = OUTPUT / "ktn_rc3_m01_front_reassembled.png"
    reassembled.save(reassembled_path, optimize=True)

    manifest = {
        "schema_version": 1,
        "technical_model": "KTN-RC3-M01",
        "character": "kotone",
        "release": "rc3",
        "purpose": "whole_body_gbot_method_locomotion_mannequin",
        "status": "six_rgba_regions_built_mesh_authoring_pending",
        "source": "../../../source/kotone_front_mannequin_t_pose.png",
        "source_sha256": sha256(SOURCE),
        "atlas": "ktn_rc3_m01_front_atlas.png",
        "atlas_size": list(ATLAS_SIZE),
        "atlas_sha256": sha256(atlas_path),
        "reassembled_preview": "ktn_rc3_m01_front_reassembled.png",
        "reassembled_sha256": sha256(reassembled_path),
        "draw_order_back_to_front": DRAW_ORDER,
        "assets": built,
        "construction": "deterministic_composite_of_approved_registration_parts",
        "mesh_authoring": "pending_godot_editor_polygon2d_uv_cells_sync_and_weights",
        "anatomical_refinement_model": "KTN-RC3-M02",
    }
    (OUTPUT / "m01_asset_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )

    print("KTN-RC3-M01 SIX-ASSET BUILD COMPLETE")


if __name__ == "__main__":
    main()
