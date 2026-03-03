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
	for faction_key in board.visible_tiles_by_faction.keys():
		var faction := str(faction_key).strip_edges().to_lower()
		if faction == "":
			continue
		var visible_for_faction: Variant = board.visible_tiles_by_faction.get(faction_key, {})
		if not (visible_for_faction is Dictionary):
			continue
		var visible_dict: Dictionary = visible_for_faction as Dictionary
		if not board.explored_tiles_by_faction.has(faction):
			board.explored_tiles_by_faction[faction] = {}
		var explored_variant: Variant = board.explored_tiles_by_faction.get(faction, {})
		if not (explored_variant is Dictionary):
			board.explored_tiles_by_faction[faction] = {}
			explored_variant = board.explored_tiles_by_faction[faction]
		var explored := explored_variant as Dictionary
		for tile in visible_dict.keys():
			explored[tile] = true

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
	if is_tile_visible_for_faction(board, tile, faction):
		return true
	var key := faction.strip_edges().to_lower()
	if not board.explored_tiles_by_faction.has(key):
		return false
	var explored_variant: Variant = board.explored_tiles_by_faction.get(key, {})
	if not (explored_variant is Dictionary):
		return false
	return (explored_variant as Dictionary).has(tile)

static func explored_tile_count_for_faction(board: HexBoard, faction: String) -> int:
	var key := faction.strip_edges().to_lower()
	if key == "":
		return 0
	if not board.explored_tiles_by_faction.has(key):
		return 0
	var explored_variant: Variant = board.explored_tiles_by_faction.get(key, {})
	if not (explored_variant is Dictionary):
		return 0
	return (explored_variant as Dictionary).size()

static func is_tile_explored_to_player(board: HexBoard, tile: Vector2i) -> bool:
	if board.debug_reveal_all:
		return true
	return is_tile_explored_for_faction(board, tile, FOG_VIEWER_FACTION)

static func is_unit_visible_to_player(board: HexBoard, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= board.units.size():
		return false
	var tile := board.query_to_vec2i(board.units[unit_idx].get(UnitState.POS, Vector2i(-1, -1)))
	return is_tile_visible_to_player(board, tile)
