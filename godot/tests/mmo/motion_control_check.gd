extends SceneTree
const Fixtures = preload("res://tests/mmo/replica_check.gd")
const InputAdapter = preload("res://scripts/ui/move_input.gd")
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var client: Node = root.get_node("MmoClient")
	client.state = "READY"
	client._world_rules = {"movement":{"engage_ms":100}}
	check(client.set_control(0, -1), "stationary turn scheduled")
	check(client._scheduled.payload == {"control_seq":1,"drive":0,"facing":-1}, "complete semantic control")
	client.set_control(1,-1)
	client.set_control(0,-1)
	check(client._scheduled.payload == {"control_seq":1,"drive":0,"facing":-1}, "short tap persists after coalescing")
	for i in range(1000): client.set_control(i % 3 - 1, -1)
	check(client._scheduled.size() == 2 and client._server_input_seq == 0, "bounded one slot no sequence consumption")
	client._pending = {"op":"control_set","payload":{"control_seq":1,"drive":0,"facing":-1}}
	client._scheduled = {}
	client.set_control(0,1)
	check(client._scheduled.is_empty() and client._desired_input == {"drive":0,"facing":1}, "latest state retained during in flight")
	check(not client.set_control(2,1) and not client.set_control(0,0), "bounded semantic domains")
	client._clear_session()
	check(client._server_input_seq == 0 and client._desired_input.drive == 0 and client._scheduled.is_empty(), "fresh session no unknown replay")
	client.state = "READY"
	client._world_rules = {"movement":{"engage_ms":120}}
	var controller := InputAdapter.new()
	controller.client = client
	root.add_child(controller)
	controller.set_physics_process(false)
	controller._require_release = false
	controller.sample_direction(-1, 1.0/60.0)
	check(client._desired_input == {"drive":0,"facing":-1}, "press turns only")
	for i in range(7): controller.sample_direction(-1, 1.0/60.0)
	check(client._desired_input.drive == 0, "no engage before server's 120ms")
	controller.sample_direction(-1, 1.0/60.0)
	controller.sample_direction(-1, 1.0/60.0)
	check(client._desired_input.drive == -1, "drive engages after server's 120ms")
	controller.sample_direction(0, 1.0/60.0)
	check(client._desired_input == {"drive":0,"facing":-1}, "release preserves facing")
	client.disconnect_world()
	controller.queue_free()
	print(JSON.stringify({"suite":"motion-control","checks":checks,"failures":failures,"result":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
