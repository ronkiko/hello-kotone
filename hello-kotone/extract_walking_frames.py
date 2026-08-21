#!/usr/bin/env python3
"""Extract six walking frames from the bordered reference sheets."""

from __future__ import annotations

import argparse
import re
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


ORDERS = {
    "walking": ("front", "back", "left", "right"),
    "idle": ("right", "left", "front", "back"),
}
FRAME_SIZE = 130


def groups(mask: np.ndarray) -> list[tuple[int, int]]:
    result = []
    start = None
    for index, value in enumerate(mask):
        if value and start is None:
            start = index
        elif not value and start is not None:
            result.append((start, index - 1))
            start = None
    if start is not None:
        result.append((start, len(mask) - 1))
    return result


def find_frame_rectangles(rgb: np.ndarray) -> list[tuple[int, int, int, int]]:
    height, width = rgb.shape[:2]
    dark = rgb.mean(axis=2) < 140
    body_top = int(height * 0.14)
    body_bottom = int(height * 0.88)

    vertical_counts = dark[body_top:body_bottom].sum(axis=0)
    vertical_mask = vertical_counts >= (body_bottom - body_top) * 0.8
    vertical = [group for group in groups(vertical_mask) if group[1] - group[0] <= 6]
    if len(vertical) != 12:
        raise RuntimeError(f"expected 12 vertical borders, found {len(vertical)}: {vertical}")

    rectangles = []
    for frame in range(6):
        left = vertical[frame * 2][1] + 1
        right = vertical[frame * 2 + 1][0] - 1
        horizontal_counts = dark[:, left:right + 1].sum(axis=1)
        horizontal_mask = horizontal_counts >= (right - left + 1) * 0.8
        horizontal = [
            group for group in groups(horizontal_mask)
            if group[1] - group[0] <= 6 and group[0] > body_top - 30 and group[1] < body_bottom + 30
        ]
        if len(horizontal) != 2:
            raise RuntimeError(f"frame {frame}: expected 2 horizontal borders, found {horizontal}")
        top = horizontal[0][1] + 1
        bottom = horizontal[1][0] - 1
        rectangles.append((left, top, right, bottom))
    return rectangles


def largest_component(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    best = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or visited[y, x]:
                continue
            queue = deque([(y, x)])
            visited[y, x] = True
            component = []
            while queue:
                cy, cx = queue.popleft()
                component.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if not (dy or dx):
                            continue
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            queue.append((ny, nx))
            if len(component) > len(best):
                best = component
    result = np.zeros_like(mask, dtype=bool)
    for y, x in best:
        result[y, x] = True
    return result


def remove_checker_background(rgb: np.ndarray) -> np.ndarray:
    gray = rgb.mean(axis=2)
    near_gray = rgb.max(axis=2) - rgb.min(axis=2) <= 10
    background_candidate = near_gray & (gray > 220)
    height, width = background_candidate.shape
    background = np.zeros_like(background_candidate, dtype=bool)
    queue = deque()
    for x in range(width):
        if background_candidate[0, x]:
            queue.append((0, x))
        if background_candidate[height - 1, x]:
            queue.append((height - 1, x))
    for y in range(height):
        if background_candidate[y, 0]:
            queue.append((y, 0))
        if background_candidate[y, width - 1]:
            queue.append((y, width - 1))
    while queue:
        y, x = queue.popleft()
        if background[y, x]:
            continue
        background[y, x] = True
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < height and 0 <= nx < width and background_candidate[ny, nx] and not background[ny, nx]:
                queue.append((ny, nx))
    return largest_component(~background)


def extract_sheet(source: Path, destination: Path) -> None:
    rgb = np.array(Image.open(source).convert("RGB"))
    rectangles = find_frame_rectangles(rgb)
    crops = []
    for left, top, right, bottom in rectangles:
        cell = rgb[top:bottom + 1, left:right + 1]
        mask = remove_checker_background(cell)
        ys, xs = np.where(mask)
        if len(xs) == 0:
            raise RuntimeError(f"no foreground found in {source} frame {(left, top, right, bottom)}")
        crops.append((cell, mask, (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))))

    side = max(max(x2 - x1 + 1, y2 - y1 + 1) for _, _, (x1, y1, x2, y2) in crops) + 12
    sheet = Image.new("RGBA", (FRAME_SIZE * 6, FRAME_SIZE), (0, 0, 0, 0))
    for index, (cell, mask, (x1, y1, x2, y2)) in enumerate(crops):
        bottom = y2 + 6
        top = bottom - side
        # Keep the frame-box center fixed. A walking leg can extend far to one
        # side, so centering on the full silhouette would move the torso.
        center_x = cell.shape[1] // 2
        left = center_x - side // 2
        canvas = np.zeros((side, side, 4), dtype=np.uint8)
        src_x1 = max(0, left)
        src_y1 = max(0, top)
        src_x2 = min(cell.shape[1], left + side)
        src_y2 = min(cell.shape[0], top + side)
        dst_x1 = src_x1 - left
        dst_y1 = src_y1 - top
        dst_x2 = dst_x1 + (src_x2 - src_x1)
        dst_y2 = dst_y1 + (src_y2 - src_y1)
        canvas[dst_y1:dst_y2, dst_x1:dst_x2, :3] = cell[src_y1:src_y2, src_x1:src_x2]
        canvas[dst_y1:dst_y2, dst_x1:dst_x2, 3] = mask[src_y1:src_y2, src_x1:src_x2] * 255
        frame = Image.fromarray(canvas, "RGBA").resize((FRAME_SIZE, FRAME_SIZE), Image.Resampling.LANCZOS)
        sheet.paste(frame, (index * FRAME_SIZE, 0), frame)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)
    print(f"{source.name}: {rectangles} -> {destination}")


def mirror_sheet(source: Path, destination: Path) -> None:
    sheet = Image.open(source).convert("RGBA")
    mirrored = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    for index in range(6):
        frame = sheet.crop((index * FRAME_SIZE, 0, (index + 1) * FRAME_SIZE, FRAME_SIZE))
        mirrored.paste(frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (index * FRAME_SIZE, 0))
    mirrored.save(destination)
    print(f"mirrored {source} -> {destination}")


def source_files(source_dir: Path) -> list[Path]:
    candidates = sorted(source_dir.glob("*.png"))
    numbered = []
    for path in candidates:
        match = re.search(r"\((\d+)\)\.png$", path.name)
        if match:
            numbered.append((int(match.group(1)), path))
    numbered.sort()
    if len(numbered) != 4 or [number for number, _ in numbered] != [1, 2, 3, 4]:
        raise RuntimeError("expected four PNG sources ending in (1).png through (4).png")
    return [path for _, path in numbered]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=ORDERS)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/kotone-v2/rc2/frames"))
    args = parser.parse_args()
    default_source_dir = "walk" if args.kind == "walking" else "idle"
    source_dir = args.source_dir or Path(f"kotone-sprites-reference/kotone-v2-raw/rc2/{default_source_dir}")
    for direction, source in zip(ORDERS[args.kind], source_files(source_dir)):
        extract_sheet(source, args.output_dir / f"{args.kind}_{direction}.png")
    if args.kind == "walking":
        # The current left reference does not preserve the right-side phase order.
        mirror_sheet(args.output_dir / "walking_right.png", args.output_dir / "walking_left.png")


if __name__ == "__main__":
    main()
