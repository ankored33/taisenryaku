extends RefCounted
class_name UnitCatalogDialogUtils

static func catalog_entry_for(board: HexBoard, unit_class: String) -> Dictionary:
	if board == null:
		return {}
	return board.get_unit_catalog_entry(unit_class)

static func build_preview_unit(
	board: HexBoard,
	unit_class: String,
	catalog_entry: Dictionary,
	fallback_faction: String = "player",
	use_current_faction: bool = false
) -> Dictionary:
	var preview := catalog_entry.duplicate(true)
	preview["unit_class"] = unit_class
	var faction := fallback_faction
	if use_current_faction and board != null:
		faction = str(board.query_current_faction())
	preview["faction"] = faction
	return preview

static func format_entry_text(entry: Dictionary, include_combat_flags: bool = false) -> String:
	if entry.is_empty():
		return "ユニット情報がありません。"
	var min_range := int(entry.get("min_range", 1))
	var max_range := int(entry.get("range", min_range))
	var range_text := str(max_range) if min_range == max_range else "%d-%d" % [min_range, max_range]
	var text := "名前: %s\n兵科: %s\nコスト: %d\nHP: %d\n攻撃: %d\n移動: %d\n視界: %d\n射程: %s" % [
		str(entry.get("name", "?")),
		str(entry.get("unit_class", "?")),
		int(entry.get("cost", 0)),
		int(entry.get("hp", 0)),
		int(entry.get("atk", 0)),
		int(entry.get("move", 0)),
		int(entry.get("vision", 3)),
		range_text
	]
	if include_combat_flags:
		text += "\n攻撃可: %s\n輸送: %s" % [
			"はい" if bool(entry.get("can_attack", true)) else "いいえ",
			"はい" if bool(entry.get("is_transport", false)) else "いいえ"
		]
	return text
