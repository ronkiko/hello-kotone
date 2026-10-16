# Map cache and 1D presentation — v3.main.5.04

Enter establishes the map reference in WorldReplica. MmoClient checks
`user://mmo/maps-v1`: a hit must pass the same strict JSON/schema/canonical SHA-256
validation as the public map response and match ID, version and hash. A missing,
truncated, oversized, duplicate-key or mismatched file is a miss, followed by the
ordinary public map request. Invalid network maps remain terminal failures.
A hit still installs map bounds into WorldReplica and requests state: it does
not skip readiness or revision checks. Explicit request_map still contacts Game.

Cache keys hash the complete reference; map IDs never become file paths. Compact
JSON files contain no newline (Protocol.decode receives frames without LF).
Writes use a temporary file and rename. Disk write failure affects reuse only;
a validated live map remains usable. Each read is capped at the wire frame budget.

World shell adapts replica values to platform presentation. Validated map geometry
sets terrain/world bounds; server-selected physics profiles set body dimensions.
Owner CharacterBody2D predicts locally, then reconciles against committed motion;
remote avatars follow delayed server samples. Camera follows the visual owner,
not a second authoritative coordinate. Map cache never restores sessions or State.
[Prediction](prediction-reconciliation.md), [client map](../../ARCHITECTURE.md).
