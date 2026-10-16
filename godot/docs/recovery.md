# Recovery — protocol v9

Статус: **IMPLEMENTED**. [Карта клиента](../../ARCHITECTURE.md).

Потеря обычных motion frames при живом Game TCP — Visual Stall, описанный в
[frame health](frame-health.md). Authority восстанавливает обычный validated frame,
в том числе с новым Zone generation; recovery snapshot/ACK/RESYNC не добавляются.

Transport fault закрывает старые Game/Lobby/account visits и возвращает sign-in.
Fresh Login → Realm → Lobby выдаёт новые handoffs. Если Registry подтверждает
online lease выбранного персонажа, Preworld может предложить явный takeover;
world_resume привязывает тот же live avatar к новой session. CHARACTER_BUSY и
DURABILITY_UNSAFE не дают права takeover. SESSION_REPLACED не вызывает обратного
автоматического захвата. Старые pending callbacks отсекаются visit generation.

Unknown control/enter/logout outcome не повторяется автоматически. Client очищает
prediction/desired control и требует свежего физического нажатия. Server State
может содержать уже принятую операцию; потерянный reply не означает rollback.
Create/delete отдельно имеют durable idempotency receipt: explicit reconcile
использует тот же ключ и намерение, не создаёт новую мутацию после ambiguity.

Safe logout ждёт финальный server logout_status и подтверждённую Registry
completion; pending/cancelled/dirty/unknown остаются различимыми. Client не может
объявить offline-safe по локальному timeout. Game crash и unsafe Registry barrier
могут требовать trusted offline operator recovery по server runbook.
