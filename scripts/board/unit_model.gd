class_name UnitModel
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

var data: Dictionary

func _init(source: Dictionary = {}) -> void:
	data = source

func id() -> String:
	return UnitState.id(data)

func faction() -> String:
	return UnitState.faction(data)

func name() -> String:
	return str(data.get(UnitState.NAME, "?"))

func hp() -> int:
	return UnitState.hp(data)

func set_hp(value: int) -> void:
	data[UnitState.HP] = value

func atk() -> int:
	return UnitState.atk(data)

func is_moved() -> bool:
	return UnitState.is_moved(data)

func set_moved(value: bool) -> void:
	data[UnitState.MOVED] = value

func is_attacked() -> bool:
	return UnitState.is_attacked(data)

func set_attacked(value: bool) -> void:
	data[UnitState.ATTACKED] = value
