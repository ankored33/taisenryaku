class_name BoardTurnService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const BoardCaptureService = preload("res://scripts/board/board_capture_service.gd")

static func end_turn(board: HexBoard) -> void:
	board.current_faction = "enemy" if board.current_faction == "player" else "player"
	if board.current_faction == "player":
		board.turn_count = int(board.turn_count) + 1
		if int(board.turn_limit) > 0 and int(board.turn_count) > int(board.turn_limit):
			board.cmd_update_turn_label()
			board.cmd_update_status("制限ターン %d を超過したため敗北しました。" % int(board.turn_limit))
			board.cmd_trigger_defeat("turn_limit")
			return
	board.selected_unit_idx = -1
	board.cmd_set_unit_action_mode("")
	board.cmd_clear_pending_attack()
	board.cmd_clear_pending_move_confirmation()
	board.cmd_clear_pending_production()
	board.cmd_reset_turn_action_flags(board.current_faction)
	board.queue_redraw()
	board.cmd_update_turn_label()
	board.cmd_update_status("手番を交代しました。")
	board.cmd_clear_unit_info()
	board.cmd_notify_turn_started()

static func reset_turn_action_flags(board: HexBoard, faction: String) -> void:
	for unit in board.units:
		if str(unit.get(UnitState.FACTION, "")) == faction:
			unit[UnitState.MOVED] = false
			unit[UnitState.ATTACKED] = false

static func unit_catalog_max_hp(board: HexBoard, unit: Dictionary) -> int:
	var unit_class := str(unit.get(UnitState.UNIT_CLASS, "")).strip_edges().to_lower()
	if unit_class == "" or not board.unit_catalog.has(unit_class):
		return 0
	var catalog_variant: Variant = board.unit_catalog.get(unit_class, {})
	if not (catalog_variant is Dictionary):
		return 0
	var catalog_entry := catalog_variant as Dictionary
	return maxi(0, int(catalog_entry.get(UnitState.HP, 0)))

static func recover_turn_start_hp(board: HexBoard, faction: String, base_range: int) -> void:
	var healed_any := false
	for i in board.units.size():
		var unit := board.units[i]
		if str(unit.get(UnitState.FACTION, "")) != faction:
			continue
		var unit_tile := board.query_to_vec2i(unit.get(UnitState.POS, Vector2i.ZERO))
		if not BoardCaptureService.is_within_owned_capture_point_range(board, unit_tile, faction, base_range):
			continue
		var hp := int(unit.get(UnitState.HP, 0))
		var max_hp := unit_catalog_max_hp(board, unit)
		if max_hp <= 0:
			continue
		if hp >= max_hp:
			continue
		unit[UnitState.HP] = mini(max_hp, hp + 1)
		healed_any = true
	if not healed_any:
		return
	if board.selected_unit_idx >= 0 and board.selected_unit_idx < board.units.size():
		board.cmd_update_unit_info(board.units[board.selected_unit_idx])
	board.cmd_update_turn_label()
	board.queue_redraw()

static func notify_turn_started(board: HexBoard, faction: String, base_range: int) -> void:
	board.cmd_grant_turn_start_income(faction, true)
	recover_turn_start_hp(board, faction, base_range)
	if board.turn_start_handler.is_valid():
		board.turn_start_handler.call(faction)
