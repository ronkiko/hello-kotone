#!/usr/bin/env python3
"""Validate the Task 4B mesh without importing or running Godot."""

from __future__ import annotations

import math
import re
from pathlib import Path


SCENE = Path(__file__).parents[2] / "scenes/rig/kotone_front_leg_mesh_spike.tscn"
PIVOT_KNEE = (555.0, 765.0)


def parse_numbers(payload: str) -> list[float]:
    return [float(value.strip()) for value in payload.split(",")]


def expected_weights(y: float) -> tuple[float, float, float]:
    if y <= 735.0:
        return 1.0, 0.0, 0.0
    if y < 795.0:
        knee = (y - 735.0) / 60.0
        return 1.0 - knee, knee, 0.0
    if y <= 1010.0:
        return 0.0, 1.0, 0.0
    if y < 1070.0:
        ankle = (y - 1010.0) / 60.0
        return 0.0, 1.0 - ankle, ankle
    return 0.0, 0.0, 1.0


def rotate(point: tuple[float, float], pivot: tuple[float, float], degrees: float) -> tuple[float, float]:
    angle = math.radians(degrees)
    cosine, sine = math.cos(angle), math.sin(angle)
    dx, dy = point[0] - pivot[0], point[1] - pivot[1]
    return pivot[0] + dx * cosine - dy * sine, pivot[1] + dx * sine + dy * cosine


def main() -> None:
    text = SCENE.read_text(encoding="utf-8")
    polygon_match = re.search(r"^polygon = PackedVector2Array\((.*?)\)$", text, re.MULTILINE)
    if polygon_match is None:
        raise SystemExit("FAIL: polygon array not found")
    coordinates = parse_numbers(polygon_match.group(1))
    vertices = list(zip(coordinates[0::2], coordinates[1::2]))

    bones_match = re.search(r"^bones = \[(.*?)\]$", text, re.MULTILINE)
    if bones_match is None:
        raise SystemExit("FAIL: bones array not found")
    weight_payloads = re.findall(r"PackedFloat32Array\((.*?)\)", bones_match.group(1))
    weights = [parse_numbers(payload) for payload in weight_payloads]

    assert len(vertices) == 72, f"expected 72 vertices, got {len(vertices)}"
    assert len(weights) == 3, f"expected 3 weight slots, got {len(weights)}"
    assert all(len(slot) == len(vertices) for slot in weights), "weight count differs from vertex count"

    for index, (_, y) in enumerate(vertices):
        actual = tuple(slot[index] for slot in weights)
        expected = expected_weights(y)
        assert abs(sum(actual) - 1.0) < 0.001, f"vertex {index} is not normalized: {actual}"
        assert all(abs(a - e) < 0.001 for a, e in zip(actual, expected)), (
            f"vertex {index} at y={y} has {actual}, expected {expected}"
        )

    # A knee-only pose gives knee and its ankle descendant the same rigid
    # transform. Below the narrow knee blend, hip weight must therefore be zero
    # and every mesh edge must preserve its length exactly.
    transformed: list[tuple[float, float]] = []
    for index, point in enumerate(vertices):
        hip, knee, ankle = (slot[index] for slot in weights)
        rotated = rotate(point, PIVOT_KNEE, 45.0)
        transformed.append(
            (
                hip * point[0] + (knee + ankle) * rotated[0],
                hip * point[1] + (knee + ankle) * rotated[1],
            )
        )

    rigid_indices = [index for index, (_, y) in enumerate(vertices) if y >= 795.0]
    max_distance_error = 0.0
    for left, right in zip(rigid_indices, rigid_indices[1:]):
        before = math.dist(vertices[left], vertices[right])
        after = math.dist(transformed[left], transformed[right])
        max_distance_error = max(max_distance_error, abs(before - after))
    assert max_distance_error < 1e-6, f"calf is not rigid: max edge error {max_distance_error}"

    print(f"PASS: {len(vertices)} vertices; 3 normalized localized weight slots")
    print("PASS: hip/knee crossover Y=765; knee/ankle crossover Y=1040")
    print(f"PASS: 45-degree knee test keeps rigid section exact (max edge error {max_distance_error:.9f}px)")
    print("STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
