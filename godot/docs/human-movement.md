# Human control — protocol v9

Статус: **IMPLEMENTED**.

MoveInput samples native physics input, changes facing immediately, engages drive
after validated server engage_ms, and releases on key/focus loss. MmoClient sends
a coalesced complete control state with zone_generation/control_seq. It never sends
position as authority. Rejection/stall requires a fresh press.
[Wire](motion-wire-v8.md), [prediction](prediction-reconciliation.md).
