class_name HexGridService
extends RefCounted

const CUBE_DIRECTIONS := [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1)
]
const UnitState = preload("res://scripts/board/unit_state.gd")

static func to_vec2i(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO

static func is_valid_hex(tile: Vector2i, cols: int, rows: int) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < cols and tile.y < rows

static func offset_to_cube(tile: Vector2i, stagger_axis: String, stagger_index: String) -> Vector3i:
	var x = 0
	var z = 0
	var use_even = stagger_index == "even"
	if stagger_axis == "x":
		x = tile.x
		if use_even:
			z = tile.y - int((tile.x + (tile.x & 1)) / 2)
		else:
			z = tile.y - int((tile.x - (tile.x & 1)) / 2)
	else:
		z = tile.y
		if use_even:
			x = tile.x - int((tile.y + (tile.y & 1)) / 2)
		else:
			x = tile.x - int((tile.y - (tile.y & 1)) / 2)
	var y = -x - z
	return Vector3i(x, y, z)

static func cube_to_offset(cube: Vector3i, stagger_axis: String, stagger_index: String) -> Vector2i:
	var col = 0
	var row = 0
	var use_even = stagger_index == "even"
	if stagger_axis == "x":
		col = cube.x
		if use_even:
			row = cube.z + int((cube.x + (cube.x & 1)) / 2)
		else:
			row = cube.z + int((cube.x - (cube.x & 1)) / 2)
	else:
		row = cube.z
		if use_even:
			col = cube.x + int((cube.z + (cube.z & 1)) / 2)
		else:
			col = cube.x + int((cube.z - (cube.z & 1)) / 2)
	return Vector2i(col, row)

static func hex_distance(a: Vector2i, b: Vector2i, stagger_axis: String, stagger_index: String) -> int:
	var ac = offset_to_cube(a, stagger_axis, stagger_index)
	var bc = offset_to_cube(b, stagger_axis, stagger_index)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2.0)

static func hex_neighbors(tile: Vector2i, cols: int, rows: int, stagger_axis: String, stagger_index: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cube = offset_to_cube(tile, stagger_axis, stagger_index)
	for dir in CUBE_DIRECTIONS:
		var neighbor = cube_to_offset(cube + dir, stagger_axis, stagger_index)
		if is_valid_hex(neighbor, cols, rows):
			result.append(neighbor)
	return result

static func can_place_unit_at(
	unit_idx: int,
	target_center: Vector2i,
	units: Array,
	unit_occupancy: Dictionary,
	cols: int,
	rows: int,
	is_impassable_tile: Callable
) -> bool:
	return can_stop_unit_at(unit_idx, target_center, units, unit_occupancy, cols, rows, is_impassable_tile)

static func _occupant_idx(unit_occupancy: Dictionary, tile: Vector2i) -> int:
	if not unit_occupancy.has(tile):
		return -1
	return int(unit_occupancy[tile])

static func can_traverse_unit_at(
	unit_idx: int,
	target_center: Vector2i,
	units: Array,
	unit_occupancy: Dictionary,
	cols: int,
	rows: int,
	is_impassable_tile: Callable
) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	if not is_valid_hex(target_center, cols, rows):
		return false
	if bool(is_impassable_tile.call(target_center)):
		return false
	var occ := _occupant_idx(unit_occupancy, target_center)
	if occ == -1 or occ == unit_idx:
		return true
	if occ < 0 or occ >= units.size():
		return false
	var unit_faction := str(units[unit_idx].get(UnitState.FACTION, ""))
	var occ_faction := str(units[occ].get(UnitState.FACTION, ""))
	return unit_faction == occ_faction

static func can_stop_unit_at(
	unit_idx: int,
	target_center: Vector2i,
	units: Array,
	unit_occupancy: Dictionary,
	cols: int,
	rows: int,
	is_impassable_tile: Callable
) -> bool:
	if not can_traverse_unit_at(unit_idx, target_center, units, unit_occupancy, cols, rows, is_impassable_tile):
		return false
	var occ := _occupant_idx(unit_occupancy, target_center)
	if occ != -1 and occ != unit_idx:
		return false
	return true

static func compute_reachable_costs(
	unit_idx: int,
	units: Array,
	unit_occupancy: Dictionary,
	cols: int,
	rows: int,
	stagger_axis: String,
	stagger_index: String,
	movement_cost_for_tile: Callable,
	is_impassable_tile: Callable,
	is_enemy_zoc_tile_for_unit: Callable
) -> Dictionary:
	var reachable_costs := {}
	var traversal_costs := {}
	if unit_idx < 0 or unit_idx >= units.size():
		return reachable_costs
	var unit: Dictionary = units[unit_idx]
	var move_points = int(unit.get(UnitState.MOVE, 0))
	var start = to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
	reachable_costs[start] = 0
	traversal_costs[start] = 0
	var frontier: Array[Vector2i] = [start]
	var cursor = 0
	while cursor < frontier.size():
		var current = frontier[cursor]
		cursor += 1
		if current != start and bool(is_enemy_zoc_tile_for_unit.call(unit_idx, current)):
			continue
		var current_cost = int(traversal_costs.get(current, 0))
		for neighbor in hex_neighbors(current, cols, rows, stagger_axis, stagger_index):
			if not can_traverse_unit_at(unit_idx, neighbor, units, unit_occupancy, cols, rows, is_impassable_tile):
				continue
			var move_cost = int(movement_cost_for_tile.call(neighbor))
			var next_cost = current_cost + move_cost
			if next_cost > move_points:
				continue
			if not traversal_costs.has(neighbor) or next_cost < int(traversal_costs[neighbor]):
				traversal_costs[neighbor] = next_cost
				frontier.append(neighbor)
			if can_stop_unit_at(unit_idx, neighbor, units, unit_occupancy, cols, rows, is_impassable_tile):
				if not reachable_costs.has(neighbor) or next_cost < int(reachable_costs[neighbor]):
					reachable_costs[neighbor] = next_cost
	return reachable_costs
