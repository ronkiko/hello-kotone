# Hello Kotone

Человеческий Godot-клиент MMO, часть единого проекта в трёх Git-репозиториях.
**[Карта клиента](ARCHITECTURE.md)** → [Godot contracts/runbook](godot/README.md).

## Multirepo и границы ответственности

| Репозиторий | Владение |
| --- | --- |
| [`ai_research`](https://github.com/ronkiko/ai_research) | Авторитетные MMO-домены и Python-сервер: Login, Lobby, Game/Realm, State, Storage, game cards, общие игровые контракты и roadmap. |
| `hello-kotone` — этот репозиторий | Godot-клиент: UI, ввод, локальные prediction/presentation, клиентские assets и GDScript SDK addon. Не владеет состоянием мира или реализацией Go-протокола. |
| [`go-networking`](https://github.com/ronkiko/go-networking) — private | Один Go-модуль: Go Networking Server (GNS) и будущий server-side GNPC. Изолированный GNS↔Python IPC проверен; игровое подключение и публичный протокол ещё не реализованы. |

Локально каталоги трёх репозиториев располагаются рядом в `/home/user/work2/`.
Обзор разделения и карта серверной стороны находятся в
[README проекта](https://github.com/ronkiko/ai_research/blob/main/README.md) и
[общей архитектуре](https://github.com/ronkiko/ai_research/blob/main/ARCHITECTURE.md).

## Текущий клиент

Текущий flow: Account Login → Realm → Lobby → Character Model/Appearance → World.
Public protocol **v9 TCP/TLS JSONL**, единый server Realm tick; client physics,
prediction, render и UI используют независимые clocks. Сервер владеет live State
и физикой. Клиент имеет owner prediction, remote interpolation и native presentation.

Открой `godot/project.godot`; main scene — MMO Login. Настройка endpoint/security
profile производится в UI согласно server stand. Private credentials и handoffs
не сохраняются как preferences. Client/server deployment и performance результаты
проверяются отдельно от наличия кода.

[Единый стандарт документации](../ai_research/DOCUMENTATION-POLICY.md) применяется
ко всем компонентам multirepo. Ретроспективный аудит 10.00 охватывает исходные
server/client репозитории; `go-networking` содержит проверенный standalone GNS IPC.
Сетевая архитектура Go описывается в private
[`go-networking/README.md`](https://github.com/ronkiko/go-networking/blob/main/README.md);
контракт синхронизации — в
[`DOCUMENTATION-CONTRACT.md`](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/go-networking/DOCUMENTATION-CONTRACT.md).
Go GNC удалён решением Директора 2026-10-16. [Godot SDK addon](addons/mmo_sdk/README.md) использует GDScript и штатные transport primitives Godot; [10.02 smoke](experiments/client_sdk/README.md) изолирован от игры. Внешняя сеть и MMO integration остаются **PLANNED/DRAFT**.

## Другие материалы

- `references/` — локальные reference/source materials; каталог игнорируется Git и
  не входит в чистый checkout. Canonical client assets находятся в `godot/assets/`.
- `reference_projects/`, Godot mannequin/rig/archive — самостоятельные эксперименты.
- Корневой HTML/CSS — библиотека прежней Canvas игры; `.legacy/web/` содержит её
  только в локальных checkout, где ignored архив сохранён. В чистом Git checkout
  ссылка не даёт playable browser game.
- `.local/` — локальные источники; `.logacy/3d-models/` — deferred 3D материалы,
  отдельные от `.legacy`. Они не входят в воспроизводимый MMO deployment.
- `.uid` и `.import` sidecars versioned; `.godot` caches generated/ignored.

Исторические RC3 сценки не задают server physics. Подготовка новых frames и
recipe replay описаны в [assets/tools](godot/docs/assets-and-tools.md).
