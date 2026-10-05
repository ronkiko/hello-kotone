# Character asset LLM analysis protocol

Use this protocol together with the files produced by:

```text
python godot/tools/character_assets.py inspect ...
```

Inputs:

- `analysis-board.png`;
- `analysis-packet.json`;
- optionally the original extracted source frames.

- optionally a `detect-plan` heuristic draft produced by the tool.

Your task is **analysis only**. Do not redraw, edit, upscale, clean, crop, or
otherwise transform pixels.

Return one JSON object compatible with:

```text
godot/tools/character_asset_normalization_plan.schema.json
```

If a heuristic draft is supplied, treat it only as a suggestion. Check every
root against the images and replace `analysis.method = "script_heuristic"` with
`"llm_reviewed_heuristic"` only after review.

## Required semantic decisions

1. Determine one `source_body_height_px` for the whole animation.
   - This represents the anatomical model scale in the source.
   - It is not alpha-bounding-box height.
   - Ignore hair volume, hats, raised arms, loose clothing and effects.
   - Do not choose a different scale for each frame.
2. For every frame determine `source_root_px = [x,y]`.
   - Root semantic: ground-contact center under the body.
   - For a standing pose it is centered between the feet on the floor.
   - For a walking pose it is the stable character/world root, not whichever foot
     extends furthest.
   - Use source image pixel coordinates with origin at top-left.
3. If source art has a uniform matte/background, optionally propose
   `source_cleanup.transparent_color` and conservative `fuzz_percent`.
4. Include confidence and notes where ambiguous.

## Invariants

- Never derive target character height from the source art. Target height comes
  from `physical_height_cm` in the project contract.
- Never move the canonical target root. It is fixed by the project contract.
- Never request non-uniform scaling.
- Never compensate a pose by changing model scale.
- Never use alpha bbox as authority; it is diagnostic evidence only.
- If the source is ambiguous, say so in `notes` and lower confidence rather
  than inventing precision.

## Output example

```json
{
  "schema": 1,
  "character_model_id": "yuna",
  "animation_id": "idle",
  "source_body_height_px": 350.0,
  "analysis": {
    "method": "llm",
    "confidence": 0.94,
    "notes": "Common anatomical scale estimated from neutral standing frames."
  },
  "frames": [
    {
      "file": "000.png",
      "source_root_px": [124.0, 380.0],
      "confidence": 0.98
    },
    {
      "file": "001.png",
      "source_root_px": [124.5, 380.0],
      "confidence": 0.96
    }
  ]
}
```

Return JSON only when the plan is intended for direct tool consumption.
