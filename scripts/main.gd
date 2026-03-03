extends Node2D

const BattleCameraController = preload("res://scripts/ui/battle_camera_controller.gd")
const UnitOverlayService = preload("res://scripts/ui/unit_overlay_service.gd")
const BattleHudController = preload("res://scripts/ui/battle_hud_controller.gd")
const BattleDebugToolsController = preload("res://scripts/debug/battle_debug_tools_controller.gd")
const ProductionDialogController = preload("res://scripts/ui/production_dialog_controller.gd")
const DeploymentDialogController = preload("res://scripts/ui/deployment_dialog_controller.gd")

const CAMERA_SPEED := 1152.0
const VIEW_PADDING := 12.0
const ZOOM_STEP := 1.12
const MIN_ZOOM := 0.60
const MAX_ZOOM := 2.40
const LEFT_PANEL_WIDTH := 300.0
const TURN_START_DIALOG_DURATION_SEC := 1.2
const TRANSPORT_GOAL_DIALOG_DURATION_SEC := 1.6
const DEFAULT_TRANSPORT_GOAL_VICTORY_SCORE := 300
const ATTACK_SEQUENCE_DURATION_SEC := 1.2
const DEFEAT_EFFECT_CONFIG_PATH := "res://data/defeat_explosion.json"
const HP_OFFSET_FACTOR := Vector2(-0.70, 0.10)
const MOVED_MARKER_OFFSET_FACTOR := Vector2(0.40, 0.25)

@onready var board: HexBoard = $HexBoard
@onready var left_panel: Control = $CanvasLayer/LeftPanel
@onready var left_panel_vbox: VBoxContainer = $CanvasLayer/LeftPanel/Margin/VBox
@onready var turn_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/Turn
@onready var status_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/Status
@onready var tile_info_label: Label = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/TileInfo")
@onready var unit_header_label: Label = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/UnitHeader") as Label
@onready var unit_info_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/UnitInfo
@onready var battle_background: Sprite2D = get_node_or_null("HexBoard/BattleBackground")
@onready var end_turn_button: Button = $CanvasLayer/LeftPanel/Margin/VBox/EndTurnButton
@onready var friendly_auto_button: Button = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/FriendlyAutoButton") as Button
@onready var end_turn_confirm: ConfirmationDialog = $CanvasLayer/EndTurnConfirm
@onready var friendly_auto_confirm: ConfirmationDialog = get_node_or_null("CanvasLayer/FriendlyAutoConfirm") as ConfirmationDialog
@onready var attack_confirm: ConfirmationDialog = $CanvasLayer/AttackConfirm
@onready var move_cancel_confirm: ConfirmationDialog = $CanvasLayer/MoveCancelConfirm
@onready var unit_action_menu: PopupMenu = get_node_or_null("CanvasLayer/UnitActionMenu") as PopupMenu
@onready var unit_info_popup: AcceptDialog = get_node_or_null("CanvasLayer/UnitInfoPopup") as AcceptDialog
@onready var turn_start_dialog: AcceptDialog = get_node_or_null("CanvasLayer/TurnStartDialog") as AcceptDialog
@onready var transport_goal_dialog: AcceptDialog = get_node_or_null("CanvasLayer/TransportGoalDialog") as AcceptDialog
@onready var enemy_turn_indicator: Label = get_node_or_null("CanvasLayer/EnemyTurnIndicator") as Label
@onready var attack_sequence_overlay: ColorRect = get_node_or_null("CanvasLayer/AttackSequenceOverlay") as ColorRect
@onready var attack_sequence_label: Label = get_node_or_null("CanvasLayer/AttackSequenceOverlay/AttackSequenceLabel") as Label
@onready var debug_victory_button: Button = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/DebugVictory")
@onready var debug_defeat_button: Button = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/DebugDefeat")
@onready var unit_hp_overlay_layer: Control = get_node_or_null("CanvasLayer/UnitHpOverlayLayer") as Control

