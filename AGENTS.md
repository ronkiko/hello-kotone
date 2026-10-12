# AGENTS.md — Hello Kotone / Godot MMO client

Перед изменениями читай `README.md` и `godot/README.md`. Для physics/multiplayer/reconciliation/transport сверяйся с действующими контрактами server-side `ai_research/v3/game/docs/`, в частности `server-tick-authority.md`, `physics-state-contract.md`, `networked-locomotion-architecture.md` и `client-prediction-and-reconciliation.md`. Серверный MMO канон принадлежит совместному проекту; этот публичный client repo не является вторым независимым источником игровых правил.

## Unified Realm Tick — обязательный регламент с 2026-10-12

**Новая целевая архитектура, до реализации [8.12](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/8/12-unified-realm-tick.md).** Один `realm_tick` на весь Realm epoch, все Zone получают общие server TickCommands и хранят лишь committed watermark `last_committed_realm_tick`. **Никаких независимых игровых часов Zone**; старый per-Zone `simulation_tick` — временная pre-migration реализация и должен быть удалён при coordinated server/client switch без legacy aliases. Физика сервера 60 Hz fixed `dt=1/60`, смена input только на tick boundary, physics damage/contacts только по committed Realm ticks.

Godot `_physics_process()`, `CharacterBody2D` и prediction `local_ordinal` остаются локальными UX/physics-clocks, не копируют серверный тик. Серверная causal order привязана к realm epoch + `realm_tick`, а Zone/generation + committed watermark определяют, на каком тике конкретная Zone действительно зафиксировала событие. Native UI/animation/RTT, interpolation 100 ms, capped extrapolation и network timeout используют real monotonic time, а не игровое время.

`motion_frame` — coalescible latest committed Zone state: nominal каждый третий Realm tick при 60/20 Hz и не чаще 20 Hz реального времени даже при catch-up. `frame_seq` и State `revision` отдельные; `damage_resolved`, presence, lifecycle, takeover, ACK — reliable order без ожидания sampling. Никакого fake packet при отстающей Zone, никакого вычисления authoritative contact на клиенте.

Перед изменением physics/wire/prediction/reducer читать серверный [канон Server Tick Authority](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/server-tick-authority.md), новую задачу 8.12 и действующий Godot README. Следующие патчи: 8.13 Load/Jitter, 8.14 integrated multiplayer, 8.15 cleanup, 8.16 acceptance. Любая техническая миграция только main и с exact SHA pair, не менять unrelated balance/canon и не запускать длинные gates до диагностики.

## Порядок изменений

Используй Godot-native nodes/resources/input/physics/AnimationPlayer где они выполняют задачу. Не создавай параллельный самописный physics или animation framework. Тесты и exact-pair server/client SHA фиксировать, работа только в `main`, логичные версионированные commits с patch id, без legacy fallback и не относящегося к задаче рефакторинга. При patch 8.12 сначала читать новое Unified Realm Tick задание в server repo; ранее прошедшие дорогостоящие тесты не перезапускать без изменения affected semantics.
