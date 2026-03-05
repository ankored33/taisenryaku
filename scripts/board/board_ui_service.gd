class_name BoardUIService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

static func update_status(board: HexBoard, text: String) -> void:
	if board.status_label != null:
		board.status_label.text = text

static func update_turn_label(board: HexBoard) -> void:
	if board.turn_label != null:
		board.turn_label.text = board.query_turn_text()

static func update_unit_info(board: HexBoard, unit: Dictionary) -> void:
	if board.unit_info_label == null:
		return
	var min_range := board.query_unit_min_range(unit)
	var max_range := board.query_unit_max_range(unit)
	var range_text := str(max_range) if min_range == max_range else "%d-%d" % [min_range, max_range]
	board.unit_info_label.text = "名前: %s\n陣営: %s\n兵科: %s\nコスト: %d\nHP: %d\n攻撃: %d\n移動: %d\n射程: %s" % [
		str(unit.get(UnitState.NAME, "?")),
		str(unit.get(UnitState.FACTION, "?")).to_upper(),
		str(unit.get(UnitState.UNIT_CLASS, "?")),
		int(unit.get(UnitState.COST, 0)),
		int(unit.get(UnitState.HP, 0)),
		int(unit.get(UnitState.ATK, 0)),
		int(unit.get(UnitState.MOVE, 0)),
		range_text
	]
	board.unit_info_label.text += "\n移動済み: %s | 攻撃済み: %s" % [
		"はい" if bool(unit.get(UnitState.MOVED, false)) else "いいえ",
		"はい" if bool(unit.get(UnitState.ATTACKED, false)) else "いいえ"
	]

static func clear_unit_info(board: HexBoard) -> void:
	if board.unit_info_label != null:
		board.unit_info_label.text = "ユニット未選択"

static func update_tile_info(board: HexBoard, tile: Vector2i) -> void:
	if board.tile_info_label == null:
		return
	var terrain := board.query_terrain_type(tile)
	var move_text := "通行不可" if board.query_is_terrain_impassable(terrain) else str(board.query_movement_cost_for_tile(tile))
	var effect_text := _terrain_effect_text(terrain)
	var text := "カーソル: (%d, %d)\n地形: %s\n移動コスト: %s\n地形効果: %s" % [
		tile.x,
		tile.y,
		terrain,
		move_text,
		effect_text
	]
	var capture_point := board.query_capture_point_at(tile)
	if not capture_point.is_empty():
		var base_name := str(capture_point.get("name", "")).strip_edges()
		if base_name == "":
			base_name = "拠点 (%d,%d)" % [tile.x, tile.y]
		var owner := str(capture_point.get("owner", "neutral")).strip_edges().to_lower()
		var owner_text := "中立"
		if owner == "player":
			owner_text = "PLAYER"
		elif owner == "enemy":
			owner_text = "ENEMY"
		var income := int(capture_point.get("income", 0))
		text += "\n---\n拠点名: %s\n収入: %d\n所有: %s\n回復範囲: %dマス" % [
			base_name,
			income,
			owner_text,
			board.query_turn_start_heal_base_range()
		]
	board.tile_info_label.text = text

static func _terrain_effect_text(terrain: String) -> String:
	var key := terrain.strip_edges().to_lower()
	var effects: Array[String] = []
	if key == "forest":
		effects.append("防御+1 / 索敵-1")
	elif key == "hill":
		effects.append("視界+1 / 高所攻撃+1")
	elif key == "peak":
		effects.append("視界+2 / 高所攻撃+2")
	elif key == "basin":
		effects.append("防御-1(被ダメ増)")
	if effects.is_empty():
		return "なし"
	return ", ".join(effects)

static func clear_tile_info(board: HexBoard) -> void:
	if board.tile_info_label == null:
		return
	board.tile_info_label.text = "カーソル: -\n地形: -\n移動コスト: -"

static func update_hover_tile_info(board: HexBoard) -> void:
	var tile := board.local_to_map(board.get_local_mouse_position())
	if board.query_is_valid_hex(tile):
		if board.hovered_tile != tile:
			board.hovered_tile = tile
			board.queue_redraw()
		update_tile_info(board, tile)
	else:
		if board.query_is_valid_hex(board.hovered_tile):
			board.hovered_tile = Vector2i(-1, -1)
			board.queue_redraw()
		clear_tile_info(board)

static func selected_text(board: HexBoard, unit: Dictionary) -> String:
	var min_range := board.query_unit_min_range(unit)
	var max_range := board.query_unit_max_range(unit)
	var range_text := str(max_range) if min_range == max_range else "%d-%d" % [min_range, max_range]
	return "選択中 %s | コスト %d | HP %d | 攻撃 %d | 移動 %d | 射程 %s" % [
		unit.get(UnitState.NAME, "?"),
		int(unit.get(UnitState.COST, 0)),
		int(unit.get(UnitState.HP, 0)),
		int(unit.get(UnitState.ATK, 0)),
		int(unit.get(UnitState.MOVE, 0)),
		range_text
	]
