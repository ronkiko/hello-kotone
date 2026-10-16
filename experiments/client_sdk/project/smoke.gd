extends SceneTree
const SDK = preload("res://addons/mmo_sdk/mmo_sdk.gd")
var _failures: int = 0
var _closed_count: int = 0

func check(condition: bool, label: String) -> void:
    if not condition:
        _failures += 1
        printerr("FAIL: ", label)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
    var sdk := SDK.new()
    check(sdk.create_client() == null, "factory requires an attached SDK")
    root.add_child(sdk)
    var client = sdk.create_client()
    var second = sdk.create_client()
    check(client != null and second != null and client != second, "independent client factory")
    check(client.get_parent() == sdk and second.get_parent() == sdk, "SDK owns client nodes")
    check(client.get_child_count() == 1 and client.get_child(0) is HTTPRequest, "native HTTP child")
    for nonce in [0, 42, 123456, 777777, 9223372036854775807, -1, (-9223372036854775807 - 1)]:
        var result: Dictionary = client.local_health(nonce)
        check(result.get("error") == OK and result.get("scope") == "local_sdk", "explicit local health")
        check(result.get("api_version") == 1 and result.get("nonce") == nonce, "API version / nonce correlation")
        check(result.get("http_backend") == "HTTPRequest" and result.get("http_state") == HTTPClient.STATUS_DISCONNECTED, "native HTTP idle")
        check(result.get("socket_backend") == "WebSocketPeer" and result.get("socket_state") == WebSocketPeer.STATE_CLOSED, "native WebSocket idle")
        print("SDK local nonce=", nonce, " API=", result.get("api_version"))
    # The result is detached; mutating it cannot alter the client or next result.
    var detached: Dictionary = client.local_health(7)
    detached["nonce"] = 999
    check(client.local_health(7).get("nonce") == 7, "detached result")
    client.closed.connect(func(): _closed_count += 1)
    client.close()
    client.close()
    check(_closed_count == 1, "close is idempotent and emits once")
    check(client.local_health(1).get("error") == ERR_UNAVAILABLE, "closed client fails explicitly")
    check(second.local_health(1).get("error") == OK, "independent client lifetime")
    sdk.remove_child(second)
    check(second.local_health(1).get("error") == ERR_UNAVAILABLE, "detaching closes the client")
    second.free()
    var weak_client: WeakRef = weakref(client)
    var weak_http: WeakRef = weakref(client.get_child(0))
    var weak_sdk: WeakRef = weakref(sdk)
    sdk.queue_free()
    await process_frame
    await process_frame
    check(weak_client.get_ref() == null and weak_sdk.get_ref() == null, "SDK removal releases clients")
    check(weak_http == null or weak_http.get_ref() == null, "HTTP node released")
    check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans_before, "no orphan nodes")
    if _failures:
        quit(1)
        return
    print("PASS: Godot GDScript SDK addon; native HTTPRequest/WebSocketPeer; local lifecycle")
    quit(0)