var board_anchor := Vector2.ZERO
var board_pan := Vector2.ZERO
var board_rect := Rect2()
var board_zoom := 1.0
var stage_background_path := ""
var transport_goal_dialog_token := 0
var attack_sequence_token := 0
var battle_result_reported := false
var transport_goal_victory_score := DEFAULT_TRANSPORT_GOAL_VICTORY_SCORE
var stage_camera_config := {}
var has_stage_camera_config := false
var unit_hp_labels := {}
var unit_moved_markers := {}
var defeat_effect_config := {}
var unit_action_menu_actions := {}
var camera_controller: BattleCameraController
var overlay_service := UnitOverlayService.new()
var hud_controller: BattleHudController
var debug_tools_controller: BattleDebugToolsController
var production_dialog_controller: ProductionDialogController
var deployment_dialog_controller: DeploymentDialogController

func _ready() -> void:
	camera_controller = BattleCameraController.new(CAMERA_SPEED, ZOOM_STEP, MIN_ZOOM, MAX_ZOOM, VIEW_PADDING)
	hud_controller = BattleHudController.new($CanvasLayer, VIEW_PADDING)
	hud_controller.set_button_order([
		"terrain_color_editor",
		"fog_debug",
		"bgm_editor",
		"unit_param_editor",
		"enemy_ai_production_editor"
	])
	_ensure_tile_info_label()
	_configure_left_panel_layout()
	_apply_stage_map_settings()
	board.bind_ui(turn_label, status_label, unit_info_label, tile_info_label)
	board.set_attack_confirm_handler(_on_attack_confirm_requested)
	board.set_move_cancel_confirm_handler(_on_move_cancel_confirm_requested)
	board.set_unit_action_menu_handler(_on_unit_action_menu_requested)
	board.set_turn_start_handler(_on_turn_started)
	board.set_battle_sequence_handler(_on_battle_sequence_requested)
	if board.has_signal("transport_goal_reached"):
		board.transport_goal_reached.connect(_on_transport_goal_reached)
	if board.has_signal("unit_removed"):
		board.unit_removed.connect(_on_board_unit_removed)
	if board.has_signal("defeat_condition_met"):
		board.defeat_condition_met.connect(_on_defeat_condition_met)
	_load_defeat_effect_config()
	_ensure_dialogs()
	_ensure_unit_action_menu()
	production_dialog_controller = ProductionDialogController.new()
	production_dialog_controller.setup(
		$CanvasLayer,
		board,
		Callable(self, "_on_production_action_chosen"),
		Callable(self, "_on_production_dialog_closed")
	)
	deployment_dialog_controller = DeploymentDialogController.new()
	deployment_dialog_controller.setup(
		$CanvasLayer,
		board,
		Callable(self, "_on_deployment_unit_selected"),
		Callable(self, "_on_deployment_finished"),
		left_panel_vbox
	)
	_ensure_unit_info_popup()
	_ensure_enemy_turn_indicator()
	_ensure_attack_sequence_ui()
	_ensure_unit_hp_overlay_layer()
	_setup_debug_tools_if_enabled()
	board.load_units("res://data/units.json")
	var stage_data: Dictionary = {}
	if has_node("/root/GameFlow"):
		var stage_data_variant: Variant = GameFlow.get_current_stage_data()
		if stage_data_variant is Dictionary:
			stage_data = stage_data_variant
			board.apply_stage_unit_spawns(stage_data)
	board.apply_stage_resources(stage_data)
	board.apply_stage_turn_limit(stage_data)
	board.apply_stage_ai_production(stage_data)
	board.apply_transport_goal_from_stage(stage_data)
	_apply_transport_goal_victory_score(stage_data)
	board.apply_capture_points_from_stage(stage_data)
	end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	end_turn_confirm.confirmed.connect(_on_end_turn_confirmed)
	if friendly_auto_button != null:
		friendly_auto_button.pressed.connect(_on_friendly_auto_button_pressed)
	if friendly_auto_confirm != null:
		friendly_auto_confirm.confirmed.connect(_on_friendly_auto_confirmed)
	attack_confirm.confirmed.connect(_on_attack_confirmed)
	attack_confirm.canceled.connect(_on_attack_canceled)
	move_cancel_confirm.confirmed.connect(_on_move_cancel_confirmed)
	move_cancel_confirm.canceled.connect(_on_move_cancel_canceled)
	if turn_start_dialog != null:
		turn_start_dialog.get_ok_button().hide()
	if transport_goal_dialog != null:
		transport_goal_dialog.get_ok_button().hide()
	if debug_victory_button != null:
		debug_victory_button.pressed.connect(_on_debug_victory_pressed)
	if debug_defeat_button != null:
		debug_defeat_button.pressed.connect(_on_debug_defeat_pressed)
	if unit_header_label != null:
		unit_header_label.visible = false
	unit_info_label.visible = false
	_refresh_layout()
	_apply_stage_initial_camera_if_needed()
	_apply_battle_background()
	_refresh_friendly_auto_ui_state()
	_start_initial_deployment_phase_if_available()

