extends SceneTree
const SDK = preload("res://addons/mmo_sdk/mmo_sdk.gd")
const Codec = preload("res://addons/mmo_sdk/soulworker_codec.gd")
var failures: int = 0
var frames: Array = []
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

func run() -> void:
    var args := OS.get_cmdline_user_args()
    var port: int = int(args[0])
    var mode: String = args[1]
    var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://lazarus.json"))
    for vector in fixtures.vectors:
        var wire: PackedByteArray = vector.wire_hex.hex_decode()
        var payload: PackedByteArray = vector.payload_hex.hex_decode()
        check(Codec.encode_frame(vector.sender, vector.opcode, payload) == wire, "independent golden encode")
        var codec = Codec.new()
        var decoded: Array = []
        for byte in wire:
            var result: Dictionary = codec.feed(PackedByteArray([byte]))
            check(result.error == OK, "split frame")
            decoded.append_array(result.frames)
        check(decoded.size() == 1 and decoded[0].opcode == vector.opcode and decoded[0].payload == payload and decoded[0].sender == vector.sender, "independent golden decode")
        check(codec.end_of_stream() == OK, "clean EOF")
        codec = Codec.new()
        check(codec.feed(wire + wire).frames.size() == 2, "coalesced frames")
        for n in range(1, wire.size()):
            codec = Codec.new()
            check(codec.feed(wire.slice(0,n)).frames.is_empty(), "no partial dispatch")
            check(codec.end_of_stream() == ERR_INVALID_DATA, "reject truncated EOF")
    for hex in ["0300070001", "0201000001", "0200000001", "0200060001", "0200001001", "0200ffff01"]:
        var codec = Codec.new()
        check(codec.feed(hex.hex_decode()).error == ERR_INVALID_DATA, "invalid header/size")
        check(codec.feed(PackedByteArray()).error == ERR_INVALID_DATA, "sticky parser failure")
    var huge := PackedByteArray()
    huge.resize(4088)
    for sender in [0, 1, 255]:
        var wire: PackedByteArray = Codec.encode_frame(sender, 0x0203, huge)
        var result: Dictionary = Codec.new().feed(wire)
        check(wire.size() == 4095 and result.frames.size() == 1 and result.frames[0].sender == sender, "max frame and opaque sender")
    huge.resize(4089)
    check(Codec.encode_frame(1, 0x0203, huge).is_empty(), "encode oversize")
    huge.resize(4096)
    check(Codec.new().feed(huge).error == ERR_INVALID_DATA, "bounded input chunk")
    print("PASS: GDScript independent golden codec, fragmented/coalesced/bounded/malformed/EOF")

    var sdk = SDK.new()
    root.add_child(sdk)
    var first = sdk.create_client()
    check(first.connect_loopback(port, "0.0.0.0") == ERR_INVALID_PARAMETER, "refuse non-loopback")
    check(first.connect_loopback(0) == ERR_INVALID_PARAMETER, "refuse invalid port")
    first.frame_received.connect(func(frame): frames.append([0, frame]))
    first.disconnected.connect(func(reason): disconnects.append([0, reason]))
    check(first.connect_loopback(port) == OK, "first connect")
    check(first.connect_loopback(port) == ERR_ALREADY_IN_USE, "refuse duplicate connect")
    var request: PackedByteArray = fixtures.vectors[0].payload_hex.hex_decode()
    if mode.begins_with("fault:"):
        await until(func(): return disconnects.size() == 1, "fault disconnect")
        check(disconnects.size() == 1 and disconnects[0][1] == mode.trim_prefix("fault:"), "actual fault reason")
    else:
        await until(func(): return first._connected, "first connected")
        var second = sdk.create_client()
        second.frame_received.connect(func(frame): frames.append([1, frame]))
        second.disconnected.connect(func(reason): disconnects.append([1, reason]))
        check(second.connect_loopback(port) == OK, "second connect")
        await until(func(): return second._connected, "second connected")
        for client in [first, second]:
            check(client.send_frame(1, 0x0203, request) == OK, "send source fixture")
        await until(func(): return frames.size() == 2, "both independent replies")
        for entry in frames:
            check(entry[1].opcode == 0x0204 and entry[1].sender == 1 and entry[1].payload == fixtures.vectors[1].payload_hex.hex_decode(), "real TCP golden response")
        check(frames.size() == 2 and frames[0][0] != frames[1][0], "client isolation")
        print("GODOT_TWO_CLIENTS_READY")
        if mode == "exchange":
            # Reuse the same client node after disconnect; closed nodes stay closed.
            first._drop("explicit_reconnect")
            for cycle in range(24):
                var count: int = frames.size()
                check(first.connect_loopback(port) == OK, "reconnect")
                await until(func(): return first._connected, "reconnected")
                check(first.send_frame(1, 0x0203, request) == OK, "resend fixture")
                await until(func(): return frames.size() == count + 1, "reconnect reply")
                first._drop("explicit_reconnect")
            # Queue bounds are checked before polling drains the queue.
            check(first.connect_loopback(port) == OK, "queue test connect")
            await until(func(): return first._connected, "queue test connected")
            huge.resize(4088)
            check(first.send_frame(1, 0x0203, huge) == OK, "queue frame one")
            check(first.send_frame(1, 0x0203, huge) == OK, "queue frame two")
            check(first.send_frame(1, 0x0203, huge) == ERR_BUSY, "bounded send queue")
            first.close()
            var count: int = frames.size()
            check(second.send_frame(1, 0x0203, request) == OK, "second survives first close")
            await until(func(): return frames.size() == count + 1, "independent second reply")
        else:
            await until(func(): return disconnects.size() == 2, "supervisor closes both sockets")
            for entry in disconnects:
                check(entry[1] == "peer_disconnected", "real EOF before timeout")
    sdk.queue_free()
    await process_frame
    await process_frame
    if failures:
        quit(1)
    else:
        print("PASS: Godot TCP mode ", mode)
        quit(0)
