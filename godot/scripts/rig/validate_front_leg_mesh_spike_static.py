#!/usr/bin/env python3
"""Validate the Task 4B mesh without importing or running Godot."""

from __future__ import annotations

import math
import re
from pathlib import Path


SCENE = Path(__file__).parents[2] / "scenes/rig/kotone_front_leg_mesh_spike.tscn"
PIVOT_KNEE = (555.0, 765.0)
PIVOT_ANKLE = (555.0, 1040.0)
DEPTH_ANGLE = 40.0
PROJECTED_LENGTH = math.cos(math.radians(DEPTH_ANGLE))


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


def knee_depth_projection(point: tuple[float, float]) -> tuple[float, float]:
    return point[0], PIVOT_KNEE[1] + PROJECTED_LENGTH * (point[1] - PIVOT_KNEE[1])


def ankle_counter_projection(point: tuple[float, float]) -> tuple[float, float]:
    shift = (PROJECTED_LENGTH - 1.0) * (PIVOT_ANKLE[1] - PIVOT_KNEE[1])
    return point[0], point[1] + shift


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

    # A front view cannot show knee flexion by rotating the calf sideways.
    # Orthographic depth flexion is represented by cosine foreshortening of the
    # calf. The ankle gets the reciprocal scale, so the shoe keeps its shape and
    # is translated upward instead of being squashed.
    transformed: list[tuple[float, float]] = []
    for index, point in enumerate(vertices):
        hip, knee, ankle = (slot[index] for slot in weights)
        projected = knee_depth_projection(point)
        counter_projected = ankle_counter_projection(point)
        transformed.append(
            (
                hip * point[0] + knee * projected[0] + ankle * counter_projected[0],
                hip * point[1] + knee * projected[1] + ankle * counter_projected[1],
            )
        )

    max_lateral_error = max(abs(before[0] - after[0]) for before, after in zip(vertices, transformed))
    assert max_lateral_error < 1e-6, f"depth proxy moved the calf sideways by {max_lateral_error}px"

    for index, ((_, y), (_, transformed_y)) in enumerate(zip(vertices, transformed)):
        if y <= 725.0:
            assert abs(transformed_y - y) < 1e-6, f"thigh vertex {index} moved"
        elif 795.0 <= y <= 1000.0:
            expected_y = PIVOT_KNEE[1] + PROJECTED_LENGTH * (y - PIVOT_KNEE[1])
            assert abs(transformed_y - expected_y) < 1e-6, f"calf vertex {index} is not foreshortened"
        elif y >= 1075.0:
            expected_y = ankle_counter_projection((0.0, y))[1]
            assert abs(transformed_y - expected_y) < 1e-6, f"shoe vertex {index} is distorted"

    print(f"PASS: {len(vertices)} vertices; 3 normalized localized weight slots")
    print("PASS: hip/knee crossover Y=765; knee/ankle crossover Y=1040")
    print(f"PASS: {DEPTH_ANGLE:.0f}-degree depth proxy uses cosine scale {PROJECTED_LENGTH:.6f}")
    print(f"PASS: no sideways knee motion (max lateral error {max_lateral_error:.9f}px)")
    print("PASS: calf foreshortens while ankle counter-scale preserves the shoe")
    print("STATIC VALIDATION PASSED")


if __name__ == "__main__":
    main()
