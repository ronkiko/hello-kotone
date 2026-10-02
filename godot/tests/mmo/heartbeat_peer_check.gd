extends "res://tests/mmo/recovery_check.gd"
## Additional commands exercise real idle transport, without world resync/input.
var replies: Dictionary = {}
var replica_changes := 0

func start() -> void:
	await super.start()
	client.response_received.connect(func(op: String, _data: Dictionary): replies[op] = replies.get(op,0) + 1)
	client.world_replica.changed.connect(func(): replica_changes += 1)

func execute(command: Dictionary) -> void:
	if command.action == "logout":
		# Test coordinator must wait until its UI action can be admitted; a pending
		# ping legitimately shares the one public request slot. No request retry.
		while client.state == "READY" and (not client._pending.is_empty() or not client._scheduled.is_empty()):
			await process_frame
	if command.action == "watch":
		await watch(command)
		return
	if command.action != "idle":
		await super.execute(command)
		return
	var before: Dictionary = client.world_replica.snapshot()
	var session: String = client.session_id
	var ready_before := ready_count
	var changes_before := replica_changes
	var requests_before: Dictionary = replies.duplicate()
	var scene_before: Node = current_scene
	var states_before := states.size()
	var elapsed := Time.get_ticks_msec()
	var policy: Dictionary = client.session_rules
	check(policy.idle_timeout_ms == command.timeout and policy.min_request_interval_ms == command.minimum, "NEGOTIATED_HOST_POLICY")
	policy.idle_timeout_ms = 999999
	check(client.session_rules.idle_timeout_ms == command.timeout,"HOST_RULES_DEFENSIVE_COPY")
	await create_timer(float(command.duration_ms)/1000.0).timeout
	check(client.state == "READY" and client.session_id == session and current_scene == scene_before, "IDLE_SURVIVES_SAME_SESSION_SCENE")
	check(client.world_replica.snapshot() == before and replica_changes == changes_before, "PING_NEVER_CHANGES_REPLICA_EPOCH_REVISION_X_MEMBERSHIP")
	check(ready_count == ready_before and states.size() == states_before, "PING_NEVER_REENTERS_READY_OR_RESYNCS")
	check(replies.get("ping",0) > requests_before.get("ping",0) + 1,"MULTIPLE_IDLE_PONGS")
	for op in ["move","state","map","world_rules","enter","logout"]:
		check(replies.get(op,0) == requests_before.get(op,0), "NO_IDLE_" + op.to_upper())
	var value := {"duration_ms":Time.get_ticks_msec()-elapsed,"snapshot":before,"session_unchanged":client.session_id == session,"responses":replies.duplicate(),"policy":client.session_rules,"failures":failures.duplicate()}
	evidence.append({"sequence":sequence,"action":command.action,"value":value})
	write_reply(sequence,value)
	busy = false

func watch(command: Dictionary) -> void:
	var session: String = client.session_id
	var view: Dictionary = client.world_replica.view()
	var x: int = view.confirmed_local_x
	var changes_before: int = replies.get("ping",0)
	var state_count: int = replies.get("state",0)
	var ready_before := ready_count
	await create_timer(float(command.duration_ms)/1000).timeout
	view = client.world_replica.view()
	check(client.state == "READY" and client.session_id == session and ready_count == ready_before, "SPECTATOR_KEEPS_SESSION")
	check(view.confirmed_local_x == x and view.epoch == command.epoch and view.players.size() == 2, "SPECTATOR_IDENTITY_MEMBERSHIP_X")
	check(view.revision == command.revision and view.players.p2.x == command.remote_x, "SPECTATOR_APPLIES_REMOTE_MOVES")
	check(replies.get("ping",0) >= changes_before + 2 and replies.get("state",0) == state_count and replies.get("move",0) == 0, "INCOMING_EVENTS_DO_NOT_SUPPRESS_PING_OR_TRIGGER_RESYNC")
	var value := {"revision":view.revision,"local_x":x,"remote_x":view.players.p2.x,"session_unchanged":client.session_id == session,"responses":replies.duplicate(),"failures":failures.duplicate()}
	evidence.append({"sequence":sequence,"action":command.action,"value":value})
	write_reply(sequence,value)
	busy = false
