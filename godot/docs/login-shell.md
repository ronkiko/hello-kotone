# Login shell — protocol v9

Статус: **IMPLEMENTED**.

Login scene delegates Account/Realm/Lobby/Creator actions to Preworld. It renders
progress/failures without exposing secrets, and enters World only after validated
Game bootstrap/map/rules/state. Cancel or fault fences the old visit.
[Realm Lobby](realm-lobby.md) describes all current screens and lifecycle.
