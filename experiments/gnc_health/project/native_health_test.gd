extends SceneTree

# GDScript -> GDExtension -> Go native library, no socket or game autoloads.
func _initialize() -> void:
    var gnc: GncLocalHealth = GncLocalHealth.new()
    if gnc.abi_version() != 1:
        printerr("FAIL: Go GNC ABI version mismatch")
        quit(1)
        return
    for nonce in [0, 42, 123456, 777777]:
        var expected: int = nonce ^ 0x1234ABCD
        var actual: int = gnc.local_health(nonce)
        if actual != expected:
            printerr("FAIL: Go GNC health nonce=", nonce)
            quit(2)
            return
    print("PASS: Godot -> GDExtension -> Go GNC local HEALTH")
    quit(0)
