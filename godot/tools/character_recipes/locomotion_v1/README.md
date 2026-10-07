# Directional idle authoring decisions

Recipe manifest schema 2 explicitly declares the animation scope. This recipe
replays all 44 frames of `idle_left`, `idle_right`, `walk_left`, and `walk_right`
for Kotone/Yuna. Additional reaction animations have their own authoring scope;
they do not extend this locomotion recipe. Replay still requires the complete
scoped canonical frame set, tracked inputs/outputs and byte-identical results.
The old implicit whole-model manifest schema 1 is rejected without fallback.

Every runtime package supplies `idle_left`, `idle_right`, `walk_left`, and
`walk_right` as prepared canonical PNG frames. Runtime selects the animation;
it does not infer symmetry, mirror pixels, or substitute a missing direction.
The initial/Creator pose is `idle_right`.

Current Yuna is treated as symmetric by the author. Her two accepted right-idle
source poses are cleaned, mirrored offline for the left view, and then placed
with reviewed roots. Source cells are 248 px wide; mirrored root x = 247 - x.
Mirroring before placement preserves pivot (128,236) exactly; directly flipping
the final 256 px canvas would move pixel-center root x128 to x127.

Current Kotone retains her accepted front-facing idle in both directional slots.
The repeated front art is an explicit decision for this current package.

Future asymmetric models need independently authored views for each required
direction, including their asymmetric hair, clothing and accessories. The agent
selects/extracts those sources, inspects them, reviews each pose plan, places both
views at the same metric scale/ground/pivot, and records the atomic operations.
Do not mirror or duplicate art automatically to satisfy a missing direction.
New art may have different source resolutions or single-frame inputs; the same
atomic tools apply and the agent supplies its own flow and coordinates.