func _ensure_tile_info_label() -> void:
	if tile_info_label != null:
		return
	tile_info_label = Label.new()
	tile_info_label.name = "TileInfo"
	tile_info_label.text = "カーソル: -\n地形: -\n移動コスト: -"
	tile_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel_vbox.add_child(tile_info_label)
	var unit_header := get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/UnitHeader")
	var status := get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/Status")
	if unit_header != null:
		left_panel_vbox.move_child(tile_info_label, unit_header.get_index())
	elif status != null:
		left_panel_vbox.move_child(tile_info_label, status.get_index() + 1)

func _process(delta: float) -> void:
	var next_pan := camera_controller.apply_pan_input(delta, board_pan)
	if next_pan != board_pan:
		board_pan = next_pan
		_apply_board_transform()
	_update_unit_hp_overlays()
	_refresh_friendly_auto_ui_state()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_refresh_layout()

func _unhandled_input(event: InputEvent) -> void:
	if not camera_controller.should_handle_zoom_event(event):
		return
	var mouse_event := event as InputEventMouseButton
	if not _is_mouse_over_board(mouse_event.position):
		return
	var zoom_factor := camera_controller.zoom_factor_from_event(mouse_event)
	_zoom_board_at(mouse_event.position, zoom_factor)

func _refresh_layout() -> void:
	_apply_left_panel_width()
	board_rect = board.get_board_local_rect()
	board_anchor = Vector2(left_panel.size.x + VIEW_PADDING, VIEW_PADDING)
	_apply_board_transform()
	if hud_controller != null:
		hud_controller.layout_buttons()
	_apply_battle_background()
	_update_unit_hp_overlays()

func _ensure_unit_hp_overlay_layer() -> void:
	unit_hp_overlay_layer = overlay_service.ensure_layer($CanvasLayer, unit_hp_overlay_layer)

func _update_unit_hp_overlays() -> void:
	overlay_service.update(unit_hp_overlay_layer, board, unit_hp_labels, unit_moved_markers, HP_OFFSET_FACTOR, MOVED_MARKER_OFFSET_FACTOR)

func _apply_board_transform() -> void:
	board_pan = camera_controller.clamp_pan_and_apply(board, left_panel.size.x, board_rect, board_anchor, board_pan, board_zoom)

func _is_mouse_over_board(mouse_position: Vector2) -> bool:
	return camera_controller.is_mouse_over_board(board, board_rect, mouse_position)

func _zoom_board_at(pivot_screen: Vector2, zoom_factor: float) -> void:
	var zoom_result := camera_controller.zoom_at(pivot_screen, board_anchor, board_pan, board_zoom, zoom_factor)
	if not bool(zoom_result.get("changed", false)):
		return
	board_zoom = float(zoom_result.get("zoom", board_zoom))
	board_pan = zoom_result.get("pan", board_pan) as Vector2
	_apply_board_transform()

func _setup_debug_tools_if_enabled() -> void:
	if not OS.is_debug_build():
		return
	debug_tools_controller = BattleDebugToolsController.new()
	debug_tools_controller.setup($CanvasLayer, board, hud_controller)

func _on_end_turn_button_pressed() -> void:
	end_turn_confirm.popup_centered()

