class_name BoardCatalogService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

static func apply_catalog_entry_to_units(units: Array[Dictionary], unit_class: String, entry: Dictionary) -> Array[Dictionary]:
	var next_units: Array[Dictionary] = []
	for unit in units:
		var copied := unit.duplicate(true)
		var current_class := str(copied.get(UnitState.UNIT_CLASS, "")).strip_edges().to_lower()
		if current_class == unit_class:
			_apply_catalog_fields_to_unit(copied, entry)
		next_units.append(copied)
	return next_units

static func save_catalog_to_path(unit_catalog: Dictionary, path: String) -> bool:
	var classes: Array[String] = []
	for key in unit_catalog.keys():
		var unit_class := str(key).strip_edges().to_lower()
		if unit_class != "":
			classes.append(unit_class)
	classes.sort()
	var list := []
	for unit_class in classes:
		var entry_variant: Variant = unit_catalog.get(unit_class, {})
		if entry_variant is Dictionary and not (entry_variant as Dictionary).is_empty():
			list.append((entry_variant as Dictionary).duplicate(true))
	var payload := {
		"unit_catalog": list
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ユニット設定の保存に失敗: %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true

static func _apply_catalog_fields_to_unit(unit: Dictionary, entry: Dictionary) -> void:
	var copied_keys := [
		UnitState.NAME,
		UnitState.COST,
		UnitState.HP,
		UnitState.ATK,
		UnitState.MOVE,
		UnitState.VISION,
		UnitState.MIN_RANGE,
		UnitState.RANGE,
		UnitState.CAN_ATTACK,
		UnitState.IS_TRANSPORT,
		UnitState.DELIVERY_SCORE,
		UnitState.AI_GROUP,
		UnitState.FRIENDLY_AUTO_AI_GROUP,
		UnitState.ICON,
		UnitState.ICON_PLAYER,
		UnitState.ICON_ENEMY
	]
	for key in copied_keys:
		if entry.has(key):
			unit[key] = entry[key]
