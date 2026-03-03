extends Node

var booted := false

func _ready() -> void:
	if booted:
		return
	booted = true
	GameFlow.start_new_game()