func _on_end_turn_confirmed() -> void:
	board.end_turn()

func _on_friendly_auto_button_pressed() -> void:
	if friendly_auto_confirm == null:
		_on_friendly_auto_confirmed()
		return
	friendly_auto_confirm.popup_centered()

func _on_friendly_auto_confirmed() -> void:
	await board.run_current_faction_auto_actions()
	_refresh_friendly_auto_ui_state()

func _on_attack_confirm_requested(text: String) -> void:
	attack_confirm.dialog_text = text
	attack_confirm.popup_centered()

func _on_attack_confirmed() -> void:
	board.confirm_pending_attack()

func _on_attack_canceled() -> void:
	board.cancel_pending_attack()

func _on_move_cancel_confirm_requested(text: String) -> void:
	move_cancel_confirm.dialog_text = text
	move_cancel_confirm.popup_centered()

func _on_move_cancel_confirmed() -> void:
	board.confirm_pending_move_cancel()

func _on_move_cancel_canceled() -> void:
	board.cancel_pending_move_cancel()

func _on_turn_started(faction: String) -> void:
	if board != null and bool(board.query_is_deployment_active()):
		return
	var ai_faction := str(board.get("ai_faction"))
	_update_enemy_turn_indicator(faction, ai_faction)
	if has_node("/root/GameFlow") and GameFlow.has_method("play_battle_turn_bgm"):
		GameFlow.play_battle_turn_bgm(faction, ai_faction)
	var label := "敵" if faction == ai_faction else "味方"
	if turn_start_dialog == null:
		if faction == ai_faction:
			board.run_ai_turn_if_needed()
		return
	turn_start_dialog.title = "ターン開始"
	turn_start_dialog.dialog_text = "%sターン開始 (%s)" % [label, faction.to_upper()]
	board.set_turn_start_pause(true)
	turn_start_dialog.popup_centered()
	await get_tree().create_timer(TURN_START_DIALOG_DURATION_SEC).timeout
	turn_start_dialog.hide()
	board.set_turn_start_pause(false)
	if faction == ai_faction:
		board.run_ai_turn_if_needed()
	_refresh_friendly_auto_ui_state()

func _on_transport_goal_reached(unit_name: String, score_delta: int, total_score: int) -> void:
	var reached_victory := total_score >= transport_goal_victory_score
	if transport_goal_dialog != null:
		transport_goal_dialog_token += 1
		var token := transport_goal_dialog_token
		transport_goal_dialog.title = "輸送目標達成"
		transport_goal_dialog.dialog_text = "%s がゴールに到達\n+%d (合計 %d)" % [unit_name, score_delta, total_score]
		transport_goal_dialog.popup_centered()
		if reached_victory:
			_report_battle_result_once(true)
			return
		await get_tree().create_timer(TRANSPORT_GOAL_DIALOG_DURATION_SEC).timeout
		if token == transport_goal_dialog_token:
			transport_goal_dialog.hide()
		return
	if reached_victory:
		_report_battle_result_once(true)

func _apply_transport_goal_victory_score(stage_data: Dictionary) -> void:
	transport_goal_victory_score = DEFAULT_TRANSPORT_GOAL_VICTORY_SCORE
	var goal_variant: Variant = stage_data.get("transport_goal", {})
	if not (goal_variant is Dictionary):
		return
	var goal := goal_variant as Dictionary
	transport_goal_victory_score = maxi(1, int(goal.get("victory_score", DEFAULT_TRANSPORT_GOAL_VICTORY_SCORE)))

func _on_board_unit_removed(payload: Dictionary) -> void:
	if str(payload.get("reason", "")) != "defeat":
		return
	var unit_variant: Variant = payload.get("unit", {})
	if not (unit_variant is Dictionary):
		return
	var unit := unit_variant as Dictionary
	if str(unit.get("faction", "")) != "enemy":
		return
	var local_position := Vector2.ZERO
	var local_position_variant: Variant = payload.get("local_position", Vector2.ZERO)
	if local_position_variant is Vector2:
		local_position = local_position_variant
	elif payload.has("tile"):
		local_position = board.map_to_local(board.query_to_vec2i(payload.get("tile", Vector2i.ZERO)))
	_play_enemy_defeat_explosion(local_position)

