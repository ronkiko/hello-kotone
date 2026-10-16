# AGENTS.md — Hello Kotone / Godot MMO client

Перед изменениями читай `README.md` и `godot/README.md`. Для physics/multiplayer/reconciliation/transport сверяйся с действующими контрактами server-side `ai_research/v3/game/docs/`, в частности `server-tick-authority.md`, `physics-state-contract.md`, `networked-locomotion-architecture.md` и `client-prediction-and-reconciliation.md`. Серверный MMO канон принадлежит совместному проекту; этот публичный client repo не является вторым независимым источником игровых правил.

## Unified Realm Tick — обязательный регламент с 2026-10-12

**Новая целевая архитектура, до реализации [8.12](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/8/12-unified-realm-tick.md).** Один `realm_tick` на весь Realm epoch, все Zone получают общие server TickCommands и хранят лишь committed watermark `last_committed_realm_tick`. **Никаких независимых игровых часов Zone**; старый per-Zone `simulation_tick` — временная pre-migration реализация и должен быть удалён при coordinated server/client switch без legacy aliases. Физика сервера 60 Hz fixed `dt=1/60`, смена input только на tick boundary, physics damage/contacts только по committed Realm ticks.

Godot `_physics_process()`, `CharacterBody2D` и prediction `local_ordinal` остаются локальными UX/physics-clocks, не копируют серверный тик. Серверная causal order привязана к realm epoch + `realm_tick`, а Zone/generation + committed watermark определяют, на каком тике конкретная Zone действительно зафиксировала событие. Native UI/animation/RTT, interpolation 100 ms, capped extrapolation и network timeout используют real monotonic time, а не игровое время.

`motion_frame` — coalescible latest committed Zone state: nominal каждый третий Realm tick при 60/20 Hz и не чаще 20 Hz реального времени даже при catch-up. `frame_seq` и State `revision` отдельные; `damage_resolved`, presence, lifecycle, takeover, ACK — reliable order без ожидания sampling. Никакого fake packet при отстающей Zone, никакого вычисления authoritative contact на клиенте.

Перед изменением physics/wire/prediction/reducer читать серверный [канон Server Tick Authority](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/server-tick-authority.md), новую задачу 8.12 и действующий Godot README. Следующие патчи: 8.13 Load/Jitter, 8.14 integrated multiplayer, 8.15 cleanup, 8.16 acceptance. Любая техническая миграция только main и с exact SHA pair, не менять unrelated balance/canon и не запускать длинные gates до диагностики.

## Series 10: обязательная документация Go Networking (черновик, не запускать реализацию без разрешения)

Названия новых компонентов: **Go Networking Client (GNC)** на компьютере игрока,
**Go Networking Server (GNS)** на сервере; общий контракт реализует
**Go Networking Protocol Core (GNPC)**. Серия 10 пока **DRAFT**;
первый функциональный сетевой результат — минимальный бинарный **GNC↔GNS
PING/PONG**, позже Godot↔GNC↔GNS; не требовать преждевременно полной MMO-функциональности.

**Единственный исходный технический документ сетевого слоя** находится в
[`ai_research/v3/game/docs/go-networking/README.md`](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/go-networking/README.md).
При любых изменениях Godot ↔ GNC, публичного wire, сетевых API, native ABI,
сериализации, connect/disconnect, протокольных событий или ошибок обязательно
читать [Documentation Contract](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/go-networking/DOCUMENTATION-CONTRACT.md).
Документация должна объяснять **логическую схему работы**: границы
Godot↔GNC↔GNS, поток сообщений, ответственность, состояния и отказы,
а **не перечислять файлы, функции и внутренние методы**.
При смысловом изменении клиентской сети согласованно обновлять живую главу
в `ai_research` и её статус PLANNED/DESIGNED/IMPLEMENTED/VERIFIED.
При чисто внутреннем рефакторинге глава может оставаться неизменной.
Исходники, ABI-детали, точные Git SHA, команды тестов и evidence изучать
в коде и отчёте патча, не переносить весь этот перечень в обзорные доки.
**Нельзя сдавать patch DONE/PASS с несовпадающей логикой кода и документации.**
Для совместимой server/client пары фиксировать оба Git SHA и версию ABI/wire
в отчёте/приёмке патча.
Не создавать независимую конкурирующую спецификацию в клиентском repo;
локальные технические детали могут ссылаться на единый документ.
Утверждённый текущий public v9 сохраняется до отдельно разрешённого cutover;
на пользовательских стендах ничего не менять без отдельного решения.

## Порядок изменений

Используй Godot-native nodes/resources/input/physics/AnimationPlayer где они выполняют задачу. Не создавай параллельный самописный physics или animation framework. Тесты и exact-pair server/client SHA фиксировать, работа только в `main`, логичные версионированные commits с patch id, без legacy fallback и не относящегося к задаче рефакторинга. При patch 8.12 сначала читать новое Unified Realm Tick задание в server repo; ранее прошедшие дорогостоящие тесты не перезапускать без изменения affected semantics.


8.12 executable cutover: current public protocol **v9** carries `realm_tick`;
`protocol_v9.gd` replaces the old validator without an old-field fallback.
Replica, native owner predictor and remote timeline use the same Realm-scoped
authoritative marker while client `local_ordinal` remains independent.
Exact-pair acceptance is recorded in the shared server 12-validation.json.
