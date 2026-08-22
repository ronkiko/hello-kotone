extends Node

signal letter_collected(value: String)
signal game_reset

var current_room := "hall"
var elapsed_seconds := 0.0
var letters_collected: Array[String] = []
var letters_burned := false
var henshin_active := false
var game_completed := false

func reset() -> void:
	current_room = "hall"
	elapsed_seconds = 0.0
	letters_collected.clear()
	letters_burned = false
	henshin_active = false
	game_completed = false
	game_reset.emit()

func collect_letter(value: String) -> void:
	if letters_burned or value in letters_collected:
		return
	letters_collected.append(value)
	letter_collected.emit(value)
