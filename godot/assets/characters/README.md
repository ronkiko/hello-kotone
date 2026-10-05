# Canonical character animation assets

This directory is the canonical raster authoring/runtime package for humanoid
character animation.

## Layout

```text
characters/
  <character_model_id>/
    idle/
      000.png
      001.png
      ...
    walk_left/
      000.png
      001.png
      ...
    walk_right/
      000.png
      001.png
      ...
    sprite_frames.tres
```

Each frame PNG must already satisfy Character Sprite Frame Contract v1:

- RGBA PNG;
- exactly 256x256;
- ground-contact pivot at pixel (128,236);
- baseline y=236;
- body height derived from `physical_height_cm` at raster-v1 projection 1 cm = 1 px;
- no per-animation scale compensation.

Frame filenames are zero-based, contiguous and zero-padded: `000.png`,
`001.png`, ...

`sprite_frames.tres` is a native Godot `SpriteFrames` resource. It owns
animation ordering, speed/duration and loop semantics. Do not add a parallel
custom animation JSON unless a future requirement cannot be represented by
`SpriteFrames`.

## Runtime rule

Gameplay/server semantics only carry `character_model_id`. Godot resolves that
semantic id to the local package:

```text
res://assets/characters/<character_model_id>/sprite_frames.tres
```

There is no silent fallback to another model.

Manual spritesheets are not canonical runtime assets. Existing historical sheets
outside this directory are source/reference material for offline extraction. A
future build pipeline may atlas canonical frames automatically without changing
this directory contract.


## Offline toolchain

Use one entry point:

```text
python godot/tools/character_assets.py doctor

python godot/tools/character_assets.py extract-grid \
  --source references/yuna/v1/yuna_idle.png \
  --output-dir /tmp/yuna-idle-raw \
  --columns 8 --rows 2

python godot/tools/character_assets.py inspect \
  --model yuna \
  --animation idle \
  --source-dir /tmp/yuna-idle-raw \
  --output-dir /tmp/yuna-idle-analysis

# Optional: create a low-confidence automatic draft for review.
python godot/tools/character_assets.py detect-plan \
  --model yuna \
  --animation idle \
  --source-dir /tmp/yuna-idle-raw \
  --output /tmp/yuna-idle-draft-plan.json

# Give analysis-board.png + analysis-packet.json and optionally the draft plan
# to an LLM or human reviewer. Reviewer returns/revises a v1 normalization plan.

python godot/tools/character_assets.py normalize \
  --plan /tmp/yuna-idle-plan.json \
  --source-dir /tmp/yuna-idle-raw \
  --output-dir godot/assets/characters/yuna/idle

python godot/tools/character_assets.py validate yuna --frames-only

python godot/tools/character_assets.py build-spriteframes \
  --model yuna \
  --animation idle=3.333333:true \
  --animation walk_left=8:true \
  --animation walk_right=8:true

python godot/tools/character_assets.py validate yuna
```

Dependencies are deliberately narrow:

- Python 3 standard library;
- ImageMagick for raster crop/cleanup/scale/composite/diagnostics;
- Godot 4 to serialize native `SpriteFrames.tres`.

Do not add Pillow/OpenCV just to perform operations already covered by ImageMagick.

### LLM-assisted analysis

`inspect` creates:

- `analysis-board.png` — source frames with coordinate grid overlays;
- `analysis-packet.json` — exact source dimensions, diagnostic alpha bounds,
  canonical target dimensions, and instructions for the reviewer.

The LLM/human reviewer returns a plan matching:

```text
godot/tools/character_asset_normalization_plan.schema.json
```

Example:

```json
{
  "schema": 1,
  "character_model_id": "yuna",
  "animation_id": "idle",
  "source_body_height_px": 350.0,
  "analysis": {
    "method": "human_reviewed_llm",
    "confidence": 0.95,
    "notes": "Body scale measured from anatomical crown to ground root; hair excluded."
  },
  "frames": [
    {"file": "000.png", "source_root_px": [124.0, 380.0], "confidence": 0.98},
    {"file": "001.png", "source_root_px": [124.5, 380.0], "confidence": 0.96}
  ]
}
```

The important split is:

- **LLM/human chooses semantics**: anatomical scale and source root points;
- **ImageMagick applies pixels deterministically**;
- **Godot builds the runtime resource**.

The optional `detect-plan` command estimates a first draft from silhouette geometry
(bottom-band contact center + median alpha silhouette height). It is intentionally
marked `analysis.method = "script_heuristic"` and is **not accepted by
`normalize` by default**. An LLM/human should review it and change the analysis
method to a reviewed value. Explicit bypass exists only as
`--accept-unreviewed-heuristic` for controlled experiments.

The plan has one `source_body_height_px` for the whole animation. Per-frame scale
is intentionally impossible. Each frame may have a different source root only to
remove authored drift while preserving the same body scale.

For old matte-backed source art the plan may additionally include:

```json
"source_cleanup": {
  "transparent_color": "#466F4B",
  "fuzz_percent": 6
}
```

Cleanup belongs to offline source conversion. Canonical runtime PNGs must already
be RGBA with transparent background.
