extends SceneTree
const SDK = preload("res://addons/mmo_sdk/mmo_sdk.gd")
const Codec = preload("res://addons/mmo_sdk/soulworker_codec.gd")
var failures: int = 0
var pongs: Array = []
var rejected: Array = []
var disconnects: Array = []

func check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", label)

func _initialize() -> void:
    call_deferred("run")

func until(predicate: Callable, label: String) -> void:
    var deadline: int = Time.get_ticks_msec() + 2500
    while not predicate.call() and Time.get_ticks_msec() < deadline:
        await process_frame
    check(predicate.call(), label)

func watch(client, id: int) -> void:
    client.pong_received.connect(func(nonce, rtt_usec):
        pongs.append([id, nonce.duplicate(), rtt_usec])
        check(rtt_usec >= 0 and rtt_usec < client.PING_TIMEOUT_USEC, "bounded monotonic RTT")
        print("PING_RTT client=", id, " nonce=", nonce.hex_encode(), " usec=", rtt_usec))
    client.ping_failed.connect(func(nonce, reason): rejected.append([id, nonce.duplicate(), reason]))
    client.disconnected.connect(func(reason): disconnects.append([id, reason]))

func run() -> void:
    var args := OS.get_cmdline_user_args()
    var port: int = int(args[0])
    var mode: String = args[1]
    # Independently generated using original reference Encrypt; not local roundtrip.
    var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://extensions.json"))
    for v in vectors.vectors:
        var payload: PackedByteArray = v.payload_hex.hex_decode()
        var wire: PackedByteArray = v.wire_hex.hex_decode()
        check(Codec.encode_frame(v.sender, v.opcode, payload) == wire, "extension golden encode")
        var decoded: Array = Codec.new().feed(wire).frames
        check(decoded.size() == 1 and decoded[0].opcode == v.opcode and decoded[0].payload == payload, "extension golden decode")
    var sdk = SDK.new()
    root.add_child(sdk)
    var first = sdk.create_client()
    watch(first, 0)
    var zero := "0000000000000000".hex_decode()
    var next := "0123456789abcdef".hex_decode()
    check(first.ping(zero) == ERR_UNAVAILABLE, "disconnected ping fails")
    check(first.connect_loopback(port) == OK, "connect first")
    if mode == "unsolicited":
        await until(func(): return disconnects.size() == 1, "unsolicited PONG disconnect")
        check(disconnects.size() == 1 and disconnects[0][1] == "unsolicited_pong", "unsolicited rejection")
        check(pongs.is_empty() and rejected.is_empty(), "no pending request means no outcome")
    else:
        await until(func(): return first._connected, "first connected")
        check(first.ping(PackedByteArray([1])) == ERR_INVALID_DATA, "short PING rejected locally")
        check(first.ping(PackedByteArray([0,1,2,3,4,5,6,7,8])) == ERR_INVALID_DATA, "long PING rejected locally")
        check(first.send_frame(1, first.PING_OPCODE, zero) == ERR_INVALID_PARAMETER, "raw PING cannot bypass correlation")
        check(first.ping(zero) == OK, "enqueue PING")
        check(first.ping(zero) == ERR_BUSY, "duplicate pending nonce rejected")
        check(first.ping(next) == ERR_BUSY, "one pending request bound")
        if mode in ["exchange", "shutdown", "parent_eof", "cross_connection"]:
            var second = sdk.create_client()
            watch(second, 1)
            check(second.connect_loopback(port) == OK, "connect second")
            await until(func(): return second._connected, "second connected")
            # Same nonce is valid on independent connections. Cross-delivery test
            # uses different nonces and deliberately swaps their real TCP replies.
            var second_nonce: PackedByteArray = next if mode == "cross_connection" else zero
            check(second.ping(second_nonce) == OK, "second PING")
            if mode == "cross_connection":
                await until(func(): return rejected.size() == 2, "both foreign replies fail")
                check(pongs.is_empty(), "foreign connection cannot complete either PING")
                for entry in rejected:
                    check(entry[2] == "wrong_pong_nonce", "cross-connection correlation")
            else:
                await until(func(): return pongs.size() == 2, "both real PONGs")
                check(pongs.size() == 2 and pongs[0][0] != pongs[1][0], "independent client completions")
                check(first.ping(zero) == ERR_ALREADY_EXISTS, "completed nonce cannot be reused")
                # Several rounds with simultaneous outstanding requests.
                for v in [next, "ffffffffffffffff".hex_decode(), "fedcba9876543210".hex_decode()]:
                    var count: int = pongs.size()
                    check(first.ping(v) == OK and second.ping(v) == OK, "concurrent PING round")
                    await until(func(): return pongs.size() == count + 2, "concurrent PONG round")
                    for entry in pongs.slice(count):
                        check(entry[1] == v, "exact echoed nonce")
                check(rejected.is_empty(), "valid exchanges have no failed outcomes")
                if mode == "exchange":
                    # Unknown opcode corrupts only one client's real Go connection.
                    check(first.send_frame(1, 0xfe03, zero) == OK, "send unknown opcode")
                    await until(func(): return disconnects.size() == 1, "bad peer disconnected")
                    var count: int = pongs.size()
                    check(second.ping("0000000000000001".hex_decode()) == OK, "healthy client still sends")
                    await until(func(): return pongs.size() == count + 1, "healthy client still receives PONG")
                    check(first.connect_loopback(port) == OK, "explicit reconnect")
                    await until(func(): return first._connected, "reconnected")
                    check(first.ping(zero) == ERR_ALREADY_EXISTS, "reconnect cannot reuse old nonce")
                    first.close()
                    count = pongs.size()
                    check(second.ping("0000000000000002".hex_decode()) == OK, "second survives first close")
                    await until(func(): return pongs.size() == count + 1, "independent close")
                    check(first.ping(next) == ERR_UNAVAILABLE, "permanent close refuses PING")
                else:
                    var count: int = pongs.size()
                    check(first.ping("0000000000000003".hex_decode()) == OK, "pending first before stop")
                    check(second.ping("0000000000000004".hex_decode()) == OK, "pending second before stop")
                    print("GODOT_PINGS_PENDING")
                    # Python stops GNS as soon as the marker is read. Avoid draining
                    # these writes first; still poll the real sockets for actual EOF.
                    first.set_process(false)
                    second.set_process(false)
                    await create_timer(0.1).timeout
                    first.set_process(true)
                    second.set_process(true)
                    await until(func(): return rejected.size() == 2, "pending requests fail on supervisor stop")
                    check(pongs.size() == count, "stopped server cannot complete PING")
                    for entry in rejected:
                        check(entry[2] == "peer_disconnected", "actual EOF failure")
        elif mode in ["stale", "duplicate"]:
            await until(func(): return pongs.size() == 1, "initial valid completion")
            check(first.ping(zero) == ERR_ALREADY_EXISTS, "reject repeated completed nonce")
            if mode == "stale":
                check(first.ping(next) == OK, "new pending nonce")
                await until(func(): return rejected.size() == 1, "stale PONG fails new PING")
                check(rejected.size() == 1 and rejected[0][2] == "wrong_pong_nonce", "stale nonce failure")
            else:
                await until(func(): return disconnects.size() == 1, "duplicate PONG rejected")
                check(disconnects.size() == 1 and disconnects[0][1] == "unsolicited_pong", "duplicate completion refused")
            check(pongs.size() == 1, "no second false completion")
        else:
            await until(func(): return rejected.size() == 1, "negative PING outcome")
            check(pongs.is_empty(), "invalid/missing response cannot succeed")
            var reason: String = {"timeout":"ping_timeout", "wrong_nonce":"wrong_pong_nonce", "wrong_opcode":"unexpected_extension_opcode", "short":"malformed_pong", "long":"malformed_pong", "disconnect":"peer_disconnected", "legacy_instead":"ping_timeout"}.get(mode, "invalid_test_mode")
            check(rejected.size() == 1 and rejected[0][2] == reason, "negative outcome reason " + mode)
    print("PING_OUTCOME mode=", mode, " success=", pongs.size(), " failed=", rejected.size())
    sdk.queue_free()
    await process_frame
    await process_frame
    if failures:
        quit(1)
    else:
        print("PASS: Godot PING mode ", mode)
        quit(0)
