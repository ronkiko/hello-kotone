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
**10.00 агентом сдана, приёмка Директора PENDING.** Узко разрешены
standalone 10.01 GNS↔Python IPC и 10.02 Godot SDK local smoke;
[текущее поручение](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/10/01-02-agent-corrective-handoff.md).

**НОВОЕ РЕШЕНИЕ ДИРЕКТОРА 2026-10-16:** удалить Go GNC и весь native
client smoke; сделать клиентский SDK **на GDScript по модели Nakama**.
Canonical addon — `addons/mmo_sdk/`, isolated smoke — `experiments/client_sdk/`.
Не восстанавливать Go client, C ABI, GDExtension, godot-cpp или sidecar.
Проверки запускать на установленном пользовательском Godot. Никакого изменения
основного `godot/`, стендов, данных, протокола v9 или production-интеграции.
Прямая команда Директора 2026-10-17 «делай 10 03» разрешила изолированный
SoulWorker-формат TCP smoke. **Corrective Директора: 10.03 нельзя считать
завершённым без сетевого PING/PONG между GDScript SDK и Go GNS; это обязательная
доработка ТОЙ ЖЕ 10.03, не новый номер.** Исходный fixture TCP smoke уже PASS,
corrective PING/PONG теперь реализован с собственными opcode, отрицательными
Godot тестами и отдельным evidence; Director acceptance остаётся PENDING. Ссылка на задачу 10.03 ниже, основная игра не затрагивается.

Перед изменениями читай `README.md`, `ARCHITECTURE.md` и `godot/README.md`. Для physics/multiplayer/reconciliation/transport сверяйся с действующими контрактами server-side `ai_research/v3/game/docs/`, в частности `server-tick-authority.md`, `physics-state-contract.md`, `networked-locomotion-architecture.md` и `client-prediction-and-reconciliation.md`. Серверный MMO канон принадлежит совместному проекту; этот публичный client repo не является вторым независимым источником игровых правил.

## Unified Realm Tick — обязательный регламент с 2026-10-12

**Реализовано в [8.12](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/8/12-unified-realm-tick.md).** Один `realm_tick` на весь Realm epoch, все Zone получают общие server TickCommands и хранят лишь committed watermark `last_committed_realm_tick`. **Никаких независимых игровых часов Zone**; старый per-Zone `simulation_tick` удалён при coordinated v9 cutover без legacy aliases. Физика сервера 60 Hz fixed `dt=1/60`, смена input только на tick boundary, physics damage/contacts только по committed Realm ticks.

Godot `_physics_process()`, `CharacterBody2D` и prediction `local_ordinal` остаются локальными UX/physics-clocks, не копируют серверный тик. Серверная causal order привязана к realm epoch + `realm_tick`, а Zone/generation + committed watermark определяют, на каком тике конкретная Zone действительно зафиксировала событие. Native UI/animation/RTT, interpolation 100 ms, capped extrapolation и network timeout используют real monotonic time, а не игровое время.

`motion_frame` — coalescible latest committed Zone state: nominal каждый третий Realm tick при 60/20 Hz и не чаще 20 Hz реального времени даже при catch-up. `frame_seq` и State `revision` отдельные; `damage_resolved`, presence, lifecycle, takeover, ACK — reliable order без ожидания sampling. Никакого fake packet при отстающей Zone, никакого вычисления authoritative contact на клиенте.

Перед изменением physics/wire/prediction/reducer читать серверный [канон Server Tick Authority](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/server-tick-authority.md), новую задачу 8.12 и действующий Godot README. Series 8 закрыта после emergency 8.14 с сохранённым 8.13 FAIL; старые 8.15/8.16 отменены. Series 9 принята 2026-10-16 с ограничениями, текущая работа — 10.00 docs audit. Любая техническая миграция только main и с exact SHA pair, не менять unrelated balance/canon и не запускать длинные gates до диагностики.

## Series 10: Godot SDK и Go GNS

Клиентский **Godot SDK** — GDScript addon в этом repo. **GNS** и будущий
server-side **GNPC** находятся в private `ronkiko/go-networking`. Go GNC удалён
по решению Директора. Не копировать старый native стек обратно.
Каноническая карта GNS/сетевого контракта — Go README; карта SDK —
[локальная архитектура](ARCHITECTURE.md) и [addon](addons/mmo_sdk/README.md);
MMO-side authority — в `ai_research/v3/game/docs/go-networking/README.md`.
Перед сетевыми изменениями читать общий DOCUMENTATION-CONTRACT.md в server repo.

10.02 проверяет только создание SDK, native Godot transport primitives и
локальный lifecycle. Изолированные connect/send и candidate wire разрешены командой 10.03;
игровые endpoints и production-интеграция по-прежнему не разрешены. **Дизайн 10.03 утверждён
Директором 2026-10-17: бинарный TCP и исторический wire SoulWorker.**
[03-soulworker-wire-first-network-smoke.md](https://github.com/ronkiko/ai_research/blob/main/v3/docs/roadmap/v3/main/10/03-soulworker-wire-first-network-smoke.md);
[владеющая спецификация](https://github.com/ronkiko/go-networking/blob/main/docs/soulworker-wire-compatibility.md).
Организацию GDScript addon берём по Nakama, но НЕ её HTTP/WebSocket wire.
Для SoulWorker-oriented реализации использовать штатный Godot StreamPeerTCP,
без client Go/GDExtension. Не добавлять в общий header обязательные версию,
request_id или group. **Уточнение Директора 2026-10-17:** SDK вправе
использовать собственные category/opcode и новые команды PING/PONG
**в том же SoulWorker формате**. Для legacy-клиента эти расширения
не отправлять без доказанной поддержки; исторические opcode не менять.
Историческая
build-совместимость оригинального SoulWorker клиента — будущая цель,
а не статус 10.03. Local health не является ответом сервера.
Текущая игра продолжает использовать v9.

Обновлять logical docs вместе со смысловыми изменениями. Source, команды и
exact repo SHAs — в patch evidence; не заявлять PASS внешней сети по local smoke.

## Порядок изменений

Используй Godot-native nodes/resources/input/physics/AnimationPlayer где они выполняют задачу. Не создавай параллельный самописный physics или animation framework. Тесты и exact-pair server/client SHA фиксировать, работа только в `main`, логичные версионированные commits с patch id, без legacy fallback и не относящегося к задаче рефакторинга. При patch 8.12 сначала читать новое Unified Realm Tick задание в server repo; ранее прошедшие дорогостоящие тесты не перезапускать без изменения affected semantics.


8.12 executable cutover: current public protocol **v9** carries `realm_tick`;
`protocol_v9.gd` replaces the old validator without an old-field fallback.
Replica, native owner predictor and remote timeline use the same Realm-scoped
authoritative marker while client `local_ordinal` remains independent.
Exact-pair acceptance is recorded in the shared server 12-validation.json.


Same-patch corrective 10.03 PING/PONG is implemented and technically verified.
Preserve canonical Go extension registry, socket-local pending correlation and
negative outcomes, and historical fixtures. Director acceptance remains PENDING;
10.04 and production integration are not authorized by this work.
