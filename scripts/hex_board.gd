class_name HexBoard
extends TileMap
signal transport_goal_reached(unit_name: String, score_delta: int, total_score: int)
signal unit_removed(payload: Dictionary)
signal defeat_condition_met(reason: String)

const UnitState = preload("res://scripts/board/unit_state.gd")
const UnitDataService = preload("res://scripts/board/unit_data_service.gd")
const BoardCatalogService = preload("res://scripts/board/board_catalog_service.gd")
const BoardCombatService = preload("res://scripts/board/board_combat_service.gd")
const BoardRendererService = preload("res://scripts/board/board_renderer_service.gd")
const BoardControllerService = preload("res://scripts/board/board_controller_service.gd")
const BoardTurnService = preload("res://scripts/board/board_turn_service.gd")
const BoardVisibilityService = preload("res://scripts/board/board_visibility_service.gd")
const BoardCaptureService = preload("res://scripts/board/board_capture_service.gd")
const BoardProductionService = preload("res://scripts/board/board_production_service.gd")
const BoardDeploymentService = preload("res://scripts/board/board_deployment_service.gd")
const BoardAITurnService = preload("res://scripts/board/board_ai_turn_service.gd")
const BoardUIService = preload("res://scripts/board/board_ui_service.gd")
const HexGridService = preload("res://scripts/board/hex_grid_service.gd")

const TERRAIN_MOVE_COST := {
	"plain": 1,
	"basin": 1,
	"forest": 2,
	"hill": 3
}
const IMPASSABLE_TERRAINS := {
	"peak": true,
	"water": true,
	"abyss": true
}
const AI_STEP_DELAY_SEC := 0.45
const AI_TURN_END_DELAY_SEC := 0.35
const UNIT_MOVE_ANIM_DURATION_SEC := 0.22
const TURN_START_HEAL_BASE_RANGE := 2
const AI_GROUPS_PATH := "res://data/ai_groups.json"
const DEFAULT_AI_GROUP := "default"
const DEFAULT_FRIENDLY_AUTO_AI_GROUP := "friendly_auto_default"
const TERRAIN_COLORS_PATH := "res://data/terrain_colors.json"
const DEFAULT_UNIT_VISION := 3
const FOG_VIEWER_FACTION := "player"
const DEFAULT_INITIAL_PLAYER_MP := 2000
const DEFAULT_INITIAL_ENEMY_MP := 0
const DEFAULT_TURN_LIMIT := 30

@export var cols := 40
@export var rows := 30
@export var hex_size := 34.0
@export var tile_width := 58
@export var tile_height := 51
@export var hex_side_length := 0
@export var stagger_axis := "y"
@export var stagger_index := "odd"

var default_terrain := "plain"
var terrain_overrides := {}
var unit_catalog := {}
var ai_groups := {}
var units: Array[Dictionary] = []
var unit_occupancy := {}
var selected_unit_idx := -1
var current_faction := "player"
var turn_count := 1
var turn_label: Label
var status_label: Label
var unit_info_label: Label
var tile_info_label: Label
var attack_confirm_handler: Callable
var move_cancel_confirm_handler: Callable
var unit_action_menu_handler: Callable
var turn_start_handler: Callable
var pending_attack_attacker_idx := -1
var pending_attack_defender_idx := -1
var pending_attack_distance := -1
var pending_production_tile := Vector2i(-1, -1)
var pending_move_cancel_unit_id := ""
var last_move_unit_id := ""
var last_move_from := Vector2i.ZERO
var last_move_to := Vector2i.ZERO
var last_move_action_sequence := -1
var last_move_revealed_new_vision := false
var action_sequence := 0
var ai_faction := "enemy"
var is_ai_running := false
var is_friendly_auto_running := false
var is_turn_start_pause := false
var unit_action_mode := ""
var hovered_tile := Vector2i(-1, -1)
var unplaced_unit_ids: Array[String] = []
var battle_score := 0
var faction_mp := {
	"player": DEFAULT_INITIAL_PLAYER_MP,
	"enemy": DEFAULT_INITIAL_ENEMY_MP
}
var faction_initial_mp := {
	"player": DEFAULT_INITIAL_PLAYER_MP,
	"enemy": DEFAULT_INITIAL_ENEMY_MP
}
var transport_goal_enabled := false
var transport_goal_tile := Vector2i(-1, -1)
var transport_goal_target_faction := "player"
var transport_goal_target_unit_class := ""
var transport_goal_score := 100
var delivered_transport_ids := {}
var capture_points := {}
var capture_allowed_unit_classes: Array[String] = ["infantry"]
var move_animations := {}
var battle_sequence_handler: Callable
var is_battle_sequence_playing := false
var terrain_color_overrides := {}
var terrain_move_cost_overrides := {}
var visible_tiles_by_faction := {}
var explored_tiles_by_faction := {}
var debug_reveal_all := false
var unit_icon_cache := {}
var units_json_path := ""
var deployment_active := false
var deployment_faction := "player"
var deployment_selected_unit_class := ""
var turn_limit := DEFAULT_TURN_LIMIT
var ai_production_allowed_classes := {}

func _ready() -> void:
	_ensure_hex_tileset()
	_load_ai_groups(AI_GROUPS_PATH)
	_load_terrain_base_colors(TERRAIN_COLORS_PATH)

func configure_hex_metrics(
	width_px: int,
	height_px: int,
	side_length_px: int = 0,
	stagger_axis_value: String = "y",
	stagger_index_value: String = "odd"
) -> void:
	tile_width = maxi(1, width_px)
	tile_height = maxi(1, height_px)
	hex_side_length = maxi(0, side_length_px)
	stagger_axis = stagger_axis_value.to_lower()
	stagger_index = stagger_index_value.to_lower()
	hex_size = float(mini(tile_width, tile_height)) * 0.5
	_ensure_hex_tileset()
	queue_redraw()

func _process(_delta: float) -> void:
	_update_hover_tile_info()
	_update_move_animations()

func bind_ui(turn: Label, status: Label, unit_info: Label, tile_info: Label = null) -> void:
	turn_label = turn
	status_label = status
	unit_info_label = unit_info
	tile_info_label = tile_info
	_update_turn_label()
	_update_status("戦場の準備ができました。")
	_clear_unit_info()
	_clear_tile_info()

func set_attack_confirm_handler(handler: Callable) -> void:
	attack_confirm_handler = handler

func set_move_cancel_confirm_handler(handler: Callable) -> void:
	move_cancel_confirm_handler = handler

func set_unit_action_menu_handler(handler: Callable) -> void:
	unit_action_menu_handler = handler

func set_turn_start_handler(handler: Callable) -> void:
	turn_start_handler = handler

func set_battle_sequence_handler(handler: Callable) -> void:
	battle_sequence_handler = handler

func set_turn_start_pause(paused: bool) -> void:
	is_turn_start_pause = paused

func run_ai_turn_if_needed() -> void:
	await BoardAITurnService.try_run_ai_turn(self)

func apply_transport_goal_from_stage(stage_data: Dictionary) -> void:
	transport_goal_enabled = false
	transport_goal_tile = Vector2i(-1, -1)
	transport_goal_target_faction = "player"
	transport_goal_target_unit_class = ""
	transport_goal_score = 100
	delivered_transport_ids.clear()
	battle_score = 0
	var goal_variant: Variant = stage_data.get("transport_goal", {})
	if not (goal_variant is Dictionary):
		_update_turn_label()
		queue_redraw()
		return
	var goal: Dictionary = goal_variant
	if bool(goal.get("enabled", true)) == false:
		_update_turn_label()
		queue_redraw()
		return
	var tile := Vector2i(-1, -1)
	if goal.has("tile"):
		tile = _to_vec2i(goal.get("tile", Vector2i(-1, -1)))
	elif goal.has("x") and goal.has("y"):
		tile = local_to_map(Vector2(float(goal.get("x", 0.0)), float(goal.get("y", 0.0))))
	if not _is_valid_hex(tile):
		_update_turn_label()
		queue_redraw()
		return
	transport_goal_tile = tile
	transport_goal_target_faction = str(goal.get("faction", "player")).strip_edges().to_lower()
	transport_goal_target_unit_class = str(goal.get("unit_class", "")).strip_edges().to_lower()
	transport_goal_score = maxi(1, int(goal.get("score", 100)))
	transport_goal_enabled = true
	_update_turn_label()
	queue_redraw()

