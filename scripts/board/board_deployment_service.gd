class_name BoardDeploymentService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")
const BoardVisibilityService = preload("res://scripts/board/board_visibility_service.gd")
const DEFAULT_DEPLOY_FACTION := "player"
const DEPLOY_ZONE_DEPTH_ROWS := 3

static func start_initial_phase(board: HexBoard) -> void:
	board.deployment_active = true
	board.deployment_faction = DEFAULT_DEPLOY_FACTION
	board.deployment_selected_unit_class = ""
	board.cmd_set_selected_unit_idx(-1)
	board.cmd_set_unit_action_mode("")
	board.cmd_clear_unit_info()
	board.queue_redraw()
	request_menu(board)
	board.cmd_update_status("初期配置フェイズ: ユニットを選択し、下側3列の地形に配置してください。")

static func finish_initial_phase(board: HexBoard) -> void:
	board.deployment_active = false
	board.deployment_selected_unit_class = ""
	board.cmd_update_status("配置フェイズを終了しました。通常行動を開始してください。")
	board.queue_redraw()

static func request_menu(board: HexBoard) -> bool:
	if not board.deployment_active:
		return false
	if not board.unit_action_menu_handler.is_valid():
		return false
	var items := list_options(board, board.deployment_faction)
	if items.is_empty():
		board.cmd_update_status("配置可能なユニット定義がありません。")
		return false
	board.unit_action_menu_handler.call({
		"menu_type": "deployment",
		"faction": board.deployment_faction,
		"mp": board.query_faction_mp(board.deployment_faction),
		"items": items
	})
	return true

static func list_options(board: HexBoard, faction: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var mp := board.query_faction_mp(faction)
	for unit_class in board.get_unit_catalog_classes():
		var entry := board.get_unit_catalog_entry(unit_class)
		if entry.is_empty():
			continue
		var cost := maxi(0, int(entry.get(UnitState.COST, 0)))
		var unit_name := str(entry.get(UnitState.NAME, unit_class.capitalize()))
		items.append({
			"action": "deploy:%s" % unit_class,
			"label": "配置: %s (MP %d)" % [unit_name, cost],
			"unit_class": unit_class,
			"unit_name": unit_name,
			"cost": cost,
			"disabled": mp < cost
		})
	return items

static func select_unit_class(board: HexBoard, unit_class: String) -> bool:
	var key := unit_class.strip_edges().to_lower()
	if key == "" or not board.unit_catalog.has(key):
		return false
	board.deployment_selected_unit_class = key
	var entry := board.get_unit_catalog_entry(key)
	var name := str(entry.get(UnitState.NAME, key.capitalize()))
	var cost := int(entry.get(UnitState.COST, 0))
	board.cmd_update_status("配置選択: %s (コスト %d)。配置先ヘクスをクリックしてください。" % [name, cost])
	return true

static func try_deploy_selected_at(board: HexBoard, tile: Vector2i) -> bool:
	if not board.deployment_active:
		return false
	var unit_class := board.deployment_selected_unit_class.strip_edges().to_lower()
	if unit_class == "":
		board.cmd_update_status("先に配置するユニットを選択してください。")
		return false
	if not can_deploy_at(board, tile):
		board.cmd_update_status("そこには配置できません。下側3列の通行可能マスのみ配置可能です。")
		return false
	var entry_variant: Variant = board.unit_catalog.get(unit_class, {})
	if not (entry_variant is Dictionary):
		return false
	var template := (entry_variant as Dictionary).duplicate(true)
	var cost := maxi(0, int(template.get(UnitState.COST, 0)))
	var mp := board.query_faction_mp(board.deployment_faction)
	if mp < cost:
		board.cmd_update_status("MP不足で配置できません。必要: %d / 現在: %d" % [cost, mp])
		request_menu(board)
		return false

	var unit_id := _next_unit_id(board, board.deployment_faction, unit_class)
	template[UnitState.ID] = unit_id
	template[UnitState.UNIT_CLASS] = unit_class
	template[UnitState.FACTION] = board.deployment_faction
	template[UnitState.POS] = tile
	if str(template.get(UnitState.NAME, "")).strip_edges() == "":
		template[UnitState.NAME] = unit_class.capitalize()
	template[UnitState.MOVED] = false
	template[UnitState.ATTACKED] = false
	board.units.append(template)
	board.faction_mp[board.deployment_faction] = mp - cost
	board.cmd_rebuild_unit_occupancy()
	BoardVisibilityService.recompute_visibility_on_board(board)
	board.cmd_update_turn_label()
	board.cmd_update_status("%s を配置しました。MP -%d (残り %d)" % [
		str(template.get(UnitState.NAME, unit_class)),
		cost,
		int(board.faction_mp.get(board.deployment_faction, 0))
	])
	board.queue_redraw()
	request_menu(board)
	return true

static func can_deploy_at(board: HexBoard, tile: Vector2i) -> bool:
	if not board.query_is_valid_hex(tile):
		return false
	if board.query_unit_at(tile) != -1:
		return false
	var min_row := maxi(0, int(board.rows) - DEPLOY_ZONE_DEPTH_ROWS)
	if tile.y < min_row:
		return false
	var terrain := board.query_terrain_type(tile)
	if board.query_is_terrain_impassable(terrain):
		return false
	return true

static func _next_unit_id(board: HexBoard, faction: String, unit_class: String) -> String:
	var base := "%s_%s" % [faction.strip_edges().to_lower(), unit_class.strip_edges().to_lower()]
	var candidate := "%s_deploy_1" % base
	var suffix := 1
	while board.query_unit_index_by_id(candidate) != -1:
		suffix += 1
		candidate = "%s_deploy_%d" % [base, suffix]
	return candidate
