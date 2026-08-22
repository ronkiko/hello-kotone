# Hello Kotone

RC3 is being developed as a new Godot 2D project. The previous browser game
is archived unchanged as a runnable legacy implementation.

## Repository layout

```text
legacy/web/                 Original Canvas and vanilla JS implementation
legacy/web/assets/kotone-v1 Historical Kotone model kept for RC1 history
legacy/web/assets/kotone-v2 Historical Kotone model kept for RC2 history
references/                 Source and visual reference material
```

The material under `references/` is reference material, not an automatic
canonical source for RC3. Canonical art and design decisions will be declared
explicitly as the Godot project is built.

The public library remains at the repository root. Its game links now point to
`legacy/web/`, so the legacy implementation remains directly playable without
changing deployment configuration.

## Legacy

Run the repository through a static HTTP server and open `/legacy/web/`:

```text
python3 -m http.server
```

The legacy implementation still uses local source material from `.local/` when
that ignored working-copy directory is available.

## Godot

Open `godot/project.godot` in Godot 4.x. The project is intentionally minimal;
gameplay will be implemented from scratch in separate commits after this
workspace-initialization commit.