func apply_stage_resources(stage_data: Dictionary) -> void:
	var initial_player := DEFAULT_INITIAL_PLAYER_MP
	var initial_enemy := DEFAULT_INITIAL_ENEMY_MP
	var resources_variant: Variant = stage_data.get("resources", {})
	if resources_variant is Dictionary:
		var resources := resources_variant as Dictionary
		var initial_variant: Variant = resources.get("initial_mp", {})
		if initial_variant is Dictionary:
			var initial_mp := initial_variant as Dictionary
			initial_player = int(initial_mp.get("player", initial_player))
			initial_enemy = int(initial_mp.get("enemy", initial_enemy))
		elif resources.has("initial_mp_player") or resources.has("initial_mp_enemy"):
			initial_player = int(resources.get("initial_mp_player", initial_player))
			initial_enemy = int(resources.get("initial_mp_enemy", initial_enemy))
	faction_initial_mp["player"] = initial_player
	faction_initial_mp["enemy"] = initial_enemy
	faction_mp["player"] = initial_player
	faction_mp["enemy"] = initial_enemy
	_update_turn_label()

func apply_stage_turn_limit(stage_data: Dictionary) -> void:
	turn_limit = DEFAULT_TURN_LIMIT
	var limit_variant: Variant = stage_data.get("turn_limit", DEFAULT_TURN_LIMIT)
	turn_limit = maxi(1, int(limit_variant))
	_update_turn_label()

func apply_stage_ai_production(stage_data: Dictionary) -> void:
	ai_production_allowed_classes.clear()
	var production_variant: Variant = stage_data.get("ai_production", {})
	if not (production_variant is Dictionary):
		return
	var production := production_variant as Dictionary
	var classes_variant: Variant = production.get("enemy", [])
	if not (classes_variant is Array):
		return
	var normalized: Array[String] = []
	var seen := {}
	for class_variant in (classes_variant as Array):
		var unit_class := str(class_variant).strip_edges().to_lower()
		if unit_class == "":
			continue
		if seen.has(unit_class):
			continue
		seen[unit_class] = true
		normalized.append(unit_class)
	ai_production_allowed_classes["enemy"] = normalized

func apply_capture_points_from_stage(stage_data: Dictionary) -> void:
	BoardCaptureService.apply_capture_points_from_stage(self, stage_data)
	_update_turn_label()

func load_units(json_path: String) -> void:
	units_json_path = json_path
	var loaded := UnitDataService.load_units(json_path)
	if not bool(loaded.get("ok", false)):
		_update_status(str(loaded.get("error", "ユニットデータの読み込みに失敗しました。")))
		return
	unit_catalog = (loaded.get("unit_catalog", {}) as Dictionary).duplicate(true)
	var loaded_units_variant: Variant = loaded.get("units", [])
	units.clear()
	if loaded_units_variant is Array:
		for item in loaded_units_variant:
			if item is Dictionary:
				units.append((item as Dictionary).duplicate(true))
	_apply_ai_groups_to_units()
	current_faction = "player"
	turn_count = 1
	_warm_unit_icon_cache()
	_rebuild_unit_occupancy()
	explored_tiles_by_faction.clear()
	BoardVisibilityService.recompute_visibility_on_board(self)
	BoardTurnService.reset_turn_action_flags(self, current_faction)
	_clear_pending_attack()
	_clear_pending_move_cancel()
	_clear_last_move_record()
	unit_action_mode = ""
	queue_redraw()
	_update_turn_label()
	_update_status("味方ユニットをクリックして行動を選択 | 「ターン終了」で手番交代")
	_clear_unit_info()

func get_unit_catalog_classes() -> Array[String]:
	var result: Array[String] = []
	for key in unit_catalog.keys():
		var unit_class := str(key).strip_edges().to_lower()
		if unit_class != "":
			result.append(unit_class)
	result.sort()
	return result

func get_unit_catalog_entry(unit_class: String) -> Dictionary:
	var key := unit_class.strip_edges().to_lower()
	if key == "" or not unit_catalog.has(key):
		return {}
	var entry_variant: Variant = unit_catalog.get(key, {})
	if entry_variant is Dictionary:
		return (entry_variant as Dictionary).duplicate(true)
	return {}

func update_unit_catalog_entry(unit_class: String, entry: Dictionary) -> void:
	var key := unit_class.strip_edges().to_lower()
	if key == "":
		return
	var next := entry.duplicate(true)
	next[UnitState.UNIT_CLASS] = key
	unit_catalog[key] = next
	units = BoardCatalogService.apply_catalog_entry_to_units(units, key, next)
	_warm_unit_icon_cache()
	BoardVisibilityService.recompute_visibility_on_board(self)
	queue_redraw()

func save_unit_catalog() -> bool:
	var path := units_json_path if units_json_path != "" else "res://data/units.json"
	return BoardCatalogService.save_catalog_to_path(unit_catalog, path)

func apply_stage_unit_spawns(stage_data: Dictionary) -> void:
	unplaced_unit_ids.clear()
	explored_tiles_by_faction.clear()
	var spawns_variant: Variant = stage_data.get("unit_spawns", [])
	if not (spawns_variant is Array):
		units.clear()
		_rebuild_unit_occupancy()
		BoardVisibilityService.recompute_visibility_on_board(self)
		_update_status("Tiledのspawn定義が見つかりません。")
		queue_redraw()
		return
	var spawns := spawns_variant as Array
	if not unit_catalog.is_empty():
		var spawned := UnitDataService.spawn_units_from_catalog(
			unit_catalog,
			spawns,
			Callable(self, "_spawn_to_tile"),
			Callable(self, "_is_valid_hex")
		)
		units.clear()
		var spawned_units_variant: Variant = spawned.get("units", [])
		if spawned_units_variant is Array:
			for item in spawned_units_variant:
				if item is Dictionary:
					units.append((item as Dictionary).duplicate(true))
		var spawned_unplaced_variant: Variant = spawned.get("unplaced_ids", [])
		if spawned_unplaced_variant is Array:
			for id_raw in spawned_unplaced_variant:
				unplaced_unit_ids.append(str(id_raw))
		var status_text := str(spawned.get("status", ""))
		if status_text != "":
			_update_status(status_text)
		_apply_ai_groups_to_units()
		_warm_unit_icon_cache()
		_rebuild_unit_occupancy()
		BoardVisibilityService.recompute_visibility_on_board(self)
		queue_redraw()
		return
	var applied := UnitDataService.apply_legacy_spawns(
		units,
		spawns,
		Callable(self, "_spawn_to_tile"),
		Callable(self, "_is_valid_hex")
	)
	var applied_unplaced_variant: Variant = applied.get("unplaced_ids", [])
	if applied_unplaced_variant is Array:
		for id_raw in applied_unplaced_variant:
			unplaced_unit_ids.append(str(id_raw))
	var applied_status := str(applied.get("status", ""))
	if applied_status != "":
		_update_status(applied_status)
	_apply_ai_groups_to_units()
	_warm_unit_icon_cache()
	_rebuild_unit_occupancy()
	BoardVisibilityService.recompute_visibility_on_board(self)
	queue_redraw()

func _load_ai_groups(json_path: String) -> void:
	ai_groups.clear()
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_warning("AIグループ定義の読み込みに失敗: %s" % json_path)
		ai_groups[DEFAULT_AI_GROUP] = {}
		ai_groups[DEFAULT_FRIENDLY_AUTO_AI_GROUP] = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("AIグループ定義の形式が不正です。")
		ai_groups[DEFAULT_AI_GROUP] = {}
		ai_groups[DEFAULT_FRIENDLY_AUTO_AI_GROUP] = {}
		return
	var root := parsed as Dictionary
	var groups_variant: Variant = root.get("groups", {})
	if groups_variant is Dictionary:
		for key in (groups_variant as Dictionary).keys():
			var name := str(key).strip_edges().to_lower()
			if name == "":
				continue
			var value: Variant = (groups_variant as Dictionary).get(key, {})
			if value is Dictionary:
				ai_groups[name] = (value as Dictionary).duplicate(true)
	if not ai_groups.has(DEFAULT_AI_GROUP):
		ai_groups[DEFAULT_AI_GROUP] = {}
	if not ai_groups.has(DEFAULT_FRIENDLY_AUTO_AI_GROUP):
		ai_groups[DEFAULT_FRIENDLY_AUTO_AI_GROUP] = {}

