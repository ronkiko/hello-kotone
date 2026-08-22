# RC3 WORKFLOW REGULATION

Status: mandatory for all Kotone RC3 work  
Repository: `ronkiko/hello-kotone`  
Canonical working branch: `RC3`

## 1. Branch and commit policy

- Work directly on `RC3`.
- Do not create task branches or pull requests.
- Do not merge into `main` without explicit user approval.
- Do not force-push, rewrite or rebase published RC3 history.
- Do not demand a clean workspace; preserve unrelated user changes and commit
  only files belonging to the current task.
- Preferred commit format: `[rc3][task-N] concise result`.

## 2. Required preflight

Before every task:

1. Verify the current remote `RC3` HEAD.
2. Read `references/rc3/KOTONE_RC3_CANON_AND_RIG_MAP.md`.
3. Read `godot/assets/rc3/rig/README.md` and `rig_manifest.json`.
4. Inspect the actual production source and latest QA previews.
5. Stop if documents, assets and manifest disagree; do not guess.

## 3. Stage discipline

- Perform only the current manifest stage.
- Run structural checks and inspect every visual output before commit.
- Report exact input/output HEADs, changed files and known limitations.
- Stop after each published task and wait for approval.
- User approval is required before changing `ready_for_review` to `approved`.
- Do not cut meshes while the T-pose is merely a candidate.
- Do not animate before the full neutral rig is approved.

## 4. Active and archived paths

Active production:

- source: `godot/assets/rc3/rig/source/`
- mesh textures/masks: `godot/assets/rc3/rig/mesh/`
- QA: `godot/assets/rc3/rig/preview/`
- scenes: `godot/scenes/rig/`
- tools: `godot/scripts/rig/`

Archived read-only experiment:
`godot/archive/rc3_rigid_cutout/`.

Active scenes and scripts must not reference the archive. `legacy/`, `main` and
original references remain untouched unless explicitly requested.

## 5. Asset rules

- Production images require genuine RGBA transparency.
- Checkerboard belongs only in QA previews, never in production pixels.
- Reject vector/cartoon/chibi drift regardless of pose correctness.
- Preserve original references; write derivatives to production paths.
- Do not commit Godot caches, exported builds or local generated files.

## 6. Current sequence

1. Archive rigid-cutout experiment — complete.
2. Prepare fresh front T-pose/mesh workspace — complete.
3. Create front T-pose source and QA — current, awaiting user review.
4. Build and approve a weighted single-limb deformation spike.
5. Build and approve the complete front neutral rig.
6. Author animations only after the previous gates pass.
7. Create separate side/back sources and rigs when explicitly scheduled.
