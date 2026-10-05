# Agent-coordinated frame preparation

`frame_tools.py` provides independent, atomic raster operations. It has no
Godot/model/package dependency, no fixed frame size or pivot, and no automatic
end-to-end flow. `character_assets.py` forwards these same commands as a client
entry point; only `doctor`, `validate`, `build-spriteframes` know the MMO profile.

The agent chooses the source, operations and order. Inputs may be damaged sheets,
new sheets with 512×512 cells, irregular pose layouts, or individual frames in
formats ImageMagick can read. The tool does not discover an arbitrary silhouette
or decide whether a source needs cleanup. Inspect it and choose explicit regions
and cleanup parameters. Complex nonuniform backgrounds may need a reviewed mask
or another offline operation; do not silently claim a color key segments them.

## Atomic operations

| Operation | Input and result |
| --- | --- |
| `split-grid` | Explicit columns/rows → lossless source cells; pad incomplete last cells. |
| `extract` | One image and optional `--region X Y W H` → one pose; no scaling. |
| `clean` | One pose and explicit matte/fuzz/alpha floor → transparent pose, unchanged dimensions. |
| `resize` | One pose and explicit uniform factor → resized pose; coordinates scale with it. |
| `mirror` | One pose → horizontal mirror; pixel center x maps to width−1−x. |
| `prepare` | Canvas, ground, pivot, height in cm, px/cm → blank RGBA frame + specification. |
| `inspect` | One pose → grid overlay + coordinate/alpha diagnostics JSON. |
| `heuristic` | One pose → low-confidence silhouette suggestion; never applies it. |
| `place` | One pose + prepared specification + reviewed single-pose plan → one RGBA frame. |
| `render` | One image + background → preview suitable for visual inspection. |

Every operation writes only explicit outputs and preserves source files, including
with `--force`. Cleanup and placement are separate operations; neither runs the
other. Avoid extra resize steps when `place` can scale directly from source.
`prepare.ground_y_px` documents the floor line; `pivot_px` is the point to which
`place` maps the source root. The caller decides their relation (humanoid standing
profile uses pivot_y == ground_y).

## Metric source of truth

The prepared frame stores `physical_height_cm` and `pixels_per_cm` separately.
The agent measures anatomical source height in pixels from body crown to ground
reference; hair, hats, arms, padding and alpha bounds are not anatomical height.

```
target_body_height_px = physical_height_cm * pixels_per_cm
uniform_scale = target_body_height_px / source_body_height_px
```

For related poses, choose one model scale in the original source units. Different
source resolutions require corresponding source-height measurements, preserving
the same physical height. Do not adjust scale per pose to erase natural posture.

## Example: one 512×512 source pose

```
python godot/tools/frame_tools.py extract --source pose.webp --output /tmp/raw.png
python godot/tools/frame_tools.py inspect --source /tmp/raw.png --output /tmp/inspect.png
python godot/tools/frame_tools.py heuristic --source /tmp/raw.png
python godot/tools/frame_tools.py prepare --canvas 320 320 --pivot 160 290 \
  --ground-y 290 --height-cm 180 --pixels-per-cm 1 --output /tmp/frame.json
# Agent inspects the source and writes a reviewed plan with its own coordinates.
python godot/tools/frame_tools.py place --source /tmp/raw.png \
  --frame-spec /tmp/frame.json --plan /tmp/pose-plan.json --output /tmp/frame.png
python godot/tools/frame_tools.py render --source /tmp/frame.png --output /tmp/preview.png
```

Plan format (`character_asset_normalization_plan.schema.json`):

```json
{"schema": 1, "source_root_px": [256, 470], "source_body_height_px": 400,
 "analysis": {"method": "llm", "confidence": 0.9,
              "notes": "Body crown at y70, stable ground root at y470; hair excluded."}}
```

`heuristic` output has `method=script_heuristic` and is deliberately rejected by
`place`. Review source pixels and replace the suggestions with reviewed values;
changing the label without visual review is not review. No LLM dependency exists
in raster operations or runtime. Coordinates use top-left origin/pixel centers.

## Current consumer: 7.11

Kotone/Yuna are application data: 172/155 cm, 1 px/cm, canvas 256×256, pivot
(128,236), ground y236. Source checksums, agent-chosen commands and individual
reviewed plans live in `character_recipes/locomotion_v1/`. Recorded commands can
be replayed deterministically; they are evidence of this conversion, not an
algorithm that chooses flows for future art.