func _on_defeat_condition_met(_reason: String) -> void:
	_report_battle_result_once(false)

func _load_defeat_effect_config() -> void:
	defeat_effect_config = {
		"id": "defeat_explosion",
		"trigger": "on_enemy_defeat",
		"vfx": {
			"offset": [0, 1.0, 0],
			"scale": 1.0,
			"lifetime_sec": 1.8,
			"particle_count": 56,
			"particle_speed_min": 70.0,
			"particle_speed_max": 220.0
		},
		"sfx": {
			"cue": "",
			"volume": 0.9
		}
	}
	var file := FileAccess.open(DEFEAT_EFFECT_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		defeat_effect_config = (parsed as Dictionary).duplicate(true)

func _play_enemy_defeat_explosion(local_position: Vector2) -> void:
	var vfx_variant: Variant = defeat_effect_config.get("vfx", {})
	var vfx: Dictionary = vfx_variant if vfx_variant is Dictionary else {}
	var offset_y := 1.0
	var offset_variant: Variant = vfx.get("offset", [0, 1.0, 0])
	if offset_variant is Array:
		var offset_array := offset_variant as Array
		if offset_array.size() >= 2:
			offset_y = float(offset_array[1])
	var scale_factor := maxf(0.1, float(vfx.get("scale", 1.0)))
	var lifetime_sec := maxf(0.8, float(vfx.get("lifetime_sec", 1.8)))
	var effect_node := Node2D.new()
	effect_node.position = local_position + Vector2(0.0, -float(board.tile_height) * 0.5 * offset_y)
	board.add_child(effect_node)

	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.lifetime = lifetime_sec
	particles.explosiveness = 1.0
	particles.amount = maxi(1, int(vfx.get("particle_count", 42)))
	particles.spread = 180.0
	particles.direction = Vector2.RIGHT
	particles.initial_velocity_min = maxf(0.0, float(vfx.get("particle_speed_min", 80.0))) * scale_factor
	particles.initial_velocity_max = maxf(particles.initial_velocity_min, float(vfx.get("particle_speed_max", 240.0)) * scale_factor)
	particles.gravity = Vector2(0.0, 280.0)
	particles.scale_amount_min = 0.7 * scale_factor
	particles.scale_amount_max = 1.6 * scale_factor

	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.76, 1.0),
		Color(1.0, 0.52, 0.22, 0.92),
		Color(0.36, 0.08, 0.05, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	particles.color_ramp = grad

	effect_node.add_child(particles)
	particles.emitting = true

	var timer := get_tree().create_timer(lifetime_sec + 0.45)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(effect_node):
			effect_node.queue_free()
	)

func _on_debug_victory_pressed() -> void:
	_report_battle_result_once(true)

func _on_debug_defeat_pressed() -> void:
	_report_battle_result_once(false)

func _report_battle_result_once(victory: bool) -> void:
	if battle_result_reported:
		return
	battle_result_reported = true
	if has_node("/root/GameFlow"):
		GameFlow.report_battle_result(victory)

func _refresh_friendly_auto_ui_state() -> void:
	if friendly_auto_button == null:
		return
	var can_use := false
	can_use = bool(board.can_run_current_faction_auto_actions())
	friendly_auto_button.disabled = not can_use

