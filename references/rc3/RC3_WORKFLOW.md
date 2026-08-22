# RC3 WORKFLOW REGULATION

Status: mandatory for all Kotone RC3 work  
Repository: `ronkiko/hello-kotone`  
Canonical working branch: `RC3`

## 1. Branch policy

- All RC3 work is performed directly on the single branch `RC3`.
- Do not create task branches, feature branches or temporary GitHub branches.
- Do not open pull requests for RC3 work.
- Do not merge RC3 into `main` without explicit user approval.
- Do not force-push, rewrite or rebase published RC3 history.
- The existing branch `rc3/task-2-canon-layer-map` is historical bootstrap only. Its approved commit is included in the initial `RC3` history and it must not be used for further work.

## 2. Commit policy

- Each approved task or explicitly requested preflight/fix is committed directly to `RC3`.
- A commit contains only files belonging to the current task.
- Do not include unrelated, generated, local or user-owned changes.
- Preferred commit format: `[rc3][task-N] concise result`.
- Preflight and corrective commits use: `[rc3][preflight] ...` or `[rc3][fix] ...`.
- Report the exact commit SHA after every published task.

## 3. Task gates

For every task:

1. Verify the current remote `RC3` HEAD.
2. Read the current canon and the files relevant to the task.
3. Perform only the approved task scope.
4. Validate the produced files and check the commit diff.
5. Commit directly to `rc3`.
6. Report results, known limitations and the exact SHA.
7. Stop and wait for approval before starting the next task.

## 4. Scope protection

- `legacy/` remains preserved and is not modified unless the user explicitly requests it.
- `main` remains untouched during RC3 production.
- Reference materials are not silently treated as production assets.
- No source reference is deleted merely because it is rejected for the rig.
- Do not replace or overwrite user artwork without retaining its source reference.
- Godot import caches, exports and other generated artifacts remain uncommitted.

## 5. Asset policy

- Canon and production notes live under `references/rc3/`.
- Prepared rig source parts live under `godot/assets/rc3/rig/`.
- Godot scenes and scripts for RC3 live under `godot/scenes/rc3/` and `godot/scripts/rc3/` when those tasks begin.
- Production PNG parts require real alpha transparency.
- Every generated or edited graphical result must be visually inspected before commit.
- Original scale, common coordinate system, pivots and layer names must remain traceable.

## 6. Current sequence

1. Task 1 — source inventory: complete.
2. Task 2 — canon and rig map: complete.
3. Task 3 — prepare transparent body parts: next.
4. Task 4 — assemble the Godot 2D skeleton.
5. Task 5 — build and validate `walk_right`.
6. Task 6 — add remaining directions, idle and base expressions.
7. Task 7 — export and integrate RC3 into the game.