func _apply_ai_groups_to_units() -> void:
	for unit in units:
		var group := str(unit.get(UnitState.AI_GROUP, "")).strip_edges().to_lower()
		if group == "":
			unit[UnitState.AI_GROUP] = DEFAULT_AI_GROUP
		elif not ai_groups.has(group):
			push_warning("未知のai_group '%s' を検出。defaultを適用します。" % group)
			unit[UnitState.AI_GROUP] = DEFAULT_AI_GROUP
		var friendly_auto_group := str(unit.get(UnitState.FRIENDLY_AUTO_AI_GROUP, "")).strip_edges().to_lower()
		if friendly_auto_group == "":
			unit[UnitState.FRIENDLY_AUTO_AI_GROUP] = DEFAULT_FRIENDLY_AUTO_AI_GROUP
		elif not ai_groups.has(friendly_auto_group):
			push_warning("未知のfriendly_auto_ai_group '%s' を検出。%sを適用します。" % [friendly_auto_group, DEFAULT_FRIENDLY_AUTO_AI_GROUP])
			unit[UnitState.FRIENDLY_AUTO_AI_GROUP] = DEFAULT_FRIENDLY_AUTO_AI_GROUP

func _spawn_to_tile(spawn: Dictionary) -> Vector2i:
	if spawn.has("tile"):
		return _to_vec2i(spawn["tile"])
	if spawn.has("x") and spawn.has("y"):
		return local_to_map(Vector2(float(spawn["x"]), float(spawn["y"])))
	return Vector2i(-1, -1)

func apply_stage_terrain(stage_data: Dictionary) -> void:
	terrain_overrides.clear()
	default_terrain = "plain"
	var terrain_block: Variant = stage_data.get("terrain", {})
	if terrain_block is Dictionary:
		default_terrain = str(terrain_block.get("default", default_terrain))
		var paint: Variant = terrain_block.get("paint", [])
		if paint is Array:
			for entry in paint:
				if not (entry is Dictionary):
					continue
				var terrain := str(entry.get("type", default_terrain))
				var tiles: Variant = entry.get("tiles", [])
				if not (tiles is Array):
					continue
				for tile_raw in tiles:
					var tile := _to_vec2i(tile_raw)
					if _is_valid_hex(tile) and terrain != default_terrain:
						terrain_overrides[tile] = terrain
	_trim_terrain_overrides_to_bounds()
	queue_redraw()

func _draw() -> void:
	BoardRendererService.draw(self)

func _unhandled_input(event: InputEvent) -> void:
	if is_ai_running or is_turn_start_pause or is_battle_sequence_playing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var clicked := local_to_map(to_local(event.position))
		if not _is_valid_hex(clicked):
			return
		_handle_click(clicked)

func _handle_click(tile: Vector2i) -> void:
	BoardControllerService.handle_click(self, tile)

# Public facade methods for board services/controllers.
func query_has_pending_attack() -> bool:
	return _has_pending_attack()

func query_has_pending_move_cancel() -> bool:
	return _has_pending_move_cancel()

func query_unit_at(tile: Vector2i) -> int:
	return _unit_at(tile)

func query_unit_count() -> int:
	return units.size()

func query_capture_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in capture_points.keys():
		if not (key is Vector2i):
			continue
		var tile := key as Vector2i
		var point_variant: Variant = capture_points.get(tile, {})
		var point: Dictionary = point_variant if point_variant is Dictionary else {}
		result.append({
			"tile": tile,
			"owner": str(point.get("owner", "neutral")),
			"name": str(point.get("name", "")),
			"income": int(point.get("income", 0))
		})
	return result

func query_capture_point_at(tile: Vector2i) -> Dictionary:
	return BoardCaptureService.capture_point_at(self, tile)

func query_turn_start_heal_base_range() -> int:
	return TURN_START_HEAL_BASE_RANGE

func query_unit_action_mode() -> String:
	return unit_action_mode

func query_is_deployment_active() -> bool:
	return deployment_active

func query_unit(idx: int) -> Dictionary:
	if idx < 0 or idx >= units.size():
		return {}
	return units[idx]

func query_current_faction() -> String:
	return str(current_faction)

func query_turn_count() -> int:
	return int(turn_count)

func query_is_unit_animating(unit_id: String) -> bool:
	if unit_id == "":
		return false
	return move_animations.has(unit_id)

func query_is_unit_visible_to_player(unit_idx: int) -> bool:
	return BoardVisibilityService.is_unit_visible_to_player(self, unit_idx)

func query_is_tile_visible_to_player(tile: Vector2i) -> bool:
	return BoardVisibilityService.is_tile_visible_to_player(self, tile)

func query_is_tile_explored_to_player(tile: Vector2i) -> bool:
	return BoardVisibilityService.is_tile_explored_to_player(self, tile)

func query_is_tile_explored_for_faction(tile: Vector2i, faction: String) -> bool:
	return BoardVisibilityService.is_tile_explored_for_faction(self, tile, faction)

func query_explored_tile_count_for_faction(faction: String) -> int:
	return BoardVisibilityService.explored_tile_count_for_faction(self, faction)

func query_selected_text(unit: Dictionary) -> String:
	return _selected_text(unit)

func cmd_update_status(text: String) -> void:
	_update_status(text)

func cmd_update_unit_info(unit: Dictionary) -> void:
	_update_unit_info(unit)

func cmd_clear_unit_info() -> void:
	_clear_unit_info()

func query_can_offer_move_cancel(unit_idx: int) -> bool:
	return _can_offer_move_cancel(unit_idx)

func query_can_unit_capture_on_current_tile(unit_idx: int) -> bool:
	return BoardCaptureService.can_unit_capture_on_current_tile(self, unit_idx)

func query_can_open_production_menu(tile: Vector2i) -> bool:
	return _can_open_production_menu(tile)

func cmd_request_move_cancel_confirmation(unit_idx: int) -> void:
	_request_move_cancel_confirmation(unit_idx)

func cmd_request_attack_confirmation(attacker_idx: int, defender_idx: int, distance: int) -> void:
	_request_attack_confirmation(attacker_idx, defender_idx, distance)

func query_can_unit_attack_at_range(unit: Dictionary, distance: int) -> bool:
	return _can_unit_attack_at_range(unit, distance)

func query_can_move_unit_to(unit_idx: int, target_center: Vector2i) -> bool:
	return _can_move_unit_to(unit_idx, target_center)

func cmd_start_move_animation(unit_id: String, from_tile: Vector2i, to_tile: Vector2i) -> void:
	_start_move_animation(unit_id, from_tile, to_tile)

func cmd_move_unit_to(unit_idx: int, target_tile: Vector2i) -> void:
	_move_unit_to(unit_idx, target_tile)

func cmd_set_last_move_record(unit_id: String, start_pos: Vector2i, end_pos: Vector2i, revealed_new_vision: bool = false) -> void:
	_set_last_move_record(unit_id, start_pos, end_pos, revealed_new_vision)

func cmd_try_award_transport_goal(unit_idx: int) -> bool:
	return _try_award_transport_goal(unit_idx)

