class_name BoardProductionService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const BoardVisibilityService = preload("res://scripts/board/board_visibility_service.gd")
const DEFAULT_AI_GROUP := "default"
const DEFAULT_FRIENDLY_AUTO_AI_GROUP := "friendly_auto_default"

static func can_open_menu(board: HexBoard, tile: Vector2i, faction: String) -> bool:
	if not board.query_is_valid_hex(tile):
		return false
	if board.query_unit_at(tile) != -1:
		return false
	var point := board.query_capture_point_at(tile)
	if point.is_empty():
		return false
	var owner := str(point.get("owner", "neutral")).strip_edges().to_lower()
	return owner == faction

static func list_production_options(board: HexBoard, faction: String, tile: Vector2i) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if not can_open_menu(board, tile, faction):
		return items
	var mp := board.query_faction_mp(faction)
	for unit_class in board.get_unit_catalog_classes():
		var entry := board.get_unit_catalog_entry(unit_class)
		if entry.is_empty():
			continue
		var cost := maxi(0, int(entry.get(UnitState.COST, 0)))
		var unit_name := str(entry.get(UnitState.NAME, unit_class.capitalize()))
		items.append({
			"action": "produce:%s" % unit_class,
			"label": "生産: %s (MP %d)" % [unit_name, cost],
			"unit_class": unit_class,
			"unit_name": unit_name,
			"cost": cost,
			"disabled": mp < cost
		})
	return items

static func request_menu(board: HexBoard, tile: Vector2i, faction: String) -> bool:
	if not can_open_menu(board, tile, faction):
		return false
	if not board.unit_action_menu_handler.is_valid():
		return false
	var items := list_production_options(board, faction, tile)
	if items.is_empty():
		board.cmd_update_status("生産可能なユニット定義がありません。")
		return false
	board.pending_production_tile = tile
	board.unit_action_menu_handler.call({
		"menu_type": "production",
		"tile": tile,
		"faction": faction,
		"items": items
	})
	board.cmd_update_status("生産するユニットを選択してください。")
	return true

static func try_produce_on_pending_tile(board: HexBoard, unit_class: String, faction: String) -> bool:
	var class_key := unit_class.strip_edges().to_lower()
	if class_key == "":
		return false
	if not can_open_menu(board, board.pending_production_tile, faction):
		board.cmd_update_status("この拠点では生産できません。")
		board.pending_production_tile = Vector2i(-1, -1)
		return false
	if not board.unit_catalog.has(class_key):
		board.cmd_update_status("未定義の兵科は生産できません。")
		return false
	var entry_variant: Variant = board.unit_catalog.get(class_key, {})
	if not (entry_variant is Dictionary):
		return false
	var template := (entry_variant as Dictionary).duplicate(true)
	var cost := maxi(0, int(template.get(UnitState.COST, 0)))
	var mp := board.query_faction_mp(faction)
	if mp < cost:
		board.cmd_update_status("MP不足で生産できません。必要: %d / 現在: %d" % [cost, mp])
		return false
	var unit_id := _next_production_unit_id(board, faction, class_key)
	template[UnitState.ID] = unit_id
	template[UnitState.UNIT_CLASS] = class_key
	template[UnitState.FACTION] = faction
	template[UnitState.POS] = board.pending_production_tile
	if str(template.get(UnitState.NAME, "")).strip_edges() == "":
		template[UnitState.NAME] = class_key.capitalize()
	template[UnitState.MOVED] = true
	template[UnitState.ATTACKED] = true
	if str(template.get(UnitState.AI_GROUP, "")).strip_edges() == "":
		template[UnitState.AI_GROUP] = DEFAULT_AI_GROUP
	if str(template.get(UnitState.FRIENDLY_AUTO_AI_GROUP, "")).strip_edges() == "":
		template[UnitState.FRIENDLY_AUTO_AI_GROUP] = DEFAULT_FRIENDLY_AUTO_AI_GROUP
	board.units.append(template)
	board.faction_mp[faction] = mp - cost
	board.pending_production_tile = Vector2i(-1, -1)
	board._rebuild_unit_occupancy()
	BoardVisibilityService.recompute_visibility_on_board(board)
	board.cmd_update_turn_label()
	board.cmd_update_status("%s を生産しました。MP -%d (残り %d)" % [
		str(template.get(UnitState.NAME, class_key)),
		cost,
		int(board.faction_mp.get(faction, 0))
	])
	board.queue_redraw()
	return true

static func request_ai_production_turn(board: HexBoard, faction: String) -> Dictionary:
	var options := collect_ai_candidates(board, faction)
	if options.is_empty():
		return {"produced": false, "reason": "no_candidates"}
	var candidate_variant: Variant = options[0]
	if not (candidate_variant is Dictionary):
		return {"produced": false, "reason": "invalid_candidate"}
	var candidate := candidate_variant as Dictionary
	var tile_variant: Variant = candidate.get("tile", Vector2i(-1, -1))
	var tile := tile_variant as Vector2i if tile_variant is Vector2i else Vector2i(-1, -1)
	var unit_class := str(candidate.get("unit_class", ""))
	board.pending_production_tile = tile
	var produced := try_produce_on_pending_tile(board, unit_class, faction)
	return {"produced": produced, "tile": tile, "unit_class": unit_class}

static func collect_ai_candidates(board: HexBoard, faction: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var affordable_classes: Array[String] = []
	var mp := board.query_faction_mp(faction)
	for unit_class in board.get_unit_catalog_classes():
		var entry := board.get_unit_catalog_entry(unit_class)
		if entry.is_empty():
			continue
		var cost := maxi(0, int(entry.get(UnitState.COST, 0)))
		if mp >= cost:
			affordable_classes.append(unit_class)
	if affordable_classes.is_empty():
		return result
	var capture_points := board.query_capture_points()
	for point in capture_points:
		if not (point is Dictionary):
			continue
		var tile_variant: Variant = (point as Dictionary).get("tile", Vector2i(-1, -1))
		if not (tile_variant is Vector2i):
			continue
		var tile := tile_variant as Vector2i
		if not can_open_menu(board, tile, faction):
			continue
		for unit_class in affordable_classes:
			result.append({
				"tile": tile,
				"unit_class": unit_class
			})
	return result

static func _next_production_unit_id(board: HexBoard, faction: String, unit_class: String) -> String:
	var base := "%s_%s" % [faction.strip_edges().to_lower(), unit_class.strip_edges().to_lower()]
	var candidate := "%s_1" % base
	var suffix := 1
	while board._unit_index_by_id(candidate) != -1:
		suffix += 1
		candidate = "%s_%d" % [base, suffix]
	return candidate
