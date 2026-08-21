# Kotone v2

RC2-ассеты улучшенной модели Kotone от Dorisu для exploration-сценариев.

## Ready For Use

Игровые листы находятся в `rc2/frames/`. Их размеры, anchor, frame counts и
timing описаны в `manifest.json`:

- `idle_front.png`, `idle_back.png`, `idle_left.png`, `idle_right.png`
- `walking_front.png`, `walking_back.png`, `walking_left.png`, `walking_right.png`

Idle-листы содержат шесть кадров `130x130`, walking-листы содержат шесть
кадров `130x130`. Все подключённые листы имеют прозрачный RGBA-фон и
подключаются напрямую canvas-рендером. Running-листы пока не подключены.

Боевые, jump, hurt и другие состояния RC2 пока не подключены.