func cmd_execute_unit_move(unit_idx: int, target_tile: Vector2i) -> Dictionary:
	if unit_idx < 0 or unit_idx >= units.size():
		return {"moved": false, "awarded": false, "revealed_new_vision": false}
	var start_tile := _to_vec2i(units[unit_idx].get(UnitState.POS, Vector2i.ZERO))
	if start_tile == target_tile:
		return {"moved": false, "awarded": false, "revealed_new_vision": false}
	var moved_unit_id := str(units[unit_idx].get(UnitState.ID, ""))
	var faction := str(units[unit_idx].get(UnitState.FACTION, ""))
	var explored_before := BoardVisibilityService.explored_tile_count_for_faction(self, faction)
	_start_move_animation(moved_unit_id, start_tile, target_tile)
	_move_unit_to(unit_idx, target_tile)
	units[unit_idx][UnitState.MOVED] = true
	action_sequence += 1
	var explored_after := BoardVisibilityService.explored_tile_count_for_faction(self, faction)
	var revealed_new_vision := explored_after > explored_before
	_set_last_move_record(moved_unit_id, start_tile, target_tile, revealed_new_vision)
	_clear_pending_move_cancel()
	var awarded := _try_award_transport_goal(unit_idx)
	queue_redraw()
	return {
		"moved": true,
		"awarded": awarded,
		"revealed_new_vision": revealed_new_vision
	}

func cmd_clear_pending_move_cancel() -> void:
	_clear_pending_move_cancel()

func cmd_set_unit_action_mode(mode: String) -> void:
	unit_action_mode = mode.strip_edges().to_lower()
	queue_redraw()

func cmd_start_initial_deployment_phase() -> void:
	BoardDeploymentService.start_initial_phase(self)

func cmd_finish_initial_deployment_phase() -> void:
	BoardDeploymentService.finish_initial_phase(self)

func cmd_request_deployment_menu() -> void:
	BoardDeploymentService.request_menu(self)

func cmd_select_deployment_unit_class(unit_class: String) -> bool:
	return BoardDeploymentService.select_unit_class(self, unit_class)

func cmd_try_deploy_selected_unit_at(tile: Vector2i) -> bool:
	return BoardDeploymentService.try_deploy_selected_at(self, tile)

func cmd_request_production_menu(tile: Vector2i) -> void:
	_request_production_menu(tile)

