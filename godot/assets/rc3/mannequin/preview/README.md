# Mannequin QA previews

- `task4c_front_mannequin_checker.png`: alpha overview;
- `task4c_front_mannequin_dark.png`: light-edge and halo check;
- `task4c_front_mannequin_magenta.png`: leftover background check;
- `task4c_front_mannequin_compare.png`: clothed reference and mannequin at the
  same canvas registration.

These files are review evidence and are not loaded by runtime scenes.

Task 4D adds:

- `task4d_front_parts_contact.png`: all 15 named trimmed parts;
- `task4d_front_parts_reassembled.png`: transparent reconstruction using only
  the trimmed parts and manifest offsets;
- checker, dark and magenta reconstruction checks.

Task 4E adds light, dark and magenta comparisons of the anatomical-right leg at
4-degree abduction, neutral and 4-degree adduction. These are a hip-range and
joint-overlap test, not a walk cycle. The committed images were rendered by
Godot 4.7.2 under GL/Xvfb and passed runtime review in commit `87a291f`.
