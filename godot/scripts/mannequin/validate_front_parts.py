#!/usr/bin/env python3
"""Validate RC3 front mannequin cutout parts without starting Godot."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops


GODOT_ROOT = Path(__file__).resolve().parents[2]
PARTS_DIR = GODOT_ROOT / "assets/rc3/mannequin/parts/front"
MANIFEST_PATH = PARTS_DIR / "front_parts_manifest.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def full_alpha(image: Image.Image, offset: tuple[int, int], canvas: tuple[int, int]) -> Image.Image:
    result = Image.new("L", canvas, 0)
    result.paste(image.getchannel("A"), offset)
    return result


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text())
    canvas_size = tuple(manifest["canvas"])
    source_path = (PARTS_DIR / manifest["source"]).resolve()
    assert digest(source_path) == manifest["source_sha256"], "source hash mismatch"
    source = Image.open(source_path).convert("RGBA")
    assert source.size == canvas_size, "source canvas mismatch"

    records = {record["name"]: record for record in manifest["parts"]}
    assert len(records) == 15, "expected 15 unique front parts"
    images: dict[str, Image.Image] = {}
    masks: dict[str, Image.Image] = {}

    for name, record in records.items():
        path = PARTS_DIR / record["file"]
        assert digest(path) == record["sha256"], f"{name}: hash mismatch"
        image = Image.open(path).convert("RGBA")
        assert list(image.size) == record["size"], f"{name}: size mismatch"
        offset = tuple(record["offset"])
        pivot_global = record["pivot_global"]
        pivot_local = record["pivot_local"]
        assert [pivot_global[0] - offset[0], pivot_global[1] - offset[1]] == pivot_local, f"{name}: pivot mismatch"
        images[name] = image
        masks[name] = full_alpha(image, offset, canvas_size)

    assembled = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    for name in manifest["layer_order_back_to_front"]:
        assembled.alpha_composite(images[name], tuple(records[name]["offset"]))
    difference = ImageChops.difference(source, assembled)
    assert difference.getbbox() is None, "parts do not reassemble pixel-exactly"

    for parent, child in manifest["required_overlap_pairs"]:
        overlap = ImageChops.multiply(masks[parent], masks[child])
        overlap_pixels = sum(1 for value in overlap.get_flattened_data() if value > 0)
        assert overlap_pixels >= 40, f"{parent}/{child}: insufficient hidden overlap ({overlap_pixels})"
        print(f"PASS: {parent} <-> {child} overlap={overlap_pixels}px")

    print("PASS: 15 RGBA parts reassemble pixel-exactly to the approved 1254x1254 source")
    print("FRONT PARTS VALIDATION PASSED")


if __name__ == "__main__":
    main()