func _apply_stage_map_settings() -> void:
	if not has_node("/root/GameFlow"):
		has_stage_camera_config = false
		stage_camera_config = {}
		return
	var stage_data := GameFlow.get_current_stage_data()
	if not (stage_data is Dictionary):
		has_stage_camera_config = false
		stage_camera_config = {}
		return
	var map_data_variant: Variant = stage_data.get("map", {})
	if not (map_data_variant is Dictionary):
		has_stage_camera_config = false
		stage_camera_config = {}
		return
	var map_data: Dictionary = map_data_variant
	board.cols = maxi(1, int(map_data.get("cols", board.cols)))
	board.rows = maxi(1, int(map_data.get("rows", board.rows)))
	var tile_width := maxi(1, int(map_data.get("tile_width", int(board.get("tile_width")))))
	var tile_height := maxi(1, int(map_data.get("tile_height", int(board.get("tile_height")))))
	var hex_side_length := maxi(0, int(map_data.get("hex_side_length", int(board.get("hex_side_length")))))
	var stagger_axis := str(map_data.get("stagger_axis", str(board.get("stagger_axis"))))
	var stagger_index := str(map_data.get("stagger_index", str(board.get("stagger_index"))))
	board.configure_hex_metrics(tile_width, tile_height, hex_side_length, stagger_axis, stagger_index)
	board.apply_stage_terrain(stage_data)
	stage_background_path = str(map_data.get("background_image", ""))
	var camera_variant: Variant = map_data.get("camera", {})
	has_stage_camera_config = camera_variant is Dictionary
	stage_camera_config = (camera_variant as Dictionary).duplicate(true) if has_stage_camera_config else {}

func _apply_stage_initial_camera_if_needed() -> void:
	if not has_stage_camera_config:
		return
	var target_local := _stage_camera_target_local()
	var target_zoom := _stage_camera_target_zoom()
	board_zoom = target_zoom
	var viewport_rect := get_viewport_rect()
	var side_gutter := left_panel.size.x + VIEW_PADDING
	var view_left := side_gutter
	var view_top := VIEW_PADDING
	var view_right := viewport_rect.size.x - side_gutter
	var view_bottom := viewport_rect.size.y - VIEW_PADDING
	var view_center := Vector2(
		(view_left + view_right) * 0.5,
		(view_top + view_bottom) * 0.5
	)
	board_pan = view_center - board_anchor - (target_local * board_zoom)
	_apply_board_transform()

func _stage_camera_target_zoom() -> float:
	return 1.0

func _stage_camera_target_local() -> Vector2:
	var fallback := board_rect.position + board_rect.size * 0.5
	if not has_stage_camera_config:
		return fallback
	if stage_camera_config.has("tile"):
		var tile_raw: Variant = stage_camera_config.get("tile", [])
		if tile_raw is Array and (tile_raw as Array).size() >= 2:
			var tile := tile_raw as Array
			var q := int(tile[0])
			var r := int(tile[1])
			return board.map_to_local(Vector2i(q, r))
	if stage_camera_config.has("local_pos"):
		var pos_raw: Variant = stage_camera_config.get("local_pos", [])
		if pos_raw is Array and (pos_raw as Array).size() >= 2:
			var pos := pos_raw as Array
			return Vector2(float(pos[0]), float(pos[1]))
	return fallback

func _ensure_dialogs() -> void:
	if turn_start_dialog == null:
		turn_start_dialog = AcceptDialog.new()
		turn_start_dialog.name = "TurnStartDialog"
		$CanvasLayer.add_child(turn_start_dialog)
	if transport_goal_dialog == null:
		transport_goal_dialog = AcceptDialog.new()
		transport_goal_dialog.name = "TransportGoalDialog"
		$CanvasLayer.add_child(transport_goal_dialog)

func _ensure_unit_info_popup() -> void:
	if unit_info_popup != null:
		return
	unit_info_popup = AcceptDialog.new()
	unit_info_popup.name = "UnitInfoPopup"
	unit_info_popup.title = "ユニット情報"
	$CanvasLayer.add_child(unit_info_popup)

func _ensure_unit_action_menu() -> void:
	if unit_action_menu != null:
		return
	unit_action_menu = PopupMenu.new()
	unit_action_menu.name = "UnitActionMenu"
	unit_action_menu.id_pressed.connect(_on_unit_action_menu_id_pressed)
	$CanvasLayer.add_child(unit_action_menu)

