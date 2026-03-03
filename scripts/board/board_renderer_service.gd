class_name BoardRendererService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const FACTION_COLORS := {
	"player": Color(0.95, 0.45, 0.20),
	"enemy": Color(0.20, 0.70, 0.95)
}
const TERRAIN_COLORS := {
	"plain": Color(0.647, 0.796, 0.310),
	"basin": Color(0.404, 0.251, 0.102),
	"forest": Color(0.078, 0.651, 0.224),
	"hill": Color(0.788, 0.463, 0.137),
	"peak": Color(0.541, 0.016, 0.286),
	"water": Color(0.047, 0.290, 0.725),
	"abyss": Color(0.051, 0.051, 0.090)
}
const EXHAUSTED_COLOR := Color(0.45, 0.45, 0.45)
const GRID_STROKE_COLOR := Color(0.24, 0.24, 0.30, 0.10)
const GRID_STROKE_WIDTH := 1.0
const HOVER_STROKE_COLOR := Color(0.55, 0.65, 0.90, 0.32)
const HOVER_STROKE_WIDTH := 2.0
const TRANSPORT_GOAL_STROKE_COLOR := Color(0.95, 0.85, 0.25, 0.95)
const TRANSPORT_GOAL_FILL_COLOR := Color(0.95, 0.85, 0.25, 0.28)
const TRANSPORT_GOAL_STROKE_WIDTH := 2.6
const CAPTURE_NEUTRAL_COLOR := Color(0.92, 0.84, 0.36, 0.90)
const CAPTURE_PLAYER_COLOR := Color(0.95, 0.45, 0.20, 0.92)
const CAPTURE_ENEMY_COLOR := Color(0.20, 0.70, 0.95, 0.92)
const CAPTURE_RANGE_FILL_ALPHA := 0.10
const CAPTURE_RANGE_STROKE_ALPHA := 0.28
const TERRAIN_FILL_ALPHA_BASE := 0.20
const TERRAIN_FILL_ALPHA_REACHABLE := 0.26
const TERRAIN_FILL_ALPHA_ATTACKABLE := 0.30
const TERRAIN_FILL_ALPHA_HOVER := 0.36
const FOG_FILL_COLOR := Color(0.01, 0.01, 0.02, 0.95)
const FOG_STROKE_COLOR := Color(0.10, 0.10, 0.14, 0.28)
const FOG_DIM_FILL_COLOR := Color(0.02, 0.02, 0.03, 0.42)
const FOG_DIM_STROKE_COLOR := Color(0.12, 0.12, 0.16, 0.20)

static func draw(board: HexBoard) -> void:
	var reachable_tiles := _selected_reachable_tiles(board)
	var attackable_tiles := _selected_attackable_tiles(board)
	for r in board.rows:
		for q in board.cols:
			var tile = Vector2i(q, r)
			var is_explored := board.query_is_tile_explored_to_player(tile)
			if not is_explored:
				_draw_hex(board, q, r, FOG_FILL_COLOR, FOG_STROKE_COLOR, GRID_STROKE_WIDTH)
				continue
			var is_visible := board.query_is_tile_visible_to_player(tile)
			var terrain := board.query_terrain_type(tile)
			var base_color: Color = board.query_terrain_base_color(terrain)
			var alpha = TERRAIN_FILL_ALPHA_BASE
			if reachable_tiles.has(tile):
				alpha = maxf(alpha, TERRAIN_FILL_ALPHA_REACHABLE)
			if attackable_tiles.has(tile):
				alpha = maxf(alpha, TERRAIN_FILL_ALPHA_ATTACKABLE)
			if tile == board.hovered_tile:
				alpha = maxf(alpha, TERRAIN_FILL_ALPHA_HOVER)
			var fill_color = Color(base_color.r, base_color.g, base_color.b, alpha)
			_draw_hex(board, q, r, fill_color, GRID_STROKE_COLOR, GRID_STROKE_WIDTH)
			if not is_visible:
				_draw_hex(board, q, r, FOG_DIM_FILL_COLOR, FOG_DIM_STROKE_COLOR, GRID_STROKE_WIDTH)
	if board.transport_goal_enabled and board.query_is_valid_hex(board.transport_goal_tile) and board.query_is_tile_visible_to_player(board.transport_goal_tile):
		_draw_hex(
			board,
			board.transport_goal_tile.x,
			board.transport_goal_tile.y,
			TRANSPORT_GOAL_FILL_COLOR,
			TRANSPORT_GOAL_STROKE_COLOR,
			TRANSPORT_GOAL_STROKE_WIDTH
		)
	_draw_capture_points(board)
	_draw_hovered_capture_heal_range(board)
	if board.query_is_valid_hex(board.hovered_tile) and board.query_is_tile_visible_to_player(board.hovered_tile):
		_draw_hex(board, board.hovered_tile.x, board.hovered_tile.y, Color(0.0, 0.0, 0.0, 0.0), HOVER_STROKE_COLOR, HOVER_STROKE_WIDTH)
	_draw_tile_outlines(board, reachable_tiles, Color(0.5, 0.8, 0.5), 2.0)
	_draw_tile_outlines(board, attackable_tiles, Color(0.92, 0.45, 0.45), 2.0)
	_draw_units(board)

