extends RefCounted
## Strict JSON for protocol v4: Godot's JSON parser alone accepts non-wire syntax.

var _text := ""
var _at := 0
var _valid := true

func decode(bytes: PackedByteArray) -> Dictionary:
	_text = bytes.get_string_from_utf8()
	_at = 0
	_valid = _text.to_utf8_buffer() == bytes and not _text.begins_with("\ufeff")
	var value: Variant = _value(0)
	_space()
	if not _valid or _at != _text.length() or not value is Dictionary:
		return {}
	return value

func _space() -> void:
	while _at < _text.length() and _text[_at] in [" ", "\t", "\n", "\r"]:
		_at += 1

func _take(character: String) -> bool:
	_space()
	if _at < _text.length() and _text[_at] == character:
		_at += 1
		return true
	return false

func _value(depth: int) -> Variant:
	_space()
	if not _valid or depth > 16 or _at >= _text.length():
		_valid = false
		return null
	var character := _text[_at]
	if character == '"':
		return _string()
	if character == "{" or character == "[":
		_at += 1
		var object: Variant = {} if character == "{" else []
		var closing := "}" if character == "{" else "]"
		if _take(closing):
			return object
		while _valid:
			if character == "{":
				_space()
				var key: Variant = _string()
				if not _valid or object.has(key) or not _take(":"):
					_valid = false
					return null
				object[key] = _value(depth + 1)
			else:
				object.append(_value(depth + 1))
			if _take(closing):
				return object
			if not _take(","):
				_valid = false
		return null
	for literal in ["true", "false", "null"]:
		if _text.substr(_at, literal.length()) == literal:
			_at += literal.length()
			return {"true": true, "false": false, "null": null}[literal]
	var match_result := RegEx.create_from_string("^-?(0|[1-9][0-9]*)").search(_text.substr(_at))
	if match_result == null:
		_valid = false
		return null
	var number := match_result.get_string()
	_at += number.length()
	# All v4 numbers are integers; reject float/exponent forms and overflow.
	if number.trim_prefix("-").length() > 16 or absi(number.to_int()) > 9007199254740991:
		_valid = false
	return number.to_int()

func _string() -> Variant:
	var start := _at
	if _at >= _text.length() or _text[_at] != '"':
		_valid = false
		return null
	_at += 1
	while _at < _text.length():
		var character := _text[_at]
		_at += 1
		if character == '"':
			var parser := JSON.new()
			if parser.parse(_text.substr(start, _at - start)) != OK or not parser.data is String:
				_valid = false
				return null
			return parser.data
		if character.unicode_at(0) < 32:
			break
		if character == "\\":
			if _at >= _text.length() or not _text[_at] in ['"', "\\", "/", "b", "f", "n", "r", "t", "u"]:
				break
			if _text[_at] == "u":
				var hex := _text.substr(_at + 1, 4)
				if not RegEx.create_from_string("^[0-9a-fA-F]{4}$").search(hex):
					break
				var scalar := hex.hex_to_int()
				_at += 5
				if scalar >= 0xd800 and scalar <= 0xdbff:
					if _text.substr(_at, 2) != "\\u":
						break
					var low := _text.substr(_at + 2, 4)
					if not RegEx.create_from_string("^[dD][c-fC-F][0-9a-fA-F]{2}$").search(low):
						break
					_at += 6
				elif scalar >= 0xdc00 and scalar <= 0xdfff:
					break
			else:
				_at += 1
	_valid = false
	return null
