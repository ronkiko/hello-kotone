# World replica — protocol v9

Статус: **IMPLEMENTED**.

The pure reducer owns confirmed values and WorldSession identity, not sockets
or physics nodes. It atomically checks/installs snapshots and motion membership,
epoch, Zone generation, revisions and sequence markers; coalesced motion may skip
physics revisions. Reliable damage and presence remain ordered.
[Current behavior](../../ARCHITECTURE.md#replica-и-пользовательское-движение).
