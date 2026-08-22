# RC3 reference notes: official Skeleton2D Demo

## Why this project was selected

This is a current, runnable Godot Foundation project whose Asset Store entry
requires Godot 4.7. It contains a complete humanoid character rather than an
isolated bone or abstract mesh. The character has multiple movement
animations, a controller and weighted deformation of arms, legs, torso and
head.

The authoritative companion documentation is:

- https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html
- https://docs.godotengine.org/en/stable/classes/class_polygon2d.html
- https://docs.godotengine.org/en/stable/classes/class_skeleton2d.html
- https://docs.godotengine.org/en/stable/classes/class_bone2d.html

The tutorial currently carries a warning that its prose has not yet been
updated for Godot 4.7. For serialized scene structure and runtime behaviour,
prefer this downloaded 4.7 demo over assumptions inferred from the prose.

## Files to inspect first

- `player/player.tscn`: complete bones, meshes, weights and animations;
- `player/gBot.png`: the source texture atlas;
- `player/player.gd`: animation selection and movement controller;
- `project.godot`: standalone project configuration.

## Right-arm facts from the upstream scene

The deforming right arm is one continuous `Polygon2D`, not three overlapping
rigid sprites. It covers upper arm, elbow, forearm and hand and is bound to the
chain:

`Hip -> Chest -> RightArm -> RightForearm -> RightHand`

The serialized right-arm mesh contains:

- 19 vertices;
- 7 explicitly drawn polygon cells;
- weights only `0`, `0.5` and `1`;
- 10 vertices influenced by `RightArm`;
- 8 vertices influenced by `RightForearm`;
- 5 vertices influenced by `RightHand`.

Shared `0.5/0.5` vertices occur at both the elbow and wrist. The mesh cells are
drawn explicitly across the joints; Godot is not allowed to invent the whole
triangulation from only a silhouette.

## Immediate implication for RC3

The official example supports the continuous-limb approach, but it also shows
that our current Task 4I assumptions must not be treated as validated merely
because their weight values resemble the demo. We must compare, in the Godot
editor, all of the following before building another Kotone mesh:

1. the `Polygon2D` node transform and texture/UV registration;
2. the skeleton path as resolved from the polygon node;
3. bone rest transforms and the order in which the rest pose was captured;
4. boundary and internal points as displayed by Godot's UV editor;
5. the explicit cells crossing the elbow and wrist;
6. weight painting on every point, including internal points;
7. animation tracks rotating bones rather than polygons.

Do not copy gBot coordinates or weights into Kotone. The next safe step is to
run this project unchanged in Godot 4.7.2, inspect its right-arm mesh in the UV
editor and document the structural differences against Task 4I.

## First high-confidence structural discrepancy

In the official scene, the polygon's `skeleton` property locates the
`Skeleton2D` node, while each entry in `bones` is a path inside that skeleton:

```text
skeleton = NodePath("../../Skeleton2D")
bones = ["Hip/Chest/RightArm", ..., "Hip/Chest/RightArm/RightForearm", ...]
```

Task 4I instead serializes bone entries as paths from the polygon toward the
skeleton node:

```text
skeleton = NodePath("../BaseRig/Skeleton2D")
bones = ["../BaseRig/Skeleton2D/pelvis/torso/upper_arm_right", ...]
```

This is the strongest current explanation for the empty arm-only Task 4I
render. The previously visible body came from `BaseRig` sprites; after those
sprites were hidden, an incorrectly bound weighted polygon would leave an
empty panel. Confirm this interpretation in Godot before modifying Task 4I:
use the Polygon2D UV editor's **Sync Bones to Polygon** operation on a disposable
copy and compare the serialized paths it produces.
