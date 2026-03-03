class_name UnitDataService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const INVALID_TILE := Vector2i(-9999, -9999)

static func load_units(json_path: String) -> Dictionary:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "ユニットデータの読み込みに失敗しました。"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "ユニットデータ形式が不正です。"}
	var root: Dictionary = parsed

	var unit_catalog := {}
	var units: Array[Dictionary] = []
	var has_data := false

	var catalog_variant: Variant = root.get("unit_catalog", [])
	if catalog_variant is Array:
		for item in catalog_variant:
			if not (item is Dictionary):
				continue
			var entry: Dictionary = (item as Dictionary).duplicate(true)
			var unit_class := UnitState.normalize_class_name(entry.get(UnitState.UNIT_CLASS, ""))
			if unit_class == "":
				continue
			entry[UnitState.UNIT_CLASS] = unit_class
			if str(entry.get(UnitState.NAME, "")).strip_edges() == "":
				entry[UnitState.NAME] = unit_class.capitalize()
			unit_catalog[unit_class] = entry
		has_data = has_data or not unit_catalog.is_empty()

	var units_variant: Variant = root.get("units", [])
	if units_variant is Array:
		for item in units_variant:
			if not (item is Dictionary):
				continue
			var unit: Dictionary = (item as Dictionary).duplicate(true)
			# Initial positions are managed by Tiled object layers.
			unit[UnitState.POS] = INVALID_TILE
			UnitState.ensure_turn_flags(unit)
			units.append(unit)
			var legacy_class := UnitState.normalize_class_name(unit.get(UnitState.UNIT_CLASS, ""))
			if legacy_class != "" and not unit_catalog.has(legacy_class):
				var template := unit.duplicate(true)
				template.erase(UnitState.ID)
				template.erase(UnitState.FACTION)
				template.erase(UnitState.POS)
				template.erase(UnitState.MOVED)
				template.erase(UnitState.ATTACKED)
				unit_catalog[legacy_class] = template
		has_data = has_data or not units.is_empty()

	if not has_data:
		return {"ok": false, "error": "ユニットデータ形式が不正です。"}
	return {"ok": true, "unit_catalog": unit_catalog, "units": units}

static func spawn_units_from_catalog(
	unit_catalog: Dictionary,
	spawns: Array,
	spawn_to_tile: Callable,
	is_valid_hex: Callable
) -> Dictionary:
	var units: Array[Dictionary] = []
	var unplaced_unit_ids: Array[String] = []
	var generated_count_by_class := {}
	var used_ids := {}
	for spawn_item in spawns:
		if not (spawn_item is Dictionary):
			continue
		var spawn := spawn_item as Dictionary
		var unit_class := UnitState.normalize_class_name(spawn.get(UnitState.UNIT_CLASS, ""))
		if unit_class == "":
			var fallback_class := UnitState.normalize_class_name(spawn.get("unit_id", ""))
			if unit_catalog.has(fallback_class):
				unit_class = fallback_class
		if unit_class == "" or not unit_catalog.has(unit_class):
			var missing := str(spawn.get("unit_id", unit_class)).strip_edges()
			if missing != "":
				unplaced_unit_ids.append(missing)
			continue
		var template := (unit_catalog[unit_class] as Dictionary).duplicate(true)
		template[UnitState.UNIT_CLASS] = unit_class
		var faction := UnitState.normalize_class_name(spawn.get(UnitState.FACTION, template.get(UnitState.FACTION, "player")))
		if faction == "":
			faction = "player"
		template[UnitState.FACTION] = faction
		var requested_id := str(spawn.get("unit_id", "")).strip_edges()
		var base_id := requested_id
		if base_id == "":
			var key := "%s|%s" % [faction, unit_class]
			var next_num := int(generated_count_by_class.get(key, 0)) + 1
			generated_count_by_class[key] = next_num
			base_id = "%s_%s_%d" % [faction, unit_class, next_num]
		template[UnitState.ID] = _ensure_unique_unit_id(base_id, used_ids)
		var unit_name := str(spawn.get("unit_name", "")).strip_edges()
		if unit_name != "":
			template[UnitState.NAME] = unit_name
		elif str(template.get(UnitState.NAME, "")).strip_edges() == "":
			template[UnitState.NAME] = unit_class.capitalize()
		var ai_group := UnitState.normalize_class_name(spawn.get(UnitState.AI_GROUP, template.get(UnitState.AI_GROUP, "")))
		if ai_group != "":
			template[UnitState.AI_GROUP] = ai_group
		var target_tile: Vector2i = spawn_to_tile.call(spawn)
		template[UnitState.POS] = target_tile if bool(is_valid_hex.call(target_tile)) else INVALID_TILE
		UnitState.ensure_turn_flags(template)
		units.append(template)
		if not bool(is_valid_hex.call(target_tile)):
			unplaced_unit_ids.append(str(template.get(UnitState.ID, "")))

	var status := ""
	if units.is_empty():
		status = "Tiled spawnから生成できるユニットがありません。"
	elif not unplaced_unit_ids.is_empty():
		status = "無効なspawnがあります: %s" % ", ".join(unplaced_unit_ids)
	return {"units": units, "unplaced_ids": unplaced_unit_ids, "status": status}

static func apply_legacy_spawns(
	units: Array[Dictionary],
	spawns: Array,
	spawn_to_tile: Callable,
	is_valid_hex: Callable
) -> Dictionary:
	var unplaced_unit_ids: Array[String] = []
	var id_to_index := {}
	for idx in units.size():
		var unit_id := str(units[idx].get(UnitState.ID, ""))
		if unit_id != "":
			id_to_index[unit_id] = idx

	for spawn_item in spawns:
		if not (spawn_item is Dictionary):
			continue
		var spawn := spawn_item as Dictionary
		var unit_id := str(spawn.get("unit_id", "")).strip_edges()
		if unit_id == "" or not id_to_index.has(unit_id):
			continue
		var unit_idx := int(id_to_index[unit_id])
		var unit_faction := UnitState.normalize_class_name(units[unit_idx].get(UnitState.FACTION, ""))
		var spawn_faction := UnitState.normalize_class_name(spawn.get(UnitState.FACTION, unit_faction))
		if unit_faction != "" and spawn_faction != "" and unit_faction != spawn_faction:
			continue
		var ai_group := UnitState.normalize_class_name(spawn.get(UnitState.AI_GROUP, units[unit_idx].get(UnitState.AI_GROUP, "")))
		if ai_group != "":
			units[unit_idx][UnitState.AI_GROUP] = ai_group
		var target_tile: Vector2i = spawn_to_tile.call(spawn)
		if not bool(is_valid_hex.call(target_tile)):
			continue
		units[unit_idx][UnitState.POS] = target_tile

	for unit in units:
		var unit_id := str(unit.get(UnitState.ID, ""))
		var tile: Vector2i = unit.get(UnitState.POS, INVALID_TILE)
		if unit_id != "" and not bool(is_valid_hex.call(tile)):
			unplaced_unit_ids.append(unit_id)

	var status := ""
	if not unplaced_unit_ids.is_empty():
		status = "Tiled spawn未設定のユニットがあります: %s" % ", ".join(unplaced_unit_ids)
	return {"units": units, "unplaced_ids": unplaced_unit_ids, "status": status}

static func _ensure_unique_unit_id(base_id: String, used_ids: Dictionary) -> String:
	var normalized := base_id if base_id != "" else "unit"
	var candidate := normalized
	var suffix := 2
	while used_ids.has(candidate):
		candidate = "%s_%d" % [normalized, suffix]
		suffix += 1
	used_ids[candidate] = true
	return candidate
