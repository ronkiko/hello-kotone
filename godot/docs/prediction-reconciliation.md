# Owner prediction и reconciliation — protocol v9

Статус: **IMPLEMENTED**. [Карта клиента](../../ARCHITECTURE.md).

Platform presentation использует native CharacterBody2D с server-selected
body/motor dimensions и forces. Input intent тот же, который MmoClient ставит
в bounded desired-control slot. Native physics local_ordinal независим от Realm
tick; history и control ledger ограничены 40 записями, history живёт до 2 секунд.
Сопоставление использует реально отправленный control_seq и server
control_started_tick, затем receive-relative retirement локальных intervals.
Прямого сравнения local ordinal и server tick для удаления history нет.

Authoritative sample возвращает body к server pose/velocity и replay оставшихся
допустимых intervals. Contact response и discontinuity приоритетны над smoothing.
Native peer proxies дают geometry hints, но не определяют mass/force результата.
При stale samples, unknown outcome, переполнении ledger или смене scope prediction
fences; новая подтверждённая база необходима для продолжения.

Visual offset скрывает bounded correction; camera следует presentation.
Gait получает integrated/rendered displacement отдельно от reconciliation.
Небольшая cosmetic lead на остановке не меняет body, State или checkpoints.
[Общий нормативный контракт](../../../ai_research/v3/game/docs/client-prediction-and-reconciliation.md),
[remote timeline](multiplayer-presentation.md), [frame stall](frame-health.md).
