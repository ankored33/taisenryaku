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
var unit_catalog := {}
var ai_groups := {}
var units: Array[Dictionary] = []
var unit_occupancy := {}
var selected_unit_idx := -1
var current_faction := "player"
var turn_count := 1
var pending_attack_attacker_idx := -1
var pending_attack_defender_idx := -1
var pending_attack_distance := -1
var pending_move_confirm_unit_idx := -1
var pending_move_confirm_target_tile := Vector2i(-1, -1)
var last_move_unit_id := ""
var last_move_from := Vector2i.ZERO
var last_move_to := Vector2i.ZERO
var last_move_action_sequence := -1
var last_move_revealed_new_enemy := false
var action_sequence := 0
var ai_faction := "enemy"
var is_ai_running := false
var is_friendly_auto_running := false
var is_turn_start_pause := false
var unit_action_mode := ""
var hovered_tile := Vector2i(-1, -1)
var unplaced_unit_ids: Array[String] = []
var transport_goal_enabled := false
var transport_goal_tile := Vector2i(-1, -1)
var transport_goal_target_faction := "player"
var transport_goal_target_unit_class := ""
var transport_goal_score := 100
var transport_goal_victory_score := 300
var delivered_transport_ids := {}
var capture_points := {}
var capture_allowed_unit_classes: Array[String] = ["infantry"]
var move_animations := {}
var is_battle_sequence_playing := false
var terrain_color_overrides := {}
var terrain_move_cost_overrides := {}
var visible_tiles_by_faction := {}
var explored_tiles_by_faction := {}
var debug_reveal_all := false
var unit_icon_cache := {}
var units_json_path := ""

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
