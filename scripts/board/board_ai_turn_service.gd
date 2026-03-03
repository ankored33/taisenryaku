class_name BoardAITurnService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const BoardAIService = preload("res://scripts/board/board_ai_service.gd")
const HexGridService = preload("res://scripts/board/hex_grid_service.gd")
const BoardVisibilityService = preload("res://scripts/board/board_visibility_service.gd")

static func try_run_ai_turn(board: HexBoard) -> void:
	if board.query_current_faction() != board.query_ai_faction():
		return
	if board.query_is_ai_running():
		return
	board.cmd_set_ai_running(true)
	board.cmd_update_status("%s の自動行動中..." % str(board.query_ai_faction()).to_upper())
	await run_ai_turn(board, board.query_ai_faction())
	await ai_wait(board, board.AI_TURN_END_DELAY_SEC)
	board.cmd_force_end_turn()
	board.cmd_set_ai_running(false)

static func run_ai_turn(board: HexBoard, faction: String) -> void:
	var unit_ids: Array[String] = []
	for unit in board.units:
		if str(unit.get(UnitState.FACTION, "")) == faction:
			unit_ids.append(str(unit.get(UnitState.ID, "")))
	for unit_id in unit_ids:
		var unit_idx := board.query_unit_index_by_id(unit_id)
		if unit_idx == -1:
			continue
		if str(board.units[unit_idx].get(UnitState.FACTION, "")) != faction:
			continue
		var acted := await take_ai_unit_action(board, unit_idx)
		if acted:
			await ai_wait(board, board.AI_STEP_DELAY_SEC)

static func collect_unacted_unit_ids(board: HexBoard, faction: String) -> Array[String]:
	var unit_ids: Array[String] = []
	for unit in board.units:
		if str(unit.get(UnitState.FACTION, "")) != faction:
			continue
		if bool(unit.get(UnitState.MOVED, false)) or bool(unit.get(UnitState.ATTACKED, false)):
			continue
		unit_ids.append(str(unit.get(UnitState.ID, "")))
	return unit_ids

static func count_unacted_units(board: HexBoard, faction: String) -> int:
	var count := 0
	for unit in board.units:
		if str(unit.get(UnitState.FACTION, "")) != faction:
			continue
		if bool(unit.get(UnitState.MOVED, false)) or bool(unit.get(UnitState.ATTACKED, false)):
			continue
		count += 1
	return count

