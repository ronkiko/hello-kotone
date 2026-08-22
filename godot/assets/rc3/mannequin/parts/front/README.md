# Front mannequin parts

This directory contains 15 transparent front-view cutout parts extracted from
the approved mannequin source. Left/right names are anatomical, not screen
directions.

`front_parts_manifest.json` records each trimmed image's original canvas
offset, global and local pivot, SHA-256 and back-to-front assembly order.
Adjacent parts deliberately share source pixels around every joint. This
hidden overlap prevents transparent gaps when a child rotates.

Run `python3 scripts/mannequin/validate_front_parts.py` from `godot/` before
using the parts. The validator proves hashes, dimensions, pivots, required
overlaps and pixel-exact neutral-pose reconstruction.
