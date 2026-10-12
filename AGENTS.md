# AGENTS.md — Hello Kotone / Godot MMO client

Перед изменениями читай `README.md` и `godot/README.md`. Для physics/multiplayer/reconciliation/transport сверяйся с действующими контрактами server-side `ai_research/v3/game/docs/`, в частности `server-tick-authority.md`, `physics-state-contract.md`, `networked-locomotion-architecture.md` и `client-prediction-and-reconciliation.md`. Серверный MMO канон принадлежит совместному проекту; этот публичный client repo не является вторым независимым источником игровых правил.

## Server Tick Authority — обязательный регламент с 2026-10-12

- Логическое время серверного мира = `simulation_tick`, ограниченный `realm_instance_id/zone_package_id/zone_generation`. Это tick Zone, а не глобальный tick всех Realms. Авторитетные position/velocity/contacts/impulses/damage привязаны к server tick и его committed revision. Public `frame_seq` — отдельный счётчик публикаций.
- Godot `_physics_process()`/`CharacterBody2D` 60 Hz **не является** clock authority сервера. Локальная prediction history сохраняет свой локальный ordinal; server tick используется для корреляции authoritative samples и reconciliation, не копируется в локальный ordinal и не заменяет его.
- Серверные контролы семантически применяются на границе server simulation tick; client не объявляет на основании моментального input state, что сервер уже применил контроль. Учитывать `last_applied_control_seq` и `control_started_tick`, scope/fences и explicit accepted snapshot.
- `motion_frame` — coalescible **latest committed** sample: nominal один на три server ticks при 60/20 Hz, при catch-up не быстрее 20 Hz реального времени. Пропущенный packet или непришедший кадр нельзя интерпретировать как новый физический тик; не изобретать server states и не считать renderer authority.
- `damage_resolved`, lifecycle, join/leave и State snapshots — reliable независимые события, не ждать motion sampling, не смешивать визуальную реакцию с gameplay outcome.
- Для клиента реальное время остаётся необходимым для RTT, sample receipt/interpolation age, frame pacing, animation, timeout, 100-ms remote delay и ограниченной extrapolation. Общее правило: **server ticks — игровая причинность; local monotonic ms — качество доставки/UX**, не подменять одно другим.
- На каждом server-physics/client-timeline corrective проверять restart/resync/epoch/generation/takeover, out-of-order/duplicate packets, short facing-only tap, contact direction и недопустимость фальшивых damage events. Не менять server physics/60/20 Hz или канон в клиенте самостоятельно; авторские изменения канона — только после согласования.

## Порядок изменений

Используй Godot-native nodes/resources/input/physics/AnimationPlayer где они выполняют задачу. Не создавай параллельный самописный physics или animation framework. Тесты и exact-pair server/client SHA фиксировать, работа только в `main`, логичные версионированные commits с patch id, без legacy fallback и не относящегося к задаче рефакторинга. При patch 8.12 сначала читать актуальное corrective в server repo; ранее прошедшие дорогостоящие тесты не перезапускать без изменения affected semantics.