static func take_ai_unit_action(board: HexBoard, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return false
	if bool(board.units[unit_idx].get(UnitState.ATTACKED, false)):
		return false

	var current_pos := board.query_to_vec2i(board.units[unit_idx].get(UnitState.POS, Vector2i.ZERO))
	var ai_profile := ai_profile_for_unit(board, unit_idx)
	var force_goal_movement := profile_bool(ai_profile, "force_goal_movement", false)
	if not force_goal_movement:
		var best_now := best_attack_from_position(board, unit_idx, current_pos)
		if int(best_now.get("target_idx", -1)) != -1:
			await board.cmd_resolve_attack(unit_idx, int(best_now["target_idx"]), int(best_now["distance"]))
			return true

	if bool(board.units[unit_idx].get(UnitState.MOVED, false)):
		return false

	var move_choice := choose_ai_move(board, unit_idx, ai_profile)
	if move_choice.is_empty():
		return false

	var target_pos := board.query_to_vec2i(move_choice.get("tile", current_pos))
	var moved := false
	var moved_unit_id := str(board.units[unit_idx].get(UnitState.ID, ""))
	if target_pos != current_pos:
		var move_result := board.cmd_execute_unit_move(unit_idx, target_pos)
		moved = bool(move_result.get("moved", false))

	var moved_idx := board.query_unit_index_by_id(moved_unit_id)
	if moved_idx == -1:
		return moved
	var pos_after_move := board.query_to_vec2i(board.units[moved_idx].get(UnitState.POS, Vector2i.ZERO))
	var best_after_move := best_attack_from_position(board, moved_idx, pos_after_move)
	if int(best_after_move.get("target_idx", -1)) != -1:
		await board.cmd_resolve_attack(moved_idx, int(best_after_move["target_idx"]), int(best_after_move["distance"]))
		return true
	return moved

static func ai_wait(board: HexBoard, seconds: float) -> void:
	if seconds <= 0.0:
		return
	await board.get_tree().create_timer(seconds).timeout

static func choose_ai_move(board: HexBoard, unit_idx: int, ai_profile: Dictionary = {}) -> Dictionary:
	var reachable := board.query_reachable_costs(unit_idx)
	var profile := ai_profile
	if profile.is_empty():
		profile = ai_profile_for_unit(board, unit_idx)
	var auto_targets := auto_action_targets_for_unit(board, unit_idx, profile)
	if not auto_targets.is_empty():
		return choose_move_toward_targets(board, unit_idx, reachable, auto_targets, profile)
	return BoardAIService.choose_ai_move(
		unit_idx,
		board.units,
		reachable,
		Callable(board, "query_unit_can_attack"),
		Callable(board, "query_can_unit_attack_at_range"),
		Callable(board, "query_enemy_indices"),
		Callable(board, "query_hex_distance"),
		profile
	)

static func auto_action_targets_for_unit(board: HexBoard, unit_idx: int, ai_profile: Dictionary) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if not board.query_is_friendly_auto_running():
		return targets
	if unit_idx < 0 or unit_idx >= board.units.size():
		return targets
	if not board.transport_goal_enabled or not board.query_is_valid_hex(board.transport_goal_tile):
		return targets
	var mode := profile_str(ai_profile, "goal_mode", "none")
	if mode == "goal_tile":
		targets.append(board.transport_goal_tile)
		return targets
	if mode != "goal_ring_if_no_visible_enemy":
		return targets
	var unit := board.units[unit_idx]
	var faction := str(unit.get(UnitState.FACTION, "")).strip_edges().to_lower()
	if faction == "":
		return targets
	var enemy_scope := profile_str(ai_profile, "enemy_scope", "all")
	if not get_enemy_indices_for_scope(board, faction, enemy_scope).is_empty():
		return targets
	for tile in HexGridService.hex_neighbors(board.transport_goal_tile, board.cols, board.rows, board.stagger_axis, board.stagger_index):
		targets.append(tile)
	if targets.is_empty():
		targets.append(board.transport_goal_tile)
	return targets

static func choose_move_toward_targets(
	board: HexBoard,
	unit_idx: int,
	reachable: Dictionary,
	targets: Array[Vector2i],
	ai_profile: Dictionary
) -> Dictionary:
	var from_pos := board.query_to_vec2i(board.units[unit_idx].get(UnitState.POS, Vector2i.ZERO))
	var goal_weight := profile_num(ai_profile, "goal_weight", 1000.0)
	var goal_move_weight := profile_num(ai_profile, "goal_move_distance_weight", 1.0)
	var best_tile := from_pos
	var best_score := -INF
	for tile in reachable.keys():
		if not (tile is Vector2i):
			continue
		var candidate := tile as Vector2i
		var nearest := INF
		for target in targets:
			var d := float(board.query_hex_distance(candidate, target))
			if d < nearest:
				nearest = d
		var moved_distance := float(board.query_hex_distance(from_pos, candidate))
		var score := -nearest * goal_weight + moved_distance * goal_move_weight
		if score > best_score:
			best_score = score
			best_tile = candidate
	return {"tile": best_tile, "score": best_score}

static func best_attack_from_position(board: HexBoard, attacker_idx: int, from_pos: Vector2i) -> Dictionary:
	var ai_profile := ai_profile_for_unit(board, attacker_idx)
	return BoardAIService.best_attack_from_position(
		attacker_idx,
		from_pos,
		board.units,
		Callable(board, "query_unit_can_attack"),
		Callable(board, "query_can_unit_attack_at_range"),
		Callable(board, "query_enemy_indices"),
		Callable(board, "query_hex_distance"),
		ai_profile
	)

static func score_attack(board: HexBoard, attacker_idx: int, defender_idx: int, distance: int) -> float:
	var ai_profile := ai_profile_for_unit(board, attacker_idx)
	return BoardAIService.score_attack(
		attacker_idx,
		defender_idx,
		distance,
		board.units,
		Callable(board, "query_can_unit_attack_at_range"),
		ai_profile
	)

static func ai_profile_for_unit(board: HexBoard, unit_idx: int) -> Dictionary:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return {}
	var unit := board.units[unit_idx]
	var group_key := UnitState.AI_GROUP
	var default_group := board.DEFAULT_AI_GROUP
	if board.query_is_friendly_auto_running():
		group_key = UnitState.FRIENDLY_AUTO_AI_GROUP
		default_group = board.DEFAULT_FRIENDLY_AUTO_AI_GROUP
	var group := str(unit.get(group_key, default_group)).strip_edges().to_lower()
	if group == "" or not board.ai_groups.has(group):
		group = default_group
	var profile_variant: Variant = board.ai_groups.get(group, {})
	if profile_variant is Dictionary:
		return profile_variant as Dictionary
	return {}

static func get_enemy_indices(board: HexBoard, faction: String) -> Array[int]:
	var result: Array[int] = []
	for idx in board.units.size():
		if str(board.units[idx].get(UnitState.FACTION, "")) != faction:
			result.append(idx)
	return result

static func get_visible_enemy_indices(board: HexBoard, faction: String) -> Array[int]:
	var result: Array[int] = []
	if board.debug_reveal_all:
		return get_enemy_indices(board, faction)
	var visible := BoardVisibilityService.visible_tiles_for_faction(board, faction)
	for idx in board.units.size():
		if str(board.units[idx].get(UnitState.FACTION, "")) == faction:
			continue
		var tile := board.query_to_vec2i(board.units[idx].get(UnitState.POS, Vector2i(-1, -1)))
		if visible.has(tile):
			result.append(idx)
	return result

static func get_enemy_indices_for_scope(board: HexBoard, faction: String, scope: String) -> Array[int]:
	var mode := scope.strip_edges().to_lower()
	if mode == "visible":
		return get_visible_enemy_indices(board, faction)
	return get_enemy_indices(board, faction)

static func profile_num(profile: Dictionary, key: String, default_value: float) -> float:
	if profile.has(key):
		return float(profile.get(key, default_value))
	return default_value

static func profile_bool(profile: Dictionary, key: String, default_value: bool) -> bool:
	if profile.has(key):
		return bool(profile.get(key, default_value))
	return default_value

static func profile_str(profile: Dictionary, key: String, default_value: String) -> String:
	if profile.has(key):
		return str(profile.get(key, default_value)).strip_edges().to_lower()
	return default_value
