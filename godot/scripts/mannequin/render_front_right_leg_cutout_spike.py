#!/usr/bin/env python3
"""Render deterministic Task 4E QA without requiring a display server."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


GODOT_ROOT = Path(__file__).resolve().parents[2]
MANNEQUIN_ROOT = GODOT_ROOT / "assets/rc3/mannequin"
PARTS_DIR = MANNEQUIN_ROOT / "parts/front"
PREVIEW_DIR = MANNEQUIN_ROOT / "preview"
MANIFEST = json.loads((PARTS_DIR / "front_parts_manifest.json").read_text())
RECORDS = {record["name"]: record for record in MANIFEST["parts"]}
HIP = (555, 565)
POSES = [
    (4.0, "4° ABDUCTION"),
    (0.0, "NEUTRAL"),
    (-4.0, "4° ADDUCTION"),
]
THEMES = [
    ("task4e_front_right_leg_cutout.png", "#eeeae5", "#faf8f5", "#27232b"),
    ("task4e_front_right_leg_cutout_dark.png", "#11141a", "#1d222b", "#f4f0eb"),
    ("task4e_front_right_leg_cutout_magenta.png", "#4a0c37", "#68134d", "#fff4fb"),
]


def load_part(name: str) -> Image.Image:
    return Image.open(PARTS_DIR / RECORDS[name]["file"]).convert("RGBA")


def place(canvas: Image.Image, name: str) -> None:
    canvas.alpha_composite(load_part(name), tuple(RECORDS[name]["offset"]))


def pose(angle: float) -> Image.Image:
    canvas_size = tuple(MANIFEST["canvas"])
    leg = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    for name in ("foot_right", "calf_right", "thigh_right"):
        place(leg, name)
    rotated = leg.rotate(angle, resample=Image.Resampling.BICUBIC, center=HIP)
    place(rotated, "pelvis")
    return rotated


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    return ImageFont.truetype(path, size) if path.exists() else ImageFont.load_default()


def render_theme(filename: str, background: str, panel: str, ink: str) -> None:
    width, height, panel_width = 1500, 900, 500
    output = Image.new("RGB", (width, height), background)
    draw = ImageDraw.Draw(output)
    title_font = font(20)
    label_font = font(28)
    title = "KOTONE / FRONT ANATOMICAL RIGHT LEG (VIEWER-LEFT) / CUTOUT HIP RANGE SPIKE"
    title_box = draw.textbbox((0, 0), title, font=title_font)
    draw.text(((width - (title_box[2] - title_box[0])) / 2, 15), title, fill=ink, font=title_font)

    crop_box = (430, 390, 780, 1190)
    for index, (angle, label) in enumerate(POSES):
        x0 = index * panel_width + 24
        draw.rectangle((x0, 94, x0 + panel_width - 48, 860), fill=panel)
        posed = pose(angle).crop(crop_box)
        output.paste(posed, (index * panel_width + 75, 95), posed)
        label_box = draw.textbbox((0, 0), label, font=label_font)
        label_width = label_box[2] - label_box[0]
        draw.text((index * panel_width + (panel_width - label_width) / 2, 52), label, fill=ink, font=label_font)

    output.save(PREVIEW_DIR / filename)


def main() -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        render_theme(*theme)
        print(f"WROTE: {PREVIEW_DIR / theme[0]}")
    print("STATIC QA RENDER COMPLETE")


if __name__ == "__main__":
    main()
