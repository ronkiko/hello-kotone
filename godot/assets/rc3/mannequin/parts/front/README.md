# Front mannequin parts

This directory contains 15 transparent front-view cutout parts extracted from
the approved mannequin source. Left/right names are anatomical, not screen
directions. These files are now registration and joint-center references for
the gBot-method full mannequin; they are not production deformation assets.

`front_parts_manifest.json` records each trimmed image's original canvas
offset, global and local pivot, SHA-256 and back-to-front assembly order.
Adjacent parts deliberately share source pixels around every joint. This
hidden overlap prevents transparent gaps when a child rotates.

Do not build the successor rig from three independently rotated rectangles per
limb. The active method uses one continuous Polygon2D texture island for each
whole arm and each whole leg. See
`references/rc3/FULL_HUMANOID_REFERENCE_BLUEPRINT.md`.

Run `python3 scripts/mannequin/validate_front_parts.py` from `godot/` before
using the parts. The validator proves hashes, dimensions, pivots, required
overlaps and pixel-exact neutral-pose reconstruction.
