# KTN-RC3-M01

This is the first complete technical locomotion mannequin for RC3.

- `parts/` contains six continuous RGBA regions: two arms, two legs, body and
  head.
- `ktn_rc3_m01_front_atlas.png` packs the same six regions for Polygon2D UV
  authoring.
- `ktn_rc3_m01_front_reassembled.png` is QA evidence. It is pixel-identical to
  the approved neutral T-pose source.
- `m01_asset_manifest.json` records source composition, offsets, atlas
  positions and hashes.

M01 deliberately reuses the approved neutral registration art. Its purpose is
to reproduce the official gBot construction and prove whole-body movement. Do
not redraw elbows or other joints during M01 assembly. Anatomical art and mesh
refinement belongs to `KTN-RC3-M02` after M01 locomotion passes.

Regenerate and validate from the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 godot/scripts/mannequin/build_front_m01_assets.py
PYTHONDONTWRITEBYTECODE=1 python3 godot/scripts/mannequin/validate_front_m01_assets.py
```
