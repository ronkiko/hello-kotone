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


## Offline tools

See [atomic operations and agent protocol](../../tools/character_asset_llm_analysis.md).
Use `frame_tools.py` directly for arbitrary source art; `character_assets.py`
forwards its commands and additionally validates/builds this MMO package.

The agent chooses the flow and coordinates. Raster primitives do not know model
ids, canonical dimensions, ground, pivot, package folders or animation names.
`prepare` receives physical height in cm and explicit px/cm projection. `place`
uses a reviewed plan for one pose and performs a single uniform source transform.

Current source/checksum/plan/operation evidence is in
`tools/character_recipes/locomotion_v1`. Kotone has 6 frames per animation; Yuna
has 16 idle and 8 walk frames. Yuna left is an offline source mirror, with
x_left=width−1−x_right. Yuna idle discards alpha <=5% extraction residue offline.
No runtime matte/geometry correction is applied.

```
python godot/tools/character_assets.py doctor
python godot/tools/character_assets.py validate kotone yuna
python godot/tools/character_assets.py build-spriteframes --model kotone
python godot/tools/character_assets.py build-spriteframes --model yuna
```

Godot import must precede SpriteFrames build. ImageMagick performs raster
operations; Godot serializes native resources. Python stdlib only, no Pillow/OpenCV.
