class_name BoardControllerService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

static func handle_click(board: HexBoard, tile: Vector2i) -> void:
	if board.query_is_ai_running() or board.query_is_turn_start_pause():
		return
	if board.has_method("query_is_deployment_active") and bool(board.query_is_deployment_active()):
		if board.has_method("cmd_try_deploy_selected_unit_at"):
			board.cmd_try_deploy_selected_unit_at(tile)
		return
	if board.query_has_pending_attack():
		board.cmd_update_status("先に攻撃確認を完了してください。")
		return
	if board.query_has_pending_move_confirmation():
		board.cmd_update_status("先に移動確認を完了してください。")
		return
	var target_idx = board.query_unit_at(tile)
	if target_idx != -1:
		var target_unit: Dictionary = board.query_unit(target_idx)
		if str(target_unit.get(UnitState.FACTION, "")).strip_edges().to_lower() != "player":
			if not board.query_is_unit_visible_to_player(target_idx):
				target_idx = -1
	var selected_idx := board.query_selected_unit_idx()
	if selected_idx == -1:
		if target_idx == -1 and _try_open_production_menu(board, tile):
			return
		if target_idx != -1:
			board.cmd_set_selected_unit_idx(target_idx)
			board.cmd_set_unit_action_mode("")
			board.queue_redraw()
			var target_unit := board.query_unit(target_idx)
			board.cmd_update_status(board.query_selected_text(target_unit))
			board.cmd_update_unit_info(target_unit)
			var selected_unit: Dictionary = target_unit
			var after_move := bool(selected_unit.get(UnitState.MOVED, false))
			board.cmd_request_unit_action_menu(target_idx, after_move)
		return
	if selected_idx < 0 or selected_idx >= board.query_unit_count():
		board.cmd_set_selected_unit_idx(-1)
		board.cmd_set_unit_action_mode("")
		board.cmd_clear_unit_info()
		board.queue_redraw()
		return

	var selected: Dictionary = board.query_unit(selected_idx)
	var start = board.query_to_vec2i(selected[UnitState.POS])
	var action_mode := board.query_unit_action_mode()

	if target_idx != -1 and target_idx == selected_idx:
		var selected_after_move := bool(selected.get(UnitState.MOVED, false))
		var target_unit := board.query_unit(target_idx)
		board.cmd_request_unit_action_menu(selected_idx, selected_after_move)
		board.cmd_update_status(board.query_selected_text(target_unit))
		board.cmd_update_unit_info(target_unit)
		return

	if target_idx != -1 and board.query_unit(target_idx).get(UnitState.FACTION, "") == selected.get(UnitState.FACTION, ""):
		board.cmd_set_selected_unit_idx(target_idx)
		board.cmd_set_unit_action_mode("")
		board.queue_redraw()
		var switched_unit: Dictionary = board.query_unit(target_idx)
		board.cmd_update_status(board.query_selected_text(switched_unit))
		board.cmd_update_unit_info(switched_unit)
		var switched_after_move := bool(switched_unit.get(UnitState.MOVED, false))
		board.cmd_request_unit_action_menu(target_idx, switched_after_move)
		return

	if str(selected[UnitState.FACTION]) != board.query_current_faction():
		if target_idx != -1:
			board.cmd_set_selected_unit_idx(target_idx)
			board.cmd_set_unit_action_mode("")
			board.queue_redraw()
			var target_unit := board.query_unit(target_idx)
			board.cmd_update_status(board.query_selected_text(target_unit))
			board.cmd_update_unit_info(target_unit)
		else:
			board.cmd_set_selected_unit_idx(-1)
			board.cmd_set_unit_action_mode("")
			board.queue_redraw()
			board.cmd_update_status("選択を解除しました。")
			board.cmd_clear_unit_info()
		return

	if action_mode == "attack":
		_handle_attack_mode_click(board, selected, start, target_idx)
		return

	if action_mode == "move":
		_handle_move_mode_click(board, selected, tile, target_idx)
		return

	if target_idx != -1 and board.query_unit(target_idx).get(UnitState.FACTION, "") != board.query_current_faction():
		if action_mode == "":
			board.cmd_set_selected_unit_idx(target_idx)
			board.cmd_set_unit_action_mode("")
			board.queue_redraw()
			var target_unit := board.query_unit(target_idx)
			board.cmd_update_status(board.query_selected_text(target_unit))
			board.cmd_update_unit_info(target_unit)
			board.cmd_request_unit_action_menu(target_idx, false)
		else:
			board.cmd_update_status("行動メニューで「攻撃」を選択してから敵をクリックしてください。")
			board.cmd_update_unit_info(selected)
		return

	if action_mode == "" and target_idx == -1 and _try_open_production_menu(board, tile):
		return

	if action_mode == "":
		board.cmd_update_status("行動メニューで行動を選択してください。")
		board.cmd_update_unit_info(selected)

