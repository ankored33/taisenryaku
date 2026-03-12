class_name BoardCaptureService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

static func apply_capture_points_from_stage(board: HexBoard, stage_data: Dictionary) -> void:
	board.capture_points.clear()
	board.capture_allowed_unit_classes = ["infantry"]
	var rules_variant: Variant = stage_data.get("capture_rules", {})
	if rules_variant is Dictionary:
		var rules := rules_variant as Dictionary
		var classes_variant: Variant = rules.get("capture_unit_classes", [])
		if classes_variant is Array and not (classes_variant as Array).is_empty():
			board.capture_allowed_unit_classes.clear()
			for raw in classes_variant:
				var name := str(raw).strip_edges().to_lower()
				if name != "":
					board.capture_allowed_unit_classes.append(name)
	var points_variant: Variant = stage_data.get("capture_points", [])
	if points_variant is Array:
		for item in points_variant:
			if not (item is Dictionary):
				continue
			var point := item as Dictionary
			var tile := Vector2i(-1, -1)
			if point.has("tile"):
				tile = board.query_to_vec2i(point.get("tile", Vector2i(-1, -1)))
			elif point.has("x") and point.has("y"):
				tile = board.local_to_map(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))))
			if not board.query_is_valid_hex(tile):
				continue
			var owner := str(point.get("owner", "neutral")).strip_edges().to_lower()
			if owner != "player" and owner != "enemy":
				owner = "neutral"
			var base_name := str(point.get("name", "")).strip_edges()
			var income := int(point.get("income", 0))
			board.capture_points[tile] = {
				"owner": owner,
				"name": base_name,
				"income": income
			}
	board.queue_redraw()

static func capture_point_at(board: HexBoard, tile: Vector2i) -> Dictionary:
	var point_variant: Variant = board.capture_points.get(tile, {})
	if point_variant is Dictionary:
		return (point_variant as Dictionary).duplicate(true)
	return {}

static func capture_owner_at(board: HexBoard, tile: Vector2i) -> String:
	var point_variant: Variant = board.capture_points.get(tile, {})
	if not (point_variant is Dictionary):
		return "neutral"
	var point := point_variant as Dictionary
	var owner := str(point.get("owner", "neutral")).strip_edges().to_lower()
	if owner == "player" or owner == "enemy":
		return owner
	return "neutral"

static func is_unit_capture_capable(board: HexBoard, unit: Dictionary) -> bool:
	if bool(unit.get("can_capture", false)):
		return true
	var unit_class := str(unit.get(UnitState.UNIT_CLASS, "")).strip_edges().to_lower()
	for allowed in board.capture_allowed_unit_classes:
		if unit_class == allowed:
			return true
	return false

static func can_unit_capture_on_current_tile(board: HexBoard, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return false
	var unit := board.units[unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != board.current_faction:
		return false
	if not is_unit_capture_capable(board, unit):
		return false
	var tile := board.query_to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	if not board.capture_points.has(tile):
		return false
	var owner := capture_owner_at(board, tile)
	return owner != board.current_faction

static func try_execute_capture(board: HexBoard, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return false
	var unit := board.units[unit_idx]
	var unit_name := str(unit.get(UnitState.NAME, "?"))
	if str(unit.get(UnitState.FACTION, "")) != board.current_faction:
		board.cmd_update_status("このユニットでは占領できません。")
		board.cmd_update_unit_info(unit)
		return false
	if bool(unit.get(UnitState.ATTACKED, false)):
		board.cmd_update_status("%s はこのターンすでに行動済みのため占領できません。" % unit_name)
		board.cmd_update_unit_info(unit)
		return false
	if not is_unit_capture_capable(board, unit):
		board.cmd_update_status("%s は占領できない兵科です。" % unit_name)
		board.cmd_update_unit_info(unit)
		return false
	var tile := board.query_to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	if not board.capture_points.has(tile):
		board.cmd_update_status("占領対象の拠点タイル上にいません。")
		board.cmd_update_unit_info(unit)
		return false
	var owner := capture_owner_at(board, tile)
	if owner == board.current_faction:
		board.cmd_update_status("この拠点はすでに%sが占領しています。" % board.current_faction.to_upper())
		board.cmd_update_unit_info(unit)
		return false
	var current_point := capture_point_at(board, tile)
	current_point["owner"] = board.current_faction
	board.capture_points[tile] = current_point
	board.units[unit_idx][UnitState.MOVED] = true
	board.units[unit_idx][UnitState.ATTACKED] = true
	board.action_sequence += 1
	board.cmd_clear_pending_attack()
	board.cmd_clear_pending_move_confirmation()
	board.cmd_update_status("%s が拠点 (%d,%d) を占領しました。" % [unit_name, tile.x, tile.y])
	board.cmd_update_unit_info(board.units[unit_idx])
	if not has_owned_capture_point(board, "player"):
		board.cmd_update_status("味方拠点がすべて制圧されたため敗北しました。")
		board.cmd_trigger_defeat("all_player_bases_lost")
	return true

static func is_within_owned_capture_point_range(
	board: HexBoard,
	unit_tile: Vector2i,
	faction: String,
	max_distance: int
) -> bool:
	for key in board.capture_points.keys():
		if not (key is Vector2i):
			continue
		var base_tile := key as Vector2i
		if capture_owner_at(board, base_tile) != faction:
			continue
		if board.query_hex_distance(unit_tile, base_tile) <= max_distance:
			return true
	return false

static func has_owned_capture_point(board: HexBoard, faction: String) -> bool:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return false
	for tile in board.capture_points.keys():
		if not (tile is Vector2i):
			continue
		if capture_owner_at(board, tile as Vector2i) == key:
			return true
	return false
