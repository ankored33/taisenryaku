class_name BoardVisibilityService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const HexGridService = preload("res://scripts/board/hex_grid_service.gd")
const FOG_VIEWER_FACTION := "player"

static func recompute_visibility(board: HexBoard, units: Array[Dictionary], fog_viewer_faction: String) -> Dictionary:
	var visibility_by_faction := {}
	var factions := {}
	for unit in units:
		var faction := UnitState.faction(unit)
		if faction == "":
			continue
		factions[faction] = true
	for key in factions.keys():
		var faction := str(key)
		visibility_by_faction[faction] = compute_visible_tiles_for_faction(board, units, faction)
	if not visibility_by_faction.has(fog_viewer_faction):
		visibility_by_faction[fog_viewer_faction] = {}
	return visibility_by_faction

static func compute_visible_tiles_for_faction(board: HexBoard, units: Array[Dictionary], faction: String) -> Dictionary:
	var visible := {}
	for unit in units:
		if UnitState.faction(unit) != faction:
			continue
		var origin := board.query_to_vec2i(UnitState.pos(unit))
		if not board.query_is_valid_hex(origin):
			continue
		visible[origin] = true
		var vision := board.query_unit_vision(unit)
		if vision <= 0:
			continue
		var visited := {origin: true}
		var frontier: Array[Vector2i] = [origin]
		for _step in vision:
			if frontier.is_empty():
				break
			var next_frontier: Array[Vector2i] = []
			for tile in frontier:
				for neighbor in HexGridService.hex_neighbors(tile, board.cols, board.rows, board.stagger_axis, board.stagger_index):
					if visited.has(neighbor):
						continue
					visited[neighbor] = true
					visible[neighbor] = true
					next_frontier.append(neighbor)
			frontier = next_frontier
	return visible

static func recompute_visibility_on_board(board: HexBoard) -> void:
	board.visible_tiles_by_faction = recompute_visibility(board, board.units, FOG_VIEWER_FACTION)

static func visible_tiles_for_faction(board: HexBoard, faction: String) -> Dictionary:
	var key := faction.strip_edges().to_lower()
	if board.visible_tiles_by_faction.has(key):
		var found: Variant = board.visible_tiles_by_faction.get(key, {})
		if found is Dictionary:
			return found as Dictionary
	return {}

static func is_tile_visible_for_faction(board: HexBoard, tile: Vector2i, faction: String) -> bool:
	if not board.query_is_valid_hex(tile):
		return false
	return visible_tiles_for_faction(board, faction).has(tile)

static func is_tile_visible_to_player(board: HexBoard, tile: Vector2i) -> bool:
	if board.debug_reveal_all:
		return true
	return is_tile_visible_for_faction(board, tile, FOG_VIEWER_FACTION)

static func is_tile_explored_for_faction(board: HexBoard, tile: Vector2i, faction: String) -> bool:
	if not board.query_is_valid_hex(tile):
		return false
	return true

static func explored_tile_count_for_faction(board: HexBoard, faction: String) -> int:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return 0
	return maxi(0, int(board.cols) * int(board.rows))

static func is_tile_explored_to_player(board: HexBoard, tile: Vector2i) -> bool:
	if board.debug_reveal_all:
		return true
	return is_tile_explored_for_faction(board, tile, FOG_VIEWER_FACTION)

static func is_unit_visible_to_player(board: HexBoard, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return false
	var tile := board.query_to_vec2i(board.units[unit_idx].get(UnitState.POS, Vector2i(-1, -1)))
	return is_tile_visible_to_player(board, tile)
