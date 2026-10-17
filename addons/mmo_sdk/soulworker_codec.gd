extends RefCounted
## Lazarus KRSW candidate only. Byte contract belongs to go-networking.
const MAX_FRAME: int = 4095
const KEY := [0x97, 0x67, 0x9c]
var _buffer := PackedByteArray()
var failed: bool = false

static func encode_frame(sender: int, opcode: int, payload: PackedByteArray) -> PackedByteArray:
    if sender < 0 or sender > 255 or opcode < 0 or opcode > 65535 or payload.size() + 7 > MAX_FRAME:
        return PackedByteArray()
    var size: int = payload.size() + 7
    var result := PackedByteArray([2, 0, size & 255, size >> 8, sender, opcode >> 8, opcode & 255])
    result.append_array(payload)
    for i in range(5, result.size()):
        result[i] = result[i] ^ KEY[(i - 5) % 3]
    return result

# Each call admits at most one socket-sized chunk. Completed frames are detached;
# the retained partial frame never exceeds MAX_FRAME. Failure is sticky.
func feed(data: PackedByteArray) -> Dictionary:
    if failed or data.size() > MAX_FRAME:
        failed = true
        _buffer.clear()
        return {"error": ERR_INVALID_DATA, "frames": []}
    _buffer.append_array(data)
    var frames: Array = []
    while _buffer.size() >= 5:
        var size: int = _buffer[2] | (_buffer[3] << 8)
        if _buffer[0] != 2 or _buffer[1] != 0 or size < 7 or size > MAX_FRAME:
            failed = true
            _buffer.clear()
            return {"error": ERR_INVALID_DATA, "frames": []}
        if _buffer.size() < size:
            break
        var body := _buffer.slice(5, size)
        for i in range(body.size()):
            body[i] = body[i] ^ KEY[i % 3]
        frames.append({"sender": int(_buffer[4]), "opcode": (body[0] << 8) | body[1], "payload": body.slice(2)})
        _buffer = _buffer.slice(size)
    return {"error": OK, "frames": frames}

func end_of_stream() -> int:
    if failed or not _buffer.is_empty():
        failed = true
        _buffer.clear()
        return ERR_INVALID_DATA
    return OK
