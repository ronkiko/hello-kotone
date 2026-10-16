# Public transport — protocol v9

Статус: **IMPLEMENTED**.

PublicPeer handles Login/Lobby visits; MmoClient handles Game bootstrap and
request/control scheduling. Both use bounded native TCP/TLS and strict JSON/v9
validation, with generation fences and no automatic replay after unknown outcomes.
[Current wire contract](motion-wire-v8.md), [client map](../../ARCHITECTURE.md).