static func _try_open_production_menu(board: HexBoard, tile: Vector2i) -> bool:
	if not board.has_method("query_can_open_production_menu"):
		return false
	if not bool(board.query_can_open_production_menu(tile)):
		return false
	if board.query_selected_unit_idx() != -1:
		board.cmd_set_selected_unit_idx(-1)
		board.cmd_set_unit_action_mode("")
		board.cmd_clear_unit_info()
		board.queue_redraw()
	if board.has_method("cmd_request_production_menu"):
		board.cmd_request_production_menu(tile)
		return true
	return false

static func _handle_attack_mode_click(
	board: HexBoard,
	selected: Dictionary,
	start: Vector2i,
	target_idx: int
) -> void:
	var selected_idx := board.query_selected_unit_idx()
	if target_idx == -1 or board.query_unit(target_idx).get(UnitState.FACTION, "") == board.query_current_faction():
		board.cmd_update_status("攻撃対象の敵ユニットを選択してください。")
		board.cmd_update_unit_info(selected)
		return
	var attack_target_center = board.query_to_vec2i(board.query_unit(target_idx).get(UnitState.POS, Vector2i.ZERO))
	var attack_distance = board.query_hex_distance(start, attack_target_center)
	if bool(selected.get(UnitState.ATTACKED, false)):
		board.cmd_set_unit_action_mode("")
		board.cmd_update_status("%s はこのターンすでに攻撃済みです。" % selected[UnitState.NAME])
		board.cmd_update_unit_info(selected)
		return
	if board.query_can_unit_attack_at_range(selected, attack_distance):
		board.cmd_request_attack_confirmation(selected_idx, target_idx, attack_distance)
	else:
		board.cmd_update_status("%s は距離 %d では攻撃できません。" % [selected[UnitState.NAME], attack_distance])
		board.cmd_update_unit_info(selected)

static func _handle_move_mode_click(
	board: HexBoard,
	selected: Dictionary,
	tile: Vector2i,
	target_idx: int
) -> void:
	var selected_idx := board.query_selected_unit_idx()
	if target_idx != -1:
		board.cmd_update_status("移動先タイルを選択してください。")
		board.cmd_update_unit_info(selected)
		return
	if not board.query_can_move_unit_to(selected_idx, tile):
		board.cmd_update_status("その場所には移動できません。")
		board.cmd_update_unit_info(selected)
		return
	if bool(selected.get(UnitState.ATTACKED, false)):
		board.cmd_set_unit_action_mode("")
		board.cmd_update_status("%s はこのターンすでに攻撃済みのため移動できません。" % selected[UnitState.NAME])
		board.cmd_update_unit_info(selected)
		return
	if bool(selected.get(UnitState.MOVED, false)):
		board.cmd_set_unit_action_mode("")
		board.cmd_update_status("%s はこのターンすでに移動済みです。" % selected[UnitState.NAME])
		board.cmd_update_unit_info(selected)
		return
	board.cmd_request_move_confirmation(selected_idx, tile)