func cmd_request_unit_action_menu(unit_idx: int, after_move: bool = false) -> void:
	if unit_idx < 0 or unit_idx >= units.size():
		return
	if not unit_action_menu_handler.is_valid():
		return
	var items: Array[Dictionary] = []
	var unit := units[unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != current_faction:
		items.append({
			"action": "info",
			"label": "ユニット情報",
			"disabled": false
		})
		unit_action_menu_handler.call({
			"unit_idx": unit_idx,
			"after_move": false,
			"items": items
		})
		return
	var can_attack := _unit_can_attack(unit)
	var can_capture := BoardCaptureService.can_unit_capture_on_current_tile(self, unit_idx)
	var has_attack_target := _has_attackable_enemy_from(unit_idx)
	var attacked := bool(unit.get(UnitState.ATTACKED, false))
	var can_show_attack := has_attack_target and can_attack and not attacked
	if after_move:
		if _can_offer_move_cancel(unit_idx):
			items.append({
				"action": "cancel_move",
				"label": "移動キャンセル",
				"disabled": false
			})
		if can_show_attack:
			items.append({
				"action": "attack",
				"label": "攻撃",
				"disabled": false
			})
		items.append({
			"action": "capture",
			"label": "占領",
			"disabled": attacked or not can_capture
		})
		items.append({
			"action": "info",
			"label": "ユニット情報",
			"disabled": false
		})
	else:
		var moved := bool(unit.get(UnitState.MOVED, false))
		items.append({
			"action": "move",
			"label": "移動",
			"disabled": moved or attacked
		})
		if can_show_attack:
			items.append({
				"action": "attack",
				"label": "攻撃",
				"disabled": false
			})
		items.append({
			"action": "capture",
			"label": "占領",
			"disabled": attacked or not can_capture
		})
		items.append({
			"action": "info",
			"label": "ユニット情報",
			"disabled": false
		})
	unit_action_menu_handler.call({
		"unit_idx": unit_idx,
		"after_move": after_move,
		"items": items
	})

func cmd_choose_unit_action(action: String) -> void:
	var key := action.strip_edges().to_lower()
	if key.begins_with("produce:"):
		var unit_class := key.trim_prefix("produce:")
		BoardProductionService.try_produce_on_pending_tile(self, unit_class, current_faction)
		return
	if selected_unit_idx < 0 or selected_unit_idx >= units.size():
		return
	var unit := units[selected_unit_idx]
	if key == "info":
		unit_action_mode = ""
		_update_status(_selected_text(unit))
		_update_unit_info(unit)
		queue_redraw()
		return
	if str(unit.get(UnitState.FACTION, "")) != current_faction:
		return
	if key == "move":
		if bool(unit.get(UnitState.ATTACKED, false)):
			_update_status("%s はこのターンすでに攻撃済みのため移動できません。" % str(unit.get(UnitState.NAME, "?")))
			_update_unit_info(unit)
			unit_action_mode = ""
			queue_redraw()
			return
		if bool(unit.get(UnitState.MOVED, false)):
			_update_status("%s はこのターンすでに移動済みです。" % str(unit.get(UnitState.NAME, "?")))
			_update_unit_info(unit)
			unit_action_mode = ""
			queue_redraw()
			return
		unit_action_mode = "move"
		_update_status("移動先を選択してください。")
		_update_unit_info(unit)
		queue_redraw()
		return
	if key == "attack":
		if bool(unit.get(UnitState.ATTACKED, false)):
			_update_status("%s はこのターンすでに攻撃済みです。" % str(unit.get(UnitState.NAME, "?")))
			_update_unit_info(unit)
			unit_action_mode = ""
			queue_redraw()
			return
		if not _unit_can_attack(unit):
			_update_status("%s は攻撃できません。" % str(unit.get(UnitState.NAME, "?")))
			_update_unit_info(unit)
			unit_action_mode = ""
			queue_redraw()
			return
		unit_action_mode = "attack"
		_update_status("攻撃対象の敵ユニットを選択してください。")
		_update_unit_info(unit)
		queue_redraw()
		return
	if key == "capture":
		unit_action_mode = ""
		BoardCaptureService.try_execute_capture(self, selected_unit_idx)
		queue_redraw()
		return
	if key == "cancel_move":
		unit_action_mode = ""
		queue_redraw()
		if _can_offer_move_cancel(selected_unit_idx):
			_request_move_cancel_confirmation(selected_unit_idx)
		else:
			_update_status("このユニットは移動キャンセルできません。")
			_update_unit_info(unit)
		return
	unit_action_mode = ""
	_update_status(_selected_text(unit))
	_update_unit_info(unit)
	queue_redraw()

func cmd_clear_pending_attack() -> void:
	_clear_pending_attack()

func cmd_clear_last_move_record() -> void:
	_clear_last_move_record()

func cmd_clear_pending_production() -> void:
	pending_production_tile = Vector2i(-1, -1)

func cmd_play_attack_sequence(attacker_idx: int, defender_idx: int, distance: int) -> void:
	await _play_attack_sequence(attacker_idx, defender_idx, distance)

func cmd_remove_unit_at(unit_idx: int, reason: String = "unknown") -> Dictionary:
	return _remove_unit_at(unit_idx, reason)

func cmd_update_turn_label() -> void:
	_update_turn_label()

func cmd_grant_turn_start_income(faction: String, announce: bool = true) -> int:
	return _grant_turn_start_income(faction, announce)

func cmd_request_ai_production_for_faction(faction: String) -> Dictionary:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return {"produced": false, "reason": "invalid_faction"}
	return BoardProductionService.request_ai_production_turn(self, key)

func cmd_reset_turn_action_flags(faction: String) -> void:
	BoardTurnService.reset_turn_action_flags(self, faction)

func cmd_notify_turn_started() -> void:
	BoardTurnService.notify_turn_started(self, current_faction, TURN_START_HEAL_BASE_RANGE)

func cmd_trigger_defeat(reason: String) -> void:
	var key := reason.strip_edges().to_lower()
	if key == "":
		key = "unknown"
	defeat_condition_met.emit(key)

func query_to_vec2i(v: Variant) -> Vector2i:
	return _to_vec2i(v)

func query_hex_distance(a: Vector2i, b: Vector2i) -> int:
	return _hex_distance(a, b)

func query_is_valid_hex(tile: Vector2i) -> bool:
	return _is_valid_hex(tile)

func query_terrain_type(tile: Vector2i) -> String:
	return _terrain_type(tile)

func query_terrain_base_color(terrain: String) -> Color:
	return _terrain_base_color(terrain)

func query_terrain_move_cost(terrain: String) -> int:
	return _terrain_move_cost(terrain)

func query_is_terrain_impassable(terrain: String) -> bool:
	var key := terrain.strip_edges().to_lower()
	return bool(IMPASSABLE_TERRAINS.get(key, false))

func query_reachable_costs(unit_idx: int) -> Dictionary:
	return _compute_reachable_costs(unit_idx)

func query_unit_draw_position(unit: Dictionary) -> Vector2:
	return _unit_draw_position(unit)

func query_unit_icon_texture(unit: Dictionary) -> Texture2D:
	return _unit_icon_texture(unit)

func query_unit_can_attack(unit: Dictionary) -> bool:
	return _unit_can_attack(unit)

func query_unit_min_range(unit: Dictionary) -> int:
	return _unit_min_range(unit)

func query_unit_max_range(unit: Dictionary) -> int:
	return _unit_max_range(unit)

func query_unit_vision(unit: Dictionary) -> int:
	return _unit_vision(unit)

func query_faction_mp(faction: String) -> int:
	var key := faction.strip_edges().to_lower()
	return int(faction_mp.get(key, 0))

func query_ai_production_allowed_classes(faction: String) -> Array[String]:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return []
	if not ai_production_allowed_classes.has(key):
		return []
	var classes_variant: Variant = ai_production_allowed_classes.get(key, [])
	if not (classes_variant is Array):
		return []
	var result: Array[String] = []
	for item in (classes_variant as Array):
		var unit_class := str(item).strip_edges().to_lower()
		if unit_class != "":
			result.append(unit_class)
	return result

func query_capture_income_for_faction(faction: String) -> int:
	return _capture_income_for_faction(faction)

func grant_turn_start_income_for_current_faction(announce: bool = false) -> int:
	return _grant_turn_start_income(current_faction, announce)

func _attack(attacker_idx: int, defender_idx: int, distance: int) -> void:
	await BoardCombatService.resolve_attack(self, attacker_idx, defender_idx, distance)

func _end_turn() -> void:
	BoardTurnService.end_turn(self)

func end_turn() -> void:
	if is_ai_running or is_turn_start_pause or is_battle_sequence_playing:
		return
	if deployment_active:
		_update_status("初期配置フェイズ中はターン終了できません。")
		return
	_end_turn()

func can_run_current_faction_auto_actions() -> bool:
	if is_ai_running or is_turn_start_pause or is_battle_sequence_playing:
		return false
	if deployment_active:
		return false
	if current_faction == ai_faction:
		return false
	return BoardAITurnService.count_unacted_units(self, current_faction) > 0

func run_current_faction_auto_actions() -> void:
	if not can_run_current_faction_auto_actions():
		return
	is_ai_running = true
	is_friendly_auto_running = true
	var faction := current_faction
	selected_unit_idx = -1
	_clear_pending_attack()
	_clear_pending_move_cancel()
	_clear_last_move_record()
	unit_action_mode = ""
	_update_status("%s の未行動ユニットを自動行動中..." % faction.to_upper())
	var unit_ids := BoardAITurnService.collect_unacted_unit_ids(self, faction)
	for unit_id in unit_ids:
		var unit_idx := _unit_index_by_id(unit_id)
		if unit_idx == -1:
			continue
		var unit := units[unit_idx]
		if str(unit.get(UnitState.FACTION, "")) != faction:
			continue
		if bool(unit.get(UnitState.MOVED, false)) or bool(unit.get(UnitState.ATTACKED, false)):
			continue
		var acted := await BoardAITurnService.take_ai_unit_action(self, unit_idx)
		if acted:
			await BoardAITurnService.ai_wait(self, AI_STEP_DELAY_SEC)
	is_friendly_auto_running = false
	is_ai_running = false
	_update_status("未行動ユニットの自動行動が完了しました。")
	_update_turn_label()
	queue_redraw()

func confirm_pending_attack() -> void:
	call_deferred("_confirm_pending_attack_async")

func _confirm_pending_attack_async() -> void:
	if not _has_pending_attack():
		return
	var attacker_idx := pending_attack_attacker_idx
	var defender_idx := pending_attack_defender_idx
	var distance := pending_attack_distance
	_clear_pending_attack()
	var validation_error := BoardCombatService.validate_attack_request(self, attacker_idx, defender_idx, distance)
	if validation_error != "":
		_update_status(validation_error)
		return
	await _attack(attacker_idx, defender_idx, distance)

func _play_attack_sequence(attacker_idx: int, defender_idx: int, distance: int) -> void:
	if attacker_idx < 0 or attacker_idx >= units.size():
		return
	if defender_idx < 0 or defender_idx >= units.size():
		return
	if not battle_sequence_handler.is_valid():
		return
	var payload := {
		"kind": "attack",
		"attacker_idx": attacker_idx,
		"defender_idx": defender_idx,
		"distance": distance,
		"attacker_name": str(units[attacker_idx].get(UnitState.NAME, "?")),
		"defender_name": str(units[defender_idx].get(UnitState.NAME, "?")),
		"attacker_pos": _to_vec2i(units[attacker_idx].get(UnitState.POS, Vector2i.ZERO)),
		"defender_pos": _to_vec2i(units[defender_idx].get(UnitState.POS, Vector2i.ZERO))
	}
	await battle_sequence_handler.call(payload)

func cancel_pending_attack() -> void:
	if not _has_pending_attack():
		return
	_clear_pending_attack()
	_update_status("攻撃をキャンセルしました。")

func _request_attack_confirmation(attacker_idx: int, defender_idx: int, distance: int) -> void:
	pending_attack_attacker_idx = attacker_idx
	pending_attack_defender_idx = defender_idx
	pending_attack_distance = distance
	var attacker_name := str(units[attacker_idx].get(UnitState.NAME, "?"))
	var defender_name := str(units[defender_idx].get(UnitState.NAME, "?"))
	var text := "%s が %s を距離 %d で攻撃します。実行しますか？" % [attacker_name, defender_name, distance]
	_update_status(text)
	if attack_confirm_handler.is_valid():
		attack_confirm_handler.call(text)
	else:
		confirm_pending_attack()

func confirm_pending_move_cancel() -> void:
	if not _has_pending_move_cancel():
		return
	var unit_id := pending_move_cancel_unit_id
	_clear_pending_move_cancel()
	var unit_idx := _unit_index_by_id(unit_id)
	if unit_idx == -1:
		_update_status("移動取り消しは無効になりました。")
		return
	if not _can_offer_move_cancel(unit_idx):
		_update_status("移動取り消しは実行できません。")
		return
	_move_unit_to(unit_idx, last_move_from)
	units[unit_idx][UnitState.MOVED] = false
	selected_unit_idx = unit_idx
	queue_redraw()
	_update_status("移動を取り消しました。")
	_update_unit_info(units[unit_idx])
	_clear_last_move_record()

func cancel_pending_move_cancel() -> void:
	if not _has_pending_move_cancel():
		return
	_clear_pending_move_cancel()
	_update_status("移動取り消しを中止しました。")

func _request_move_cancel_confirmation(unit_idx: int) -> void:
	var unit := units[unit_idx]
	var unit_id := str(unit.get(UnitState.ID, ""))
	pending_move_cancel_unit_id = unit_id
	var text := "%s の移動を取り消しますか？" % str(unit.get(UnitState.NAME, "?"))
	_update_status(text)
	if move_cancel_confirm_handler.is_valid():
		move_cancel_confirm_handler.call(text)
	else:
		confirm_pending_move_cancel()

func _can_offer_move_cancel(unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var unit := units[unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != current_faction:
		return false
	if not bool(unit.get(UnitState.MOVED, false)):
		return false
	if bool(unit.get(UnitState.ATTACKED, false)):
		return false
	var unit_id := str(unit.get(UnitState.ID, ""))
	if unit_id == "" or unit_id != last_move_unit_id:
		return false
	if action_sequence != last_move_action_sequence:
		return false
	if _to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO)) != last_move_to:
		return false
	if last_move_revealed_new_vision:
		return false
	return true

func _has_pending_attack() -> bool:
	return pending_attack_attacker_idx != -1 and pending_attack_defender_idx != -1

func _clear_pending_attack() -> void:
	pending_attack_attacker_idx = -1
	pending_attack_defender_idx = -1
	pending_attack_distance = -1

func _has_pending_move_cancel() -> bool:
	return pending_move_cancel_unit_id != ""

func _clear_pending_move_cancel() -> void:
	pending_move_cancel_unit_id = ""

func _set_last_move_record(unit_id: String, start_pos: Vector2i, end_pos: Vector2i, revealed_new_vision: bool = false) -> void:
	last_move_unit_id = unit_id
	last_move_from = start_pos
	last_move_to = end_pos
	last_move_action_sequence = action_sequence
	last_move_revealed_new_vision = revealed_new_vision

func _clear_last_move_record() -> void:
	last_move_unit_id = ""
	last_move_from = Vector2i.ZERO
	last_move_to = Vector2i.ZERO
	last_move_action_sequence = -1
	last_move_revealed_new_vision = false

func _unit_index_by_id(unit_id: String) -> int:
	if unit_id == "":
		return -1
	for idx in units.size():
		if str(units[idx].get(UnitState.ID, "")) == unit_id:
			return idx
	return -1

func _rebuild_unit_occupancy() -> void:
	unit_occupancy.clear()
	for idx in units.size():
		var tile := _to_vec2i(units[idx].get(UnitState.POS, Vector2i(-9999, -9999)))
		if _is_valid_hex(tile):
			unit_occupancy[tile] = idx

func _move_unit_to(unit_idx: int, target_tile: Vector2i) -> void:
	if unit_idx < 0 or unit_idx >= units.size():
		return
	var old_tile := _to_vec2i(units[unit_idx].get(UnitState.POS, Vector2i(-9999, -9999)))
	if _is_valid_hex(old_tile):
		unit_occupancy.erase(old_tile)
	units[unit_idx][UnitState.POS] = target_tile
	if _is_valid_hex(target_tile):
		unit_occupancy[target_tile] = unit_idx
	BoardVisibilityService.recompute_visibility_on_board(self)

func _start_move_animation(unit_id: String, from_tile: Vector2i, to_tile: Vector2i) -> void:
	if unit_id == "":
		return
	if from_tile == to_tile:
		move_animations.erase(unit_id)
		return
	move_animations[unit_id] = {
		"from": map_to_local(from_tile),
		"to": map_to_local(to_tile),
		"start_ms": Time.get_ticks_msec(),
		"duration_ms": int(UNIT_MOVE_ANIM_DURATION_SEC * 1000.0)
	}
	queue_redraw()

func _unit_draw_position(unit: Dictionary) -> Vector2:
	var tile := _to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	var default_pos := map_to_local(tile)
	var unit_id := str(unit.get(UnitState.ID, ""))
	if unit_id == "" or not move_animations.has(unit_id):
		return default_pos
	var anim_variant: Variant = move_animations.get(unit_id, {})
	if not (anim_variant is Dictionary):
		return default_pos
	var anim: Dictionary = anim_variant
	var duration_ms := maxi(1, int(anim.get("duration_ms", 1)))
	var start_ms := int(anim.get("start_ms", 0))
	var elapsed := Time.get_ticks_msec() - start_ms
	if elapsed >= duration_ms:
		move_animations.erase(unit_id)
		return default_pos
	var t := clampf(float(elapsed) / float(duration_ms), 0.0, 1.0)
	var from_pos := anim.get("from", default_pos) as Vector2
	var to_pos := anim.get("to", default_pos) as Vector2
	return from_pos.lerp(to_pos, t)

func _update_move_animations() -> void:
	if move_animations.is_empty():
		return
	var finished: Array[String] = []
	var has_active := false
	var now_ms := Time.get_ticks_msec()
	for key in move_animations.keys():
		var unit_id := str(key)
		var anim_variant: Variant = move_animations[key]
		if not (anim_variant is Dictionary):
			finished.append(unit_id)
			continue
		var anim: Dictionary = anim_variant
		var duration_ms := maxi(1, int(anim.get("duration_ms", 1)))
		var start_ms := int(anim.get("start_ms", 0))
		if now_ms - start_ms >= duration_ms:
			finished.append(unit_id)
		else:
			has_active = true
	for unit_id in finished:
		move_animations.erase(unit_id)
	if has_active or not finished.is_empty():
		queue_redraw()

func _remove_unit_at(unit_idx: int, reason: String = "unknown") -> Dictionary:
	if unit_idx < 0 or unit_idx >= units.size():
		return {}
	var removed := (units[unit_idx] as Dictionary).duplicate(true)
	var removed_id := str(removed.get(UnitState.ID, ""))
	var removed_tile := _to_vec2i(removed.get(UnitState.POS, Vector2i.ZERO))
	var removed_local_position := map_to_local(removed_tile)
	if removed_id != "":
		move_animations.erase(removed_id)
	units.remove_at(unit_idx)
	_rebuild_unit_occupancy()
	BoardVisibilityService.recompute_visibility_on_board(self)
	unit_removed.emit({
		"reason": reason,
		"unit": removed,
		"tile": removed_tile,
		"local_position": removed_local_position
	})
	return removed

func _try_run_ai_turn() -> void:
	await BoardAITurnService.try_run_ai_turn(self)

func _run_ai_turn(faction: String) -> void:
	await BoardAITurnService.run_ai_turn(self, faction)

func _collect_unacted_unit_ids(faction: String) -> Array[String]:
	return BoardAITurnService.collect_unacted_unit_ids(self, faction)

func _count_unacted_units(faction: String) -> int:
	return BoardAITurnService.count_unacted_units(self, faction)

func _take_ai_unit_action(unit_idx: int) -> bool:
	return await BoardAITurnService.take_ai_unit_action(self, unit_idx)

func _ai_wait(seconds: float) -> void:
	await BoardAITurnService.ai_wait(self, seconds)

func _choose_ai_move(unit_idx: int, ai_profile: Dictionary = {}) -> Dictionary:
	return BoardAITurnService.choose_ai_move(self, unit_idx, ai_profile)

func _auto_action_targets_for_unit(unit_idx: int, ai_profile: Dictionary) -> Array[Vector2i]:
	return BoardAITurnService.auto_action_targets_for_unit(self, unit_idx, ai_profile)

func _choose_move_toward_targets(unit_idx: int, reachable: Dictionary, targets: Array[Vector2i], ai_profile: Dictionary) -> Dictionary:
	return BoardAITurnService.choose_move_toward_targets(self, unit_idx, reachable, targets, ai_profile)

func _best_attack_from_position(attacker_idx: int, from_pos: Vector2i) -> Dictionary:
	return BoardAITurnService.best_attack_from_position(self, attacker_idx, from_pos)

func _score_attack(attacker_idx: int, defender_idx: int, distance: int) -> float:
	return BoardAITurnService.score_attack(self, attacker_idx, defender_idx, distance)

func _ai_profile_for_unit(unit_idx: int) -> Dictionary:
	return BoardAITurnService.ai_profile_for_unit(self, unit_idx)

func _get_enemy_indices(faction: String) -> Array[int]:
	return BoardAITurnService.get_enemy_indices(self, faction)

func _get_visible_enemy_indices(faction: String) -> Array[int]:
	return BoardAITurnService.get_visible_enemy_indices(self, faction)

func _get_enemy_indices_for_scope(faction: String, scope: String) -> Array[int]:
	return BoardAITurnService.get_enemy_indices_for_scope(self, faction, scope)

func _profile_num(profile: Dictionary, key: String, default_value: float) -> float:
	return BoardAITurnService.profile_num(profile, key, default_value)

func _profile_bool(profile: Dictionary, key: String, default_value: bool) -> bool:
	return BoardAITurnService.profile_bool(profile, key, default_value)

func _profile_str(profile: Dictionary, key: String, default_value: String) -> String:
	return BoardAITurnService.profile_str(profile, key, default_value)

func _turn_text() -> String:
	var player_mp := query_faction_mp("player")
	var enemy_mp := query_faction_mp("enemy")
	var base := "ターン: %d/%d | 手番: %s | スコア: %d | MP P:%d E:%d" % [
		turn_count,
		turn_limit,
		current_faction.to_upper(),
		battle_score,
		player_mp,
		enemy_mp
	]
	if not transport_goal_enabled:
		return base
	var faction_label := transport_goal_target_faction.to_upper()
	var target_text := transport_goal_target_unit_class if transport_goal_target_unit_class != "" else "transport*"
	return "%s | 目標: (%d,%d) %s %s +%d" % [
		base,
		transport_goal_tile.x,
		transport_goal_tile.y,
		faction_label,
		target_text,
		transport_goal_score
	]

func _can_open_production_menu(tile: Vector2i) -> bool:
	return BoardProductionService.can_open_menu(self, tile, current_faction)

func _request_production_menu(tile: Vector2i) -> void:
	BoardProductionService.request_menu(self, tile, current_faction)

func _try_produce_unit_on_pending_tile(unit_class: String) -> bool:
	return BoardProductionService.try_produce_on_pending_tile(self, unit_class, current_faction)

func _capture_income_for_faction(faction: String) -> int:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return 0
	var total := 0
	for point_variant in capture_points.values():
		if not (point_variant is Dictionary):
			continue
		var point := point_variant as Dictionary
		var owner := str(point.get("owner", "neutral")).strip_edges().to_lower()
		if owner != key:
			continue
		total += int(point.get("income", 0))
	return total

func _grant_turn_start_income(faction: String, announce: bool = true) -> int:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return 0
	var income := _capture_income_for_faction(key)
	if income <= 0:
		return 0
	var current := int(faction_mp.get(key, 0))
	var next := current + income
	faction_mp[key] = next
	_update_turn_label()
	if announce:
		_update_status("%s のMP +%d (合計 %d)" % [key.to_upper(), income, next])
	return income

func _try_award_transport_goal(unit_idx: int) -> bool:
	if not transport_goal_enabled:
		return false
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var unit := units[unit_idx]
	var unit_class := str(unit.get(UnitState.UNIT_CLASS, "")).to_lower()
	if transport_goal_target_unit_class != "":
		if unit_class != transport_goal_target_unit_class:
			return false
	elif not _is_transport_unit(unit):
		return false
	if transport_goal_target_faction != "" and str(unit.get(UnitState.FACTION, "")).to_lower() != transport_goal_target_faction:
		return false
	if _to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO)) != transport_goal_tile:
		return false
	var unit_id := str(unit.get(UnitState.ID, ""))
	if unit_id != "" and delivered_transport_ids.has(unit_id):
		return false
	var score_delta := _delivery_score_for_unit(unit)
	battle_score += score_delta
	if unit_id != "":
		delivered_transport_ids[unit_id] = true
	_remove_unit_at(unit_idx, "transport_goal")
	_clear_pending_attack()
	_clear_pending_move_cancel()
	_clear_last_move_record()
	selected_unit_idx = -1
	unit_action_mode = ""
	_update_turn_label()
	var delivered_name := str(unit.get(UnitState.NAME, "?"))
	_update_status("輸送目標達成: %s が目標に到達。+%d (合計 %d)" % [
		delivered_name,
		score_delta,
		battle_score
	])
	transport_goal_reached.emit(delivered_name, score_delta, battle_score)
	return true

