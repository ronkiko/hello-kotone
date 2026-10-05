#!/usr/bin/env python3
"""Pure-Python checks for character_assets.py (no ImageMagick/Godot required)."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
MODULE_PATH = TOOLS / "character_assets.py"

spec = importlib.util.spec_from_file_location("character_assets_under_test", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL cannot import character_assets.py")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


checks = 0
failures: list[str] = []


def check(condition: bool, label: str) -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(label)


def expect_tool_error(fn, label: str) -> None:
    try:
        fn()
    except module.ToolError:
        check(True, label)
    else:
        check(False, label)


contract = module.load_contract()
check((contract.width, contract.height) == (256, 256), "frame contract")
check((contract.pivot_x, contract.pivot_y) == (128, 236), "pivot contract")
check(contract.target_height_px("kotone") == 172, "Kotone metric projection")
check(contract.target_height_px("yuna") == 155, "Yuna metric projection")
expect_tool_error(lambda: contract.target_height_px("unknown"), "unknown model rejected")

with tempfile.TemporaryDirectory(prefix="character-assets-check-") as temp:
    root = Path(temp)

    source = root / "frames"
    source.mkdir()
    (source / "000.png").write_bytes(b"")
    (source / "001.png").write_bytes(b"")
    check([p.name for p in module.frame_files(source)] == ["000.png", "001.png"], "contiguous frame names")

    (source / "001.png").rename(source / "002.png")
    expect_tool_error(lambda: module.frame_files(source), "frame gap rejected")

    plan = {
        "schema": 1,
        "character_model_id": "yuna",
        "animation_id": "idle",
        "source_body_height_px": 350.0,
        "analysis": {
            "method": "llm_reviewed_heuristic",
            "confidence": 0.9,
        },
        "frames": [
            {"file": "000.png", "source_root_px": [124.0, 380.0], "confidence": 0.9},
            {"file": "001.png", "source_root_px": [124.5, 380.0], "confidence": 0.9},
        ],
    }
    plan_path = root / "plan.json"
    plan_path.write_text(json.dumps(plan), encoding="utf-8")
    loaded = module.load_plan(plan_path, contract)
    check(loaded["character_model_id"] == "yuna", "valid reviewed plan accepted")

    invalid = json.loads(json.dumps(plan))
    invalid["frames"][0]["scale"] = 0.9
    plan_path.write_text(json.dumps(invalid), encoding="utf-8")
    expect_tool_error(
        lambda: module.load_plan(plan_path, contract),
        "per-frame scale/unknown field rejected",
    )

    invalid = json.loads(json.dumps(plan))
    invalid["source_cleanup"] = {"fuzz_percent": 5}
    plan_path.write_text(json.dumps(invalid), encoding="utf-8")
    expect_tool_error(
        lambda: module.load_plan(plan_path, contract),
        "fuzz without matte color rejected",
    )

    invalid = json.loads(json.dumps(plan))
    invalid["analysis"]["method"] = "magic"
    plan_path.write_text(json.dumps(invalid), encoding="utf-8")
    expect_tool_error(
        lambda: module.load_plan(plan_path, contract),
        "unknown analysis method rejected",
    )

result = {
    "suite": "character-assets-tool",
    "checks": checks,
    "failures": failures,
    "result": "PASS" if not failures else "FAIL",
}
print(json.dumps(result))
raise SystemExit(0 if not failures else 1)
