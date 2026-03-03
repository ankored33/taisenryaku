class_name BoardRuntimeState
extends RefCounted

var pending_production_tile := Vector2i(-1, -1)
var battle_score := 0
var faction_mp := {}
var faction_initial_mp := {}
var deployment_active := false
var deployment_faction := "player"
var deployment_selected_unit_class := ""
var turn_limit := 30
var ai_production_allowed_classes := {}

func _init(initial_player_mp: int, initial_enemy_mp: int, default_turn_limit: int) -> void:
	faction_mp = {
		"player": initial_player_mp,
		"enemy": initial_enemy_mp
	}
	faction_initial_mp = {
		"player": initial_player_mp,
		"enemy": initial_enemy_mp
	}
	turn_limit = default_turn_limit