func _delivery_score_for_unit(unit: Dictionary) -> int:
	var score := int(unit.get(UnitState.DELIVERY_SCORE, transport_goal_score))
	return maxi(1, score)

func _is_transport_unit(unit: Dictionary) -> bool:
	if bool(unit.get(UnitState.IS_TRANSPORT, false)):
		return true
	var unit_class := str(unit.get(UnitState.UNIT_CLASS, "")).to_lower()
	return unit_class == "transport" or unit_class.begins_with("transport_")

func _tile_to_local_center(tile: Vector2i) -> Vector2:
	return map_to_local(tile)

func get_board_local_rect() -> Rect2:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var unit_radius := Vector2(float(tile_width) * 0.5, float(tile_height) * 0.5)
	for r in rows:
		for q in cols:
			var center := _tile_to_local_center(Vector2i(q, r))
			var low := center - unit_radius
			var high := center + unit_radius
			min_pos = Vector2(minf(min_pos.x, low.x), minf(min_pos.y, low.y))
			max_pos = Vector2(maxf(max_pos.x, high.x), maxf(max_pos.y, high.y))
	return Rect2(min_pos, max_pos - min_pos)

func _ensure_hex_tileset() -> void:
	if tile_set == null:
		tile_set = TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	if stagger_axis == "y":
		tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
		tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED if stagger_index != "even" else TileSet.TILE_LAYOUT_STACKED_OFFSET
	else:
		tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
		tile_set.tile_layout = TileSet.TILE_LAYOUT_STAIRS_RIGHT if stagger_index != "even" else TileSet.TILE_LAYOUT_STAIRS_DOWN
	tile_set.tile_size = Vector2i(tile_width, tile_height)