static func _selected_reachable_tiles(board: HexBoard) -> Dictionary:
	var result = {}
	if board.query_unit_action_mode() != "move":
		return result
	if board.selected_unit_idx < 0 or board.selected_unit_idx >= board.units.size():
		return result
	var unit: Dictionary = board.units[board.selected_unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != board.current_faction:
		return result
	if bool(unit.get(UnitState.MOVED, false)):
		return result
	var reachable := board.query_reachable_costs(board.selected_unit_idx)
	for target in reachable.keys():
		if not (target is Vector2i):
			continue
		var target_tile := board.query_to_vec2i(target)
		result[target_tile] = true
	return result

static func _selected_attackable_tiles(board: HexBoard) -> Dictionary:
	var result = {}
	if board.query_unit_action_mode() != "attack":
		return result
	if board.selected_unit_idx < 0 or board.selected_unit_idx >= board.units.size():
		return result
	var unit: Dictionary = board.units[board.selected_unit_idx]
	if str(unit.get(UnitState.FACTION, "")) != board.current_faction:
		return result
	if bool(unit.get(UnitState.ATTACKED, false)):
		return result
	if not board.query_unit_can_attack(unit):
		return result
	var min_range := board.query_unit_min_range(unit)
	var max_range := board.query_unit_max_range(unit)
	var start := board.query_to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	for r in board.rows:
		for q in board.cols:
			var target := Vector2i(q, r)
			var target_idx := board.query_unit_at(target)
			var has_enemy := target_idx != -1 and str(board.units[target_idx].get(UnitState.FACTION, "")) != board.current_faction
			if not has_enemy:
				continue
			if not board.query_is_unit_visible_to_player(target_idx):
				continue
			var enemy_center := board.query_to_vec2i(board.units[target_idx].get(UnitState.POS, Vector2i.ZERO))
			var distance := board.query_hex_distance(start, enemy_center)
			if distance >= min_range and distance <= max_range:
				result[target] = true
	return result

static func _draw_hex(board: HexBoard, q: int, r: int, fill_color: Color, stroke_color: Color, stroke_width: float) -> void:
	var center = board.map_to_local(Vector2i(q, r))
	var points = _hex_outline_points(board, center)
	if fill_color.a > 0.0:
		board.draw_colored_polygon(points, fill_color)
	for i in points.size():
		board.draw_line(points[i], points[(i + 1) % points.size()], stroke_color, stroke_width)

static func _draw_units(board: HexBoard) -> void:
	for idx in board.units.size():
		var unit: Dictionary = board.units[idx]
		if str(unit.get(UnitState.FACTION, "")) != "player":
			if not board.query_is_unit_visible_to_player(idx):
				continue
		var faction_color: Color = FACTION_COLORS.get(unit[UnitState.FACTION], Color.WHITE) as Color
		var is_current_faction := str(unit.get(UnitState.FACTION, "")) == str(board.current_faction)
		var moved := bool(unit.get(UnitState.MOVED, false))
		var attacked := bool(unit.get(UnitState.ATTACKED, false))
		var can_attack := board.query_unit_can_attack(unit)
		var is_exhausted := is_current_faction and ((can_attack and moved and attacked) or ((not can_attack) and moved))
		var icon_modulate := EXHAUSTED_COLOR if is_exhausted else Color.WHITE
		var center_tile := board.query_to_vec2i(unit[UnitState.POS])
		if not board.query_is_valid_hex(center_tile):
			continue
		var center := board.query_unit_draw_position(unit)
		var radius = board.hex_size * 0.4
		var icon := board.query_unit_icon_texture(unit)
		if icon != null:
			var size: Vector2 = Vector2.ONE * radius * 2.0
			var rect: Rect2 = Rect2(center - size * 0.5, size)
			board.draw_texture_rect(icon, rect, false, icon_modulate)
			board.draw_arc(center, radius + 2.0, 0.0, TAU, 20, faction_color, 1.8)
		else:
			var color := faction_color
			if is_exhausted:
				color = EXHAUSTED_COLOR
			board.draw_circle(center, radius, color)
		if idx == board.selected_unit_idx:
			board.draw_arc(center, radius + 5.0, 0.0, TAU, 20, Color.WHITE, 2.0)

static func _draw_tile_outlines(board: HexBoard, tiles: Dictionary, color: Color, stroke_width: float) -> void:
	for tile_key in tiles.keys():
		if not (tile_key is Vector2i):
			continue
		var tile := tile_key as Vector2i
		_draw_hex(board, tile.x, tile.y, Color(0.0, 0.0, 0.0, 0.0), color, stroke_width)

static func _draw_capture_points(board: HexBoard) -> void:
	var points := board.query_capture_points()
	for point in points:
		if not (point is Dictionary):
			continue
		var entry := point as Dictionary
		var tile := board.query_to_vec2i(entry.get("tile", Vector2i(-1, -1)))
		if not board.query_is_valid_hex(tile):
			continue
		if not board.query_is_tile_visible_to_player(tile):
			continue
		var owner := str(entry.get("owner", "neutral")).strip_edges().to_lower()
		var color := CAPTURE_NEUTRAL_COLOR
		if owner == "player":
			color = CAPTURE_PLAYER_COLOR
		elif owner == "enemy":
			color = CAPTURE_ENEMY_COLOR
		var center := board.map_to_local(tile)
		var radius := board.hex_size * 0.18
		board.draw_circle(center, radius, Color(color.r, color.g, color.b, color.a * 0.28))
		board.draw_arc(center, radius + 2.0, 0.0, TAU, 18, color, 2.0)

static func _draw_hovered_capture_heal_range(board: HexBoard) -> void:
	var hover := board.hovered_tile
	if not board.query_is_valid_hex(hover):
		return
	if not board.query_is_tile_visible_to_player(hover):
		return
	var capture_point := board.query_capture_point_at(hover)
	if capture_point.is_empty():
		return
	var owner := str(capture_point.get("owner", "neutral")).strip_edges().to_lower()
	var color := CAPTURE_NEUTRAL_COLOR
	if owner == "player":
		color = CAPTURE_PLAYER_COLOR
	elif owner == "enemy":
		color = CAPTURE_ENEMY_COLOR
	var heal_range := maxi(0, board.query_turn_start_heal_base_range())
	for r in board.rows:
		for q in board.cols:
			var tile := Vector2i(q, r)
			if board.query_hex_distance(hover, tile) > heal_range:
				continue
			if not board.query_is_tile_explored_to_player(tile):
				continue
			var fill_alpha := CAPTURE_RANGE_FILL_ALPHA
			var stroke_alpha := CAPTURE_RANGE_STROKE_ALPHA
			if tile == hover:
				fill_alpha = CAPTURE_RANGE_FILL_ALPHA * 1.5
				stroke_alpha = CAPTURE_RANGE_STROKE_ALPHA * 1.3
			_draw_hex(
				board,
				tile.x,
				tile.y,
				Color(color.r, color.g, color.b, fill_alpha),
				Color(color.r, color.g, color.b, stroke_alpha),
				1.6
			)

static func _hex_outline_points(board: HexBoard, center: Vector2) -> PackedVector2Array:
	var half_w = float(board.tile_width) * 0.5
	var half_h = float(board.tile_height) * 0.5
	var side = float(board.hex_side_length)
	if side <= 0.0:
		side = half_h
	side = clampf(side, 0.0, float(board.tile_height))
	var half_side = side * 0.5
	return PackedVector2Array([
		center + Vector2(0.0, -half_h),
		center + Vector2(half_w, -half_side),
		center + Vector2(half_w, half_side),
		center + Vector2(0.0, half_h),
		center + Vector2(-half_w, half_side),
		center + Vector2(-half_w, -half_side)
	])
