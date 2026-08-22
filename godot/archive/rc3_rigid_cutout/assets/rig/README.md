# Kotone RC3 rig artwork

This directory contains the prepared artwork output of RC3 Task 3.

## Contents

- `master/kotone_side_right_master.png` — visual neutral assembly and proportion reference.
- `parts/` — 29 normalized transparent PNG layers.
- `rig_manifest.json` — bone ownership, default z-order and pivot hints.
- `preview/task3_contact_sheet.png` — visual QA sheet for the master and every part.

## Production decisions

- Direction master: right.
- Left direction: horizontal mirror in Godot.
- Front/back: separate future rigs.
- No bag, watch, bracelets, earrings or necklace.
- Rolled blouse sleeves, centered lanyard and blank badge.
- Parts were normalized once during Task 3. Task 4 should keep texture scale at `1.0` and align bones/offsets rather than independently rescaling individual sprites.

## Known Task 4 work

- Fine-tune node offsets and exact joint positions in the Godot neutral assembly.
- Confirm skirt/hip overlap across the intended walk range.
- Preserve the canonical skirt construction: one fitted mini pencil skirt with a pronounced front slit over the forward leg and a rear walking vent. The openings must never read as shorts or separate leg holes.

## Alpha-mask QA

- Every rig part must be reviewed on both a bright chroma background and a dark background before use in Godot.
- The skirt openings and both the outside and inside of the lanyard loop are true alpha, not black or white fills.
- In the assembled rig, both thigh sprites must remain behind `pelvis_skirt` so the skirt openings reveal the tights rather than the scene background.
- Contrast QA sheets are stored in `preview/` and must be regenerated after any future extraction change.
- Confirm shoe/ankle overlap at heel contact and toe-off.
- Position face overlays on `head_base`; strict side profile may hide the far eye variants.
- Pivot values in the manifest are starting hints and must be visually checked in the assembled scene.

## Source lineage

The master and parts were derived with image editing from the approved RC2 right-walk and idle references. The generated checkerboard backgrounds were removed and all committed production PNGs were checked for a real alpha channel. Original RC1/RC2 references remain unchanged under `references/`.