func _is_valid_hex(tile: Vector2i) -> bool:
	return HexGridService.is_valid_hex(tile, cols, rows)

func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	return HexGridService.hex_distance(a, b, stagger_axis, stagger_index)

func _to_vec2i(v: Variant) -> Vector2i:
	return HexGridService.to_vec2i(v)

func _trim_terrain_overrides_to_bounds() -> void:
	var to_remove: Array[Vector2i] = []
	for key in terrain_overrides.keys():
		if not (key is Vector2i):
			continue
		var tile := _to_vec2i(key)
		if not _is_valid_hex(tile):
			to_remove.append(tile)
	for tile in to_remove:
		terrain_overrides.erase(tile)

func _unit_at(tile: Vector2i) -> int:
	if not _is_valid_hex(tile):
		return -1
	if not unit_occupancy.has(tile):
		return -1
	return int(unit_occupancy[tile])

func _can_move_unit_to(unit_idx: int, target_center: Vector2i) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var reachable := _compute_reachable_costs(unit_idx)
	return reachable.has(target_center)

func _compute_reachable_costs(unit_idx: int) -> Dictionary:
	return HexGridService.compute_reachable_costs(
		unit_idx,
		units,
		unit_occupancy,
		cols,
		rows,
		stagger_axis,
		stagger_index,
		Callable(self, "_movement_cost_for_tile"),
		Callable(self, "_is_impassable_tile"),
		Callable(self, "_is_enemy_zoc_tile_for_unit")
	)

func _is_enemy_zoc_tile_for_unit(unit_idx: int, tile: Vector2i) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var unit_faction := str(units[unit_idx].get(UnitState.FACTION, ""))
	for neighbor in HexGridService.hex_neighbors(tile, cols, rows, stagger_axis, stagger_index):
		var occ_idx := _unit_at(neighbor)
		if occ_idx == -1 or occ_idx == unit_idx:
			continue
		if str(units[occ_idx].get(UnitState.FACTION, "")) != unit_faction:
			return true
	return false

func _terrain_type(tile: Vector2i) -> String:
	return str(terrain_overrides.get(tile, default_terrain))

func _unit_vision(unit: Dictionary) -> int:
	return maxi(0, int(unit.get(UnitState.VISION, DEFAULT_UNIT_VISION)))

func _warm_unit_icon_cache() -> void:
	unit_icon_cache.clear()
	for unit in units:
		var path := _unit_icon_path(unit)
		if path == "":
			continue
		_unit_icon_texture_by_path(path)

func _unit_icon_path(unit: Dictionary) -> String:
	var faction := str(unit.get(UnitState.FACTION, "")).strip_edges().to_lower()
	if faction == "player":
		var player_path := str(unit.get(UnitState.ICON_PLAYER, "")).strip_edges()
		if player_path != "":
			return player_path
	if faction == "enemy":
		var enemy_path := str(unit.get(UnitState.ICON_ENEMY, "")).strip_edges()
		if enemy_path != "":
			return enemy_path
	return str(unit.get(UnitState.ICON, "")).strip_edges()

