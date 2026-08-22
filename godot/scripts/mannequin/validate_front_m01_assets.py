#!/usr/bin/env python3
"""Validate KTN-RC3-M01 transparency, hashes and neutral reconstruction."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "godot/assets/rc3/mannequin/godot_mesh/front/m01"
MANIFEST_PATH = MODEL_DIR / "m01_asset_manifest.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    require(MANIFEST_PATH.is_file(), "missing M01 manifest")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    require(manifest["technical_model"] == "KTN-RC3-M01", "wrong model number")
    require(set(manifest["assets"]) == {"arm_right", "arm_left", "leg_right", "leg_left", "body", "head"}, "wrong asset set")

    atlas_path = MODEL_DIR / manifest["atlas"]
    atlas = Image.open(atlas_path)
    require(atlas.mode == "RGBA", "atlas is not RGBA")
    require(list(atlas.size) == manifest["atlas_size"], "atlas size mismatch")
    require(sha256(atlas_path) == manifest["atlas_sha256"], "atlas hash mismatch")
    require(atlas.getpixel((0, 0))[3] == 0, "atlas border is not transparent")

    for name, asset in manifest["assets"].items():
        path = MODEL_DIR / asset["file"]
        image = Image.open(path)
        require(image.mode == "RGBA", f"{name} is not RGBA")
        require(list(image.size) == asset["size"], f"{name} size mismatch")
        require(sha256(path) == asset["sha256"], f"{name} hash mismatch")
        alpha = image.getchannel("A")
        require(alpha.getbbox() == (0, 0, image.width, image.height), f"{name} is not tightly trimmed")
        require(alpha.getextrema() == (0, 255), f"{name} lacks real transparency or opacity")

    source = Image.open(ROOT / "godot/assets/rc3/mannequin/source/kotone_front_mannequin_t_pose.png").convert("RGBA")
    reassembled = Image.open(MODEL_DIR / manifest["reassembled_preview"]).convert("RGBA")
    require(source.size == reassembled.size, "neutral reconstruction canvas mismatch")
    difference = ImageChops.difference(source, reassembled)
    require(difference.getbbox() is None, "six assets do not reconstruct the approved neutral source exactly")

    print("KTN-RC3-M01 SIX-ASSET STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
