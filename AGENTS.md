# AGENTS.md — Hello Kotone / Godot MMO client

## Общее обязательное правило документации — ВСЕ компоненты

[Единый стандарт документации всего проекта](https://github.com/ronkiko/ai_research/blob/main/DOCUMENTATION-POLICY.md)
распространяется на **все** компоненты `hello-kotone` и `ai_research`:
Godot, UI, сцены, рендер, анимации, инструменты ассетов, multiplayer,
physics, сеть, сервисы и будущие подсистемы, а не только Series 10.
Каждый реальный логический компонент должен быть находим на общей карте и
описан через назначение, границы ответственности, реальные процессы,
потоки/состояния/отказы и взаимодействия. Отсутствие покрытия —
**баг `DOC-COVERAGE`**, противоречие коду — **баг `DOC-DRIFT`**.
Не превращать архитектурные документы в перечень файлов, классов и функций;
читать карту, затем изучать код. При смысловом изменении поддерживать карту
в согласованном коммите. Детали кода и SHA — в patch evidence.
Нормативные спецификации и практические инструкции сохраняют нужную точность.

**[v3.main.10.00 — общий нулевой патч ревизии документации](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/10/00-documentation-revision.md)**
проверяет все логические компоненты **двух исходных runtime-репозиториев**;
**Директор разрешил начать аудит 10.00 уже сейчас.** Параллельно разрешено
обсуждать и дополнять **DRAFT** серии 10, но формальное исполнение 10.01
и любой Go Networking кодовый патч требуют предварительной проверки и
приёмки 10.00. Создание задания не является приёмкой 10.00.
Не изменять runtime, стенды и сохранённые данные в ходе нулевой ревизии.


Перед изменениями читай `README.md`, `ARCHITECTURE.md` и `godot/README.md`. Для physics/multiplayer/reconciliation/transport сверяйся с действующими контрактами server-side `ai_research/v3/game/docs/`, в частности `server-tick-authority.md`, `physics-state-contract.md`, `networked-locomotion-architecture.md` и `client-prediction-and-reconciliation.md`. Серверный MMO канон принадлежит совместному проекту; этот публичный client repo не является вторым независимым источником игровых правил.

## Unified Realm Tick — обязательный регламент с 2026-10-12

**Реализовано в [8.12](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/8/12-unified-realm-tick.md).** Один `realm_tick` на весь Realm epoch, все Zone получают общие server TickCommands и хранят лишь committed watermark `last_committed_realm_tick`. **Никаких независимых игровых часов Zone**; старый per-Zone `simulation_tick` удалён при coordinated v9 cutover без legacy aliases. Физика сервера 60 Hz fixed `dt=1/60`, смена input только на tick boundary, physics damage/contacts только по committed Realm ticks.

Godot `_physics_process()`, `CharacterBody2D` и prediction `local_ordinal` остаются локальными UX/physics-clocks, не копируют серверный тик. Серверная causal order привязана к realm epoch + `realm_tick`, а Zone/generation + committed watermark определяют, на каком тике конкретная Zone действительно зафиксировала событие. Native UI/animation/RTT, interpolation 100 ms, capped extrapolation и network timeout используют real monotonic time, а не игровое время.

`motion_frame` — coalescible latest committed Zone state: nominal каждый третий Realm tick при 60/20 Hz и не чаще 20 Hz реального времени даже при catch-up. `frame_seq` и State `revision` отдельные; `damage_resolved`, presence, lifecycle, takeover, ACK — reliable order без ожидания sampling. Никакого fake packet при отстающей Zone, никакого вычисления authoritative contact на клиенте.

Перед изменением physics/wire/prediction/reducer читать серверный [канон Server Tick Authority](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/server-tick-authority.md), новую задачу 8.12 и действующий Godot README. Series 8 закрыта после emergency 8.14 с сохранённым 8.13 FAIL; старые 8.15/8.16 отменены. Series 9 принята 2026-10-16 с ограничениями, текущая работа — 10.00 docs audit. Любая техническая миграция только main и с exact SHA pair, не менять unrelated balance/canon и не запускать длинные gates до диагностики.

## Series 10: обязательная документация Go Networking (черновик, не запускать реализацию без разрешения)

Названия новых компонентов: **Go Networking Client (GNC)** на компьютере игрока,
**Go Networking Server (GNS)** на сервере; общий контракт реализует
**Go Networking Protocol Core (GNPC)**. **УТВЕРЖДЕНО:** GNC/GNS/GNPC
будут одним Go-модулем в отдельном private `ronkiko/go-networking` (репозиторий уже создан, Go-код пока не реализован).
`hello-kotone` владеет только Godot native integration/packaging; нельзя
копировать здесь самостоятельный Go codec/сеть. Серия 10 пока **DRAFT**;
первый функциональный сетевой результат — минимальный бинарный **GNC↔GNS
PING/PONG**, позже Godot↔GNC↔GNS; не требовать преждевременно полной MMO-функциональности.

**Каноническая внутренняя карта Go Networking** находится в private
[`go-networking/README.md`](https://github.com/ronkiko/go-networking/blob/main/README.md). MMO-side boundary остаётся в
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
