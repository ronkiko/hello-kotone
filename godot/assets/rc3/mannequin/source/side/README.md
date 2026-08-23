# RC3 side mannequin sources

`kotone_side_left_mannequin_source.png` is the only available coherent side
turnaround source. It is a 135 x 914 RGBA image and faces viewer-left.

`kotone_side_arm_down_source.png` is the approved cleaned derivative of the
separately generated complete arm used to replace the turnaround's
camera-foreshortened near arm. The raw 1024 x 1536 generation contained a
transparent glow; M03 retains only the cropped 56 x 360 alpha-clean result so
the repository does not carry a one-megabyte non-runtime intermediate.

Neither source is a runtime texture. Run
`godot/scripts/mannequin/build_side_m03_assets.py` to normalize the body to the
approved 1254 x 1254 registration canvas, mirror it to viewer-right, and build
the first rig-ready M03 assets.

The original sources are immutable evidence. Visual corrections belong in a
new source version, never as an undocumented overwrite.
