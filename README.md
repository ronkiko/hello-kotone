# Hello Kotone

Человеческий Godot-клиент исследовательского MMO.
**[Карта клиента](ARCHITECTURE.md)** → [Godot contracts/runbook](godot/README.md).
Сервер и общие спецификации находятся в соседнем
[ai_research](../ai_research/ARCHITECTURE.md) ([GitHub](https://github.com/ronkiko/ai_research/blob/main/ARCHITECTURE.md)).

Текущий flow: Account Login → Realm → Lobby → Character Model/Appearance → World.
Public protocol **v9 TCP/TLS JSONL**, единый server Realm tick; client physics,
prediction, render и UI используют независимые clocks. Сервер владеет live State
и физикой. Клиент имеет owner prediction, remote interpolation и native presentation.

Открой `godot/project.godot`; main scene — MMO Login. Настройка endpoint/security
profile производится в UI согласно server stand. Private credentials и handoffs
не сохраняются как preferences. Client/server deployment и performance результаты
проверяются отдельно от наличия кода.

[Единый стандарт документации](../ai_research/DOCUMENTATION-POLICY.md) и
[10.00 audit](../ai_research/v3/docs/roadmap/v3/main/10/00-review-and-validation.md)
охватывают оба репозитория. Будущие **GNC/GNS/GNPC — PLANNED/DRAFT**;
Go transport пока не обслуживает игру. [Черновик](https://github.com/ronkiko/ai_research/blob/main/v3/game/docs/go-networking/README.md).

## Другие материалы

- `references/` — source/reference art, в том числе tracked inputs canonical recipes.
- `reference_projects/`, Godot mannequin/rig/archive — самостоятельные эксперименты.
- Корневой HTML/CSS — библиотека прежней Canvas игры; `.legacy/web/` содержит её
  только в локальных checkout, где ignored архив сохранён. В чистом Git checkout
  ссылка не даёт playable browser game.
- `.local/` — локальные источники; `.logacy/3d-models/` — deferred 3D материалы,
  отдельные от `.legacy`. Они не входят в воспроизводимый MMO deployment.
- `.uid` и `.import` sidecars versioned; `.godot` caches generated/ignored.

Исторические RC3 сценки не задают server physics. Подготовка новых frames и
recipe replay описаны в [assets/tools](godot/docs/assets-and-tools.md).
