class_name BoardAIService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

static func _profile_num(profile: Dictionary, key: String, default_value: float) -> float:
	if profile.has(key):
		return float(profile.get(key, default_value))
	return default_value

static func score_attack(
	attacker_idx: int,
	defender_idx: int,
	distance: int,
	units: Array,
	can_unit_attack_at_range: Callable,
	ai_profile: Dictionary = {}
) -> float:
	var attacker: Dictionary = units[attacker_idx]
	var defender: Dictionary = units[defender_idx]
	var atk := int(attacker.get(UnitState.ATK, 0))
	var defender_hp := int(defender.get(UnitState.HP, 0))
	var attack_bias := _profile_num(ai_profile, "attack_bias", 1.0)
	var kill_bonus_scale := _profile_num(ai_profile, "kill_bonus_scale", 1.0)
	var counter_threat_weight := _profile_num(ai_profile, "counter_threat_weight", 1.0)
	var defender_hp_weight := _profile_num(ai_profile, "defender_hp_weight", 1.0)
	var score := float(atk * 10.0 * attack_bias)
	if atk >= defender_hp:
		score += 100.0 * kill_bonus_scale
	if bool(can_unit_attack_at_range.call(defender, distance)):
		score -= float(int(defender.get(UnitState.ATK, 0)) * 4.0 * counter_threat_weight)
	score -= float(defender_hp) * defender_hp_weight
	return score

static func best_attack_from_position(
	attacker_idx: int,
	from_pos: Vector2i,
	units: Array,
	unit_can_attack: Callable,
	can_unit_attack_at_range: Callable,
	get_enemy_indices: Callable,
	hex_distance: Callable,
	ai_profile: Dictionary = {}
) -> Dictionary:
	if attacker_idx < 0 or attacker_idx >= units.size():
		return {"target_idx": -1}
	var attacker: Dictionary = units[attacker_idx]
	if not bool(unit_can_attack.call(attacker)):
		return {"target_idx": -1}
	var enemies: Array = get_enemy_indices.call(str(attacker.get(UnitState.FACTION, "")))
	var best_target_idx := -1
	var best_score := -INF
	var best_distance := -1
	for enemy_idx in enemies:
		var enemy_pos: Vector2i = units[enemy_idx].get(UnitState.POS, Vector2i.ZERO)
		var distance := int(hex_distance.call(from_pos, enemy_pos))
		if not bool(can_unit_attack_at_range.call(attacker, distance)):
			continue
		var score := score_attack(attacker_idx, enemy_idx, distance, units, can_unit_attack_at_range, ai_profile)
		if score > best_score:
			best_score = score
			best_target_idx = enemy_idx
			best_distance = distance
	return {"target_idx": best_target_idx, "score": best_score, "distance": best_distance}

static func evaluate_ai_tile(
	unit_idx: int,
	tile: Vector2i,
	units: Array,
	unit_can_attack: Callable,
	can_unit_attack_at_range: Callable,
	get_enemy_indices: Callable,
	hex_distance: Callable,
	ai_profile: Dictionary = {}
) -> float:
	var best_attack := best_attack_from_position(
		unit_idx,
		tile,
		units,
		unit_can_attack,
		can_unit_attack_at_range,
		get_enemy_indices,
		hex_distance,
		ai_profile
	)
	var attack_opportunity_bonus := _profile_num(ai_profile, "attack_opportunity_bonus", 1000.0)
	var approach_weight := _profile_num(ai_profile, "approach_weight", 1.0)
	var move_distance_weight := _profile_num(ai_profile, "move_distance_weight", 0.0)
	var from_pos: Vector2i = units[unit_idx].get(UnitState.POS, Vector2i.ZERO)
	var moved_distance := float(int(hex_distance.call(from_pos, tile)))
	if int(best_attack.get("target_idx", -1)) != -1:
		return float(best_attack.get("score", 0.0)) + attack_opportunity_bonus + moved_distance * move_distance_weight

	var faction := str(units[unit_idx].get(UnitState.FACTION, ""))
	var enemies: Array = get_enemy_indices.call(faction)
	if enemies.is_empty():
		return -1000000.0
	var nearest := INF
	for enemy_idx in enemies:
		var enemy_pos: Vector2i = units[enemy_idx].get(UnitState.POS, Vector2i.ZERO)
		var d := float(hex_distance.call(tile, enemy_pos))
		if d < nearest:
			nearest = d
	return -nearest * approach_weight + moved_distance * move_distance_weight

static func choose_ai_move(
	unit_idx: int,
	units: Array,
	reachable: Dictionary,
	unit_can_attack: Callable,
	can_unit_attack_at_range: Callable,
	get_enemy_indices: Callable,
	hex_distance: Callable,
	ai_profile: Dictionary = {}
) -> Dictionary:
	var unit: Dictionary = units[unit_idx]
	var from_pos: Vector2i = unit.get(UnitState.POS, Vector2i.ZERO)
	var best_tile: Vector2i = from_pos
	var best_score := -INF
	for tile in reachable.keys():
		if not (tile is Vector2i):
			continue
		var target_tile := tile as Vector2i
		var score := evaluate_ai_tile(
			unit_idx,
			target_tile,
			units,
			unit_can_attack,
			can_unit_attack_at_range,
			get_enemy_indices,
			hex_distance,
			ai_profile
		)
		if score > best_score:
			best_score = score
			best_tile = target_tile
	return {"tile": best_tile, "score": best_score}