func _on_unit_action_menu_requested(payload: Dictionary) -> void:
	if deployment_dialog_controller != null and deployment_dialog_controller.is_deployment_menu_payload(payload):
		deployment_dialog_controller.open_from_payload(payload)
		return
	if production_dialog_controller != null and production_dialog_controller.is_production_menu_payload(payload):
		production_dialog_controller.open_from_payload(payload)
		return
	_ensure_unit_action_menu()
	if unit_action_menu == null:
		return
	unit_action_menu.clear()
	unit_action_menu_actions.clear()
	var items_variant: Variant = payload.get("items", [])
	if not (items_variant is Array):
		return
	var items := items_variant as Array
	var next_id := 0
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item := item_variant as Dictionary
		var action := str(item.get("action", "")).strip_edges().to_lower()
		var label := str(item.get("label", action))
		if action == "":
			continue
		unit_action_menu.add_item(label, next_id)
		unit_action_menu.set_item_disabled(unit_action_menu.get_item_count() - 1, bool(item.get("disabled", false)))
		unit_action_menu_actions[next_id] = action
		next_id += 1
	if next_id <= 0:
		return
	unit_action_menu.position = Vector2i(get_viewport().get_mouse_position())
	unit_action_menu.reset_size()
	unit_action_menu.popup()

func _on_production_action_chosen(action: String) -> void:
	if board != null:
		board.cmd_choose_unit_action(action)

func _on_production_dialog_closed() -> void:
	if board != null:
		board.cmd_clear_pending_production()

func _on_deployment_unit_selected(unit_class: String) -> void:
	if board != null:
		board.cmd_select_deployment_unit_class(unit_class)

func _on_deployment_finished() -> void:
	if board != null:
		board.cmd_finish_initial_deployment_phase()
		board.cmd_notify_turn_started()

func _start_initial_deployment_phase_if_available() -> void:
	if board == null:
		return
	board.cmd_start_initial_deployment_phase()

func _on_unit_action_menu_id_pressed(id: int) -> void:
	if board == null:
		return
	if not unit_action_menu_actions.has(id):
		return
	var action := str(unit_action_menu_actions.get(id, ""))
	if action == "":
		return
	if action == "info":
		_popup_selected_unit_info()
	board.cmd_choose_unit_action(action)

func _popup_selected_unit_info() -> void:
	if board == null:
		return
	var unit_idx := int(board.selected_unit_idx)
	if unit_idx < 0 or unit_idx >= board.query_unit_count():
		return
	var unit := board.query_unit(unit_idx)
	if unit.is_empty():
		return
	_ensure_unit_info_popup()
	if unit_info_popup == null:
		return
	unit_info_popup.title = "ユニット情報"
	unit_info_popup.dialog_text = _format_unit_info_text(unit)
	unit_info_popup.popup_centered(Vector2i(420, 320))

func _format_unit_info_text(unit: Dictionary) -> String:
	var min_range := int(unit.get("min_range", 1))
	var max_range := int(unit.get("max_range", min_range))
	var range_text := str(max_range) if min_range == max_range else "%d-%d" % [min_range, max_range]
	return "名前: %s\n陣営: %s\n兵科: %s\nコスト: %d\nHP: %d\n攻撃: %d\n移動: %d\n射程: %s\n移動済み: %s | 攻撃済み: %s" % [
		str(unit.get("name", "?")),
		str(unit.get("faction", "?")).to_upper(),
		str(unit.get("unit_class", "?")),
		int(unit.get("cost", 0)),
		int(unit.get("hp", 0)),
		int(unit.get("atk", 0)),
		int(unit.get("move", 0)),
		range_text,
		"はい" if bool(unit.get("moved", false)) else "いいえ",
		"はい" if bool(unit.get("attacked", false)) else "いいえ"
	]

func _ensure_enemy_turn_indicator() -> void:
	if enemy_turn_indicator != null:
		return
	enemy_turn_indicator = Label.new()
	enemy_turn_indicator.name = "EnemyTurnIndicator"
	enemy_turn_indicator.text = "敵ターン"
	enemy_turn_indicator.visible = false
	enemy_turn_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_turn_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_turn_indicator.add_theme_font_size_override("font_size", 42)
	enemy_turn_indicator.set_anchors_preset(Control.PRESET_CENTER)
	enemy_turn_indicator.position = Vector2(-220.0, -50.0)
	enemy_turn_indicator.size = Vector2(440.0, 100.0)
	$CanvasLayer.add_child(enemy_turn_indicator)