func _unit_icon_texture(unit: Dictionary) -> Texture2D:
	var path := _unit_icon_path(unit)
	return _unit_icon_texture_by_path(path)

func _unit_icon_texture_by_path(path: String) -> Texture2D:
	if path == "":
		return null
	if unit_icon_cache.has(path):
		var cached: Variant = unit_icon_cache[path]
		if cached is Texture2D:
			return cached as Texture2D
		return null
	var loaded := ResourceLoader.load(path)
	if loaded is Texture2D:
		unit_icon_cache[path] = loaded
		return loaded as Texture2D
	unit_icon_cache[path] = null
	return null

func set_debug_reveal_all(enabled: bool) -> void:
	debug_reveal_all = enabled
	queue_redraw()

func _terrain_base_color(terrain: String) -> Color:
	var key := terrain.strip_edges().to_lower()
	if terrain_color_overrides.has(key):
		var overridden: Variant = terrain_color_overrides[key]
		if overridden is Color:
			return overridden as Color
	var fallback: Variant = BoardRendererService.TERRAIN_COLORS.get(key, BoardRendererService.TERRAIN_COLORS["plain"])
	if fallback is Color:
		return fallback as Color
	return Color(0.16, 0.18, 0.22)

func set_terrain_base_color(terrain: String, color: Color) -> void:
	var key := terrain.strip_edges().to_lower()
	if key == "":
		return
	terrain_color_overrides[key] = color
	queue_redraw()

func clear_terrain_base_color(terrain: String) -> void:
	var key := terrain.strip_edges().to_lower()
	if key == "":
		return
	var defaults := _default_terrain_base_colors()
	if defaults.has(key):
		terrain_color_overrides[key] = defaults[key]
	else:
		terrain_color_overrides.erase(key)
	queue_redraw()

func clear_all_terrain_base_colors() -> void:
	terrain_color_overrides = _default_terrain_base_colors()
	queue_redraw()

func set_terrain_move_cost(terrain: String, move_cost: int) -> void:
	var key := terrain.strip_edges().to_lower()
	if key == "":
		return
	if query_is_terrain_impassable(key):
		return
	terrain_move_cost_overrides[key] = maxi(1, move_cost)
	queue_redraw()

func clear_terrain_move_cost(terrain: String) -> void:
	var key := terrain.strip_edges().to_lower()
	if key == "":
		return
	var defaults := _default_terrain_move_costs()
	if defaults.has(key):
		terrain_move_cost_overrides[key] = int(defaults[key])
	else:
		terrain_move_cost_overrides.erase(key)
	queue_redraw()

func clear_all_terrain_move_costs() -> void:
	terrain_move_cost_overrides = _default_terrain_move_costs()
	queue_redraw()

func save_terrain_base_colors() -> bool:
	return _save_terrain_base_colors(TERRAIN_COLORS_PATH)

func _default_terrain_base_colors() -> Dictionary:
	var result := {}
	for key in BoardRendererService.TERRAIN_COLORS.keys():
		var name := str(key).strip_edges().to_lower()
		var value: Variant = BoardRendererService.TERRAIN_COLORS[key]
		if value is Color:
			result[name] = value
	return result

func _default_terrain_move_costs() -> Dictionary:
	var result := {}
	for key in TERRAIN_MOVE_COST.keys():
		var name := str(key).strip_edges().to_lower()
		result[name] = int(TERRAIN_MOVE_COST[key])
	return result

func _load_terrain_base_colors(path: String) -> void:
	terrain_color_overrides = _default_terrain_base_colors()
	terrain_move_cost_overrides = _default_terrain_move_costs()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_save_terrain_base_colors(path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var root := parsed as Dictionary
	var colors_variant: Variant = root.get("terrain_colors", {})
	if colors_variant is Dictionary:
		var color_map := colors_variant as Dictionary
		for key in color_map.keys():
			var name := str(key).strip_edges().to_lower()
			if name == "":
				continue
			var default_color := _terrain_base_color(name)
			var raw: Variant = color_map.get(key, "")
			var parsed_color := default_color
			if raw is String:
				parsed_color = Color.from_string(str(raw), default_color)
			elif raw is Color:
				parsed_color = raw as Color
			terrain_color_overrides[name] = parsed_color
	var costs_variant: Variant = root.get("terrain_move_costs", {})
	if costs_variant is Dictionary:
		var cost_map := costs_variant as Dictionary
		for key in cost_map.keys():
			var name := str(key).strip_edges().to_lower()
			if name == "":
				continue
			if query_is_terrain_impassable(name):
				continue
			var raw_cost: Variant = cost_map.get(key, 1)
			terrain_move_cost_overrides[name] = maxi(1, int(raw_cost))

func _save_terrain_base_colors(path: String) -> bool:
	var color_map := {}
	for key in terrain_color_overrides.keys():
		var name := str(key).strip_edges().to_lower()
		if name == "":
			continue
		var value: Variant = terrain_color_overrides[key]
		if value is Color:
			color_map[name] = (value as Color).to_html(true)
	var cost_map := {}
	for key in terrain_move_cost_overrides.keys():
		var name := str(key).strip_edges().to_lower()
		if name == "" or query_is_terrain_impassable(name):
			continue
		cost_map[name] = int(terrain_move_cost_overrides[key])
	var payload := {
		"terrain_colors": color_map,
		"terrain_move_costs": cost_map
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("地形色設定の保存に失敗: %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true

func _movement_cost_for_tile(tile: Vector2i) -> int:
	var terrain := _terrain_type(tile)
	if _is_impassable_tile(tile):
		return 999999
	return _terrain_move_cost(terrain)

func _terrain_move_cost(terrain: String) -> int:
	var key := terrain.strip_edges().to_lower()
	if key == "":
		return 1
	if terrain_move_cost_overrides.has(key):
		return maxi(1, int(terrain_move_cost_overrides[key]))
	return int(TERRAIN_MOVE_COST.get(key, 1))

func _is_impassable_tile(tile: Vector2i) -> bool:
	return bool(IMPASSABLE_TERRAINS.get(_terrain_type(tile), false))

func _update_status(text: String) -> void:
	BoardUIService.update_status(self, text)

func _update_turn_label() -> void:
	BoardUIService.update_turn_label(self)

func _update_unit_info(unit: Dictionary) -> void:
	BoardUIService.update_unit_info(self, unit)

func _clear_unit_info() -> void:
	BoardUIService.clear_unit_info(self)

func _update_tile_info(tile: Vector2i) -> void:
	BoardUIService.update_tile_info(self, tile)

func _clear_tile_info() -> void:
	BoardUIService.clear_tile_info(self)

func _update_hover_tile_info() -> void:
	BoardUIService.update_hover_tile_info(self)

func _selected_text(unit: Dictionary) -> String:
	return BoardUIService.selected_text(self, unit)

func _unit_min_range(unit: Dictionary) -> int:
	return int(unit.get(UnitState.MIN_RANGE, 1))

func _unit_max_range(unit: Dictionary) -> int:
	return int(unit.get(UnitState.RANGE, 1))

func _unit_can_attack(unit: Dictionary) -> bool:
	return bool(unit.get(UnitState.CAN_ATTACK, true)) and int(unit.get(UnitState.ATK, 0)) > 0

func _can_unit_attack_at_range(unit: Dictionary, distance: int) -> bool:
	if not _unit_can_attack(unit):
		return false
	return distance >= _unit_min_range(unit) and distance <= _unit_max_range(unit)

func _has_attackable_enemy_from(unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var unit := units[unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != current_faction:
		return false
	if bool(unit.get(UnitState.ATTACKED, false)):
		return false
	if not _unit_can_attack(unit):
		return false
	var from_pos := _to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	for target_idx in units.size():
		if target_idx == unit_idx:
			continue
		var target := units[target_idx]
		if str(target.get(UnitState.FACTION, "")) == current_faction:
			continue
		if not BoardVisibilityService.is_unit_visible_to_player(self, target_idx):
			continue
		var to_pos := _to_vec2i(target.get(UnitState.POS, Vector2i.ZERO))
		var distance := _hex_distance(from_pos, to_pos)
		if _can_unit_attack_at_range(unit, distance):
			return true
	return false
