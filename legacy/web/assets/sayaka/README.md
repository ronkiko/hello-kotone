# Sayaka Sprite Pack

Separate second character model for the game. This pack is not connected to
the game code yet and does not replace Kotone.

## Format

- PNG RGBA with transparency
- One horizontal sheet per animation
- 6 frames per sheet
- 130x130 pixels per frame
- 780x130 pixels per file
- Frame order is left to right
- Left-facing sheets marked as mirrored use the designer's right-facing source

## Movement Sheets

| File | Meaning | Source |
| --- | --- | --- |
| `walking_front.png` | Walk toward camera | `renew/01_46_51` |
| `walking_back.png` | Walk away from camera | `renew/01_46_52 (2)` |
| `walking_left.png` | Walk left | `renew/01_46_52 (3)` |
| `walking_right.png` | Walk right | `renew/01_46_52 (4)` |
| `running_front.png` | Run toward camera | `renew/01_39_35 (2)`, row 1 |
| `running_back.png` | Run away from camera | `renew/01_39_35 (2)`, row 2 |
| `running_left.png` | Run left | Mirrored from the right profile |
| `running_right.png` | Run right | `renew/01_39_35 (2)`, row 3 |
| `sprinting_left.png` | Low sprint left | Mirrored from the right profile |
| `sprinting_right.png` | Low sprint right | `renew/01_39_35 (2)`, row 4 |
| `jumping_front.png` | Jump toward camera | `renew/01_39_35 (3)`, row 1 |
| `jumping_back.png` | Jump away from camera | `renew/01_39_35 (3)`, row 2 |
| `jumping_left.png` | Jump left | Mirrored from the right profile |
| `jumping_right.png` | Jump right | `renew/01_39_35 (3)`, row 3 |
| `jumping_low_left.png` | Low side jump left | Mirrored from the right profile |
| `jumping_low_right.png` | Low side jump right | `renew/01_39_35 (3)`, row 4 |
| `hurt_front.png` | Hurt/fall recovery, front | `renew/01_39_35 (4)`, row 1 |
| `hurt_back.png` | Hurt/fall recovery, back | `renew/01_39_35 (4)`, row 2 |
| `hurt_left.png` | Hurt/fall recovery, left | Mirrored from the right profile |
| `hurt_right.png` | Hurt/fall recovery, right | `renew/01_39_35 (4)`, row 3 |
| `hurt_low_left.png` | Low fall/recovery left | Mirrored from the right profile |
| `hurt_low_right.png` | Low fall/recovery right | `renew/01_39_35 (4)`, rows 3-4 |

## Idle Sheets

| File | Meaning | Source |
| --- | --- | --- |
| `idle_clap.png` | Clapping gesture | `renew/01_39_36`, row 1 |
| `idle_foldarm.png` | Folded arms | `renew/01_39_36`, row 2 |
| `idle_thinking.png` | Thinking gesture | `renew/01_39_37`, row 1 |
| `idle_waving.png` | Waving | `renew/01_39_37`, row 2 |
| `idle_heart.png` | Heart gesture | `renew/01_52_06 (1)`, row 1 |
| `idle_shy.png` | Shy/weight-shift idle | `renew/01_52_06 (1)`, row 2 |
| `idle_idea.png` | Idea/explanation gesture | `renew/01_52_06 (2)`, row 1 |
| `idle_ipad.png` | Tablet interaction | `renew/01_52_06 (2)`, row 2 |

## Extra

`special_box.png` is a six-frame interaction sequence with Sayaka inside a
cardboard box. It includes the box prop and its printed markings, so it is not
a replacement for a normal character sheet.

The `renew/01_39_34` atlas is retained as a visual reference and was not
duplicated into the production folder. The `renew/01_52_06` sheets use a 6x2
layout with 256x512 cells. `renew/02_17_15` has an opaque rain background and
is retained as an illustration reference. The `adult_...` file contains a
different adult combat character and is not part of Sayaka.