func _update_enemy_turn_indicator(faction: String, ai_faction: String) -> void:
	if enemy_turn_indicator == null:
		return
	enemy_turn_indicator.visible = faction == ai_faction

func _ensure_attack_sequence_ui() -> void:
	if attack_sequence_overlay == null:
		attack_sequence_overlay = ColorRect.new()
		attack_sequence_overlay.name = "AttackSequenceOverlay"
		attack_sequence_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		attack_sequence_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
		attack_sequence_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		attack_sequence_overlay.visible = false
		$CanvasLayer.add_child(attack_sequence_overlay)
	if attack_sequence_label == null:
		attack_sequence_label = Label.new()
		attack_sequence_label.name = "AttackSequenceLabel"
		attack_sequence_label.text = ""
		attack_sequence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		attack_sequence_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		attack_sequence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		attack_sequence_label.add_theme_font_size_override("font_size", 38)
		attack_sequence_label.set_anchors_preset(Control.PRESET_CENTER)
		attack_sequence_label.position = Vector2(-260.0, -70.0)
		attack_sequence_label.size = Vector2(520.0, 140.0)
		attack_sequence_overlay.add_child(attack_sequence_label)

func _on_battle_sequence_requested(payload: Dictionary) -> void:
	if str(payload.get("kind", "")) != "attack":
		return
	await _play_attack_sequence(payload)

func _play_attack_sequence(payload: Dictionary) -> void:
	_ensure_attack_sequence_ui()
	if attack_sequence_overlay == null or attack_sequence_label == null:
		return
	attack_sequence_token += 1
	var token := attack_sequence_token
	var attacker_name := str(payload.get("attacker_name", "攻撃側"))
	var defender_name := str(payload.get("defender_name", "防御側"))
	attack_sequence_label.text = "%s  ->  %s" % [attacker_name, defender_name]
	attack_sequence_overlay.color = Color(0.02, 0.02, 0.02, 0.0)
	attack_sequence_overlay.visible = true
	attack_sequence_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(attack_sequence_overlay, "color:a", 0.52, 0.20)
	tween.parallel().tween_property(attack_sequence_label, "modulate:a", 1.0, 0.16)
	tween.tween_interval(maxf(0.0, ATTACK_SEQUENCE_DURATION_SEC - 0.40))
	tween.tween_property(attack_sequence_overlay, "color:a", 0.0, 0.20)
	tween.parallel().tween_property(attack_sequence_label, "modulate:a", 0.0, 0.20)
	await tween.finished
	if token == attack_sequence_token and attack_sequence_overlay != null:
		attack_sequence_overlay.visible = false

func _configure_left_panel_layout() -> void:
	_apply_left_panel_width()
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_info_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	unit_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if tile_info_label != null:
		tile_info_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		tile_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _apply_left_panel_width() -> void:
	left_panel.custom_minimum_size.x = LEFT_PANEL_WIDTH
	left_panel.size.x = LEFT_PANEL_WIDTH
	left_panel.offset_right = LEFT_PANEL_WIDTH

func _apply_battle_background() -> void:
	if battle_background == null:
		return
	if stage_background_path == "":
		battle_background.texture = null
		battle_background.scale = Vector2.ONE
		return
	var loaded := ResourceLoader.load(stage_background_path)
	if not (loaded is Texture2D):
		battle_background.texture = null
		battle_background.scale = Vector2.ONE
		return
	var texture := loaded as Texture2D
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	battle_background.texture = texture
	var local_rect: Rect2 = board.get_board_local_rect()
	battle_background.position = local_rect.position + local_rect.size * 0.5
	var scale_x := local_rect.size.x / texture_size.x
	var scale_y := local_rect.size.y / texture_size.y
	var uniform_scale := maxf(scale_x, scale_y)
	battle_background.scale = Vector2.ONE * uniform_scale
	battle_background.modulate = Color(1, 1, 1, 1.0)
