# RC3 front joint rigging architecture

## Decision

Task 4G proved transform directions but rejected independently rotated rigid
PNG cutouts for exposed human joints. Task 4H remains a diagnostic proof that
Godot can bind a continuous texture to several bones; its dense strip and broad
weight gradients are not the production topology.

The front mannequin will use a hybrid rig:

- continuous weighted `Polygon2D` meshes for skin and fabric that must bend;
- rigid bone children for parts that should preserve shape, such as hands,
  shoes and small accessories;
- deliberately drawn hidden overlap and rounded joint ends where two rigid
  assets rotate against each other;
- a corrective joint patch or rare pose correction only when a properly built
  mesh cannot preserve the silhouette at the required extreme.

IK is not part of the deformation solution. IK chooses bone rotations; mesh
topology, weights and source artwork determine how those rotations look.

## Evidence

The official Godot Skeleton2D demo uses one `Polygon2D` for an entire arm,
including upper arm, forearm and hand. Its arm has 19 semantic vertices and
seven explicit mesh cells. Most vertices carry a weight of `1.0` for one bone;
the vertices at the elbow and wrist transition carry `0.5/0.5`. It does not use
three rectangular limb sprites or a long smooth gradient over the whole arm:

- [Godot Skeleton2D demo](https://github.com/godotengine/godot-demo-projects/tree/master/2d/skeleton)
- [official player scene](https://github.com/godotengine/godot-demo-projects/blob/master/2d/skeleton/player/player.tscn)

Godot's 2D skeleton documentation requires internal vertices in regions that
bend and smaller custom polygons around those regions. It explicitly notes that
full weights on two bones are automatically shared at a common point, so broad
gray gradients are not required for a basic joint:

- [Godot 2D skeletons](https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html)
- [Godot 4.7 Polygon2D](https://docs.godotengine.org/en/4.7/classes/class_polygon2d.html)

Dedicated 2D rigging documentation reaches the same conclusion. Rive separates
rigid transforms from weighted raster deformation and gives a rigid hand plus a
weighted sleeve as a hybrid example. Spine recommends minimal purposeful
topology, grouped weights, testing at the intended extremes, hidden artwork and
rounded ends for rotating cutouts:

- [Rive bones and hybrid deformation](https://rive.app/docs/editor/manipulating-shapes/bones)
- [Rive raster meshes](https://rive.app/docs/editor/manipulating-shapes/meshes)
- [Spine mesh weight workflow](https://esotericsoftware.com/blog/Mesh-weight-workflows)
- [Spine asset preparation](https://esotericsoftware.com/blog/How-to-cut-your-assets-for-animation)

## Kotone joint construction rules

1. Build and approve the neutral bind/rest pose before changing weights.
2. Put the bone origin at the anatomical joint center, not at a trimmed PNG
   corner or at the visible edge of an overlap.
3. Trace the visible silhouette with the minimum useful external vertices.
4. Use large cells for regions controlled by one bone and small cells only
   around a shoulder, elbow, wrist, hip, knee or ankle.
5. For a tubular limb, create a transverse vertex pair at the joint plus at
   most one internal joint vertex for the initial topology.
6. Give vertices away from the joint `100%` to one bone. Begin the joint ring at
   `50/50`; tune only that local ring while viewing the maximum required bend.
7. Do not spread tiny residual weights across the limb. They create rubbery
   deformation and make the rig harder to reason about.
8. Test the complete required range, not a single flattering angle. The front
   anatomical-right elbow gate is `0°`, `-30°`, `-60°`, `-90°`.
9. Never allow elbow motion in the anatomically forbidden direction merely to
   make a symmetric test sheet.
10. If the local mesh pinches at the required maximum, stop weight tuning and
    choose one explicit remedy: redraw the joint with additional hidden volume,
    add a rounded underlay/patch, or author a narrowly scoped corrective pose.

## Artwork rules for the clothed model

The flattened RC2 art cannot simply be cropped at every visible seam. Every
layer that can reveal pixels during motion must contain those hidden pixels.

- Base skin arm: continuous from under the shoulder to under the wrist.
- Hand: rigid layer with a rounded hidden wrist extension.
- Shirt sleeve: separate weighted mesh crossing the elbow, with fabric drawn
  beneath the cuff and torso overlaps.
- Cuff: separate rigid or narrowly weighted layer if its shape must remain
  crisp.
- Torso: covers the hidden shoulder end of the arm mesh.
- Hair, skirt and badge: separate later passes; they must not be introduced
  while validating the naked joint mechanics.

## Gates

1. Approve one anatomical-right elbow across `0/30/60/90` degrees.
2. Mirror the proven topology and swap bone assignments for the left arm.
3. Apply the same joint-local method to shoulders, hips, knees and ankles.
4. Approve a complete naked mannequin articulation sheet.
5. Create the first walk cycle on the naked mannequin.
6. Only then prepare and bind clothing layers to the approved skeleton.
