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
