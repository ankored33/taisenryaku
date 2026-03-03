class_name UnitState
extends RefCounted

const ID := "id"
const NAME := "name"
const UNIT_CLASS := "unit_class"
const FACTION := "faction"
const POS := "pos"
const HP := "hp"
const ATK := "atk"
const MOVE := "move"
const VISION := "vision"
const ICON := "icon"
const ICON_PLAYER := "icon_player"
const ICON_ENEMY := "icon_enemy"
const COST := "cost"
const MIN_RANGE := "min_range"
const RANGE := "range"
const CAN_ATTACK := "can_attack"
const IS_TRANSPORT := "is_transport"
const DELIVERY_SCORE := "delivery_score"
const AI_GROUP := "ai_group"
const FRIENDLY_AUTO_AI_GROUP := "friendly_auto_ai_group"
const MOVED := "moved"
const ATTACKED := "attacked"

static func normalize_class_name(raw: Variant) -> String:
	return str(raw).strip_edges().to_lower()

static func ensure_turn_flags(unit: Dictionary) -> void:
	unit[MOVED] = false
	unit[ATTACKED] = false

static func id(unit: Dictionary) -> String:
	return str(unit.get(ID, "")).strip_edges()

static func faction(unit: Dictionary) -> String:
	return str(unit.get(FACTION, "")).strip_edges().to_lower()

static func hp(unit: Dictionary) -> int:
	return int(unit.get(HP, 0))

static func atk(unit: Dictionary) -> int:
	return int(unit.get(ATK, 0))

static func pos(unit: Dictionary) -> Variant:
	return unit.get(POS, Vector2i.ZERO)

static func is_moved(unit: Dictionary) -> bool:
	return bool(unit.get(MOVED, false))

static func is_attacked(unit: Dictionary) -> bool:
	return bool(unit.get(ATTACKED, false))
