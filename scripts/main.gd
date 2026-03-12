extends Node2D

const BattleCameraController = preload("res://scripts/ui/battle_camera_controller.gd")
const UnitOverlayService = preload("res://scripts/ui/unit_overlay_service.gd")
const BattleHudController = preload("res://scripts/ui/battle_hud_controller.gd")
const BattleDebugToolsController = preload("res://scripts/debug/battle_debug_tools_controller.gd")
const ProductionDialogController = preload("res://scripts/ui/production_dialog_controller.gd")
const DeploymentDialogController = preload("res://scripts/ui/deployment_dialog_controller.gd")
const BattleDefeatEffectService = preload("res://scripts/ui/battle_defeat_effect_service.gd")
const BattleStageSetupService = preload("res://scripts/ui/battle_stage_setup_service.gd")

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
const LEFT_FLOATING_BUTTON_HEIGHT := 34.0
const LEFT_FLOATING_BUTTON_GAP := 8.0

@onready var board: HexBoard = $HexBoard
@onready var left_panel: Control = $CanvasLayer/LeftPanel
@onready var left_panel_vbox: VBoxContainer = $CanvasLayer/LeftPanel/Margin/VBox
@onready var turn_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/Turn
@onready var status_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/Status
@onready var status_log_panel: PanelContainer = get_node_or_null("CanvasLayer/StatusLogPanel") as PanelContainer
@onready var tile_info_label: Label = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/TileInfo")
@onready var unit_header_label: Label = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/UnitHeader") as Label
@onready var unit_info_label: Label = $CanvasLayer/LeftPanel/Margin/VBox/UnitInfo
@onready var battle_background: Sprite2D = get_node_or_null("HexBoard/BattleBackground")
@onready var end_turn_button: Button = $CanvasLayer/LeftPanel/Margin/VBox/EndTurnButton
@onready var friendly_auto_button: Button = get_node_or_null("CanvasLayer/LeftPanel/Margin/VBox/FriendlyAutoButton") as Button
@onready var end_turn_confirm: ConfirmationDialog = $CanvasLayer/EndTurnConfirm
@onready var friendly_auto_confirm: ConfirmationDialog = get_node_or_null("CanvasLayer/FriendlyAutoConfirm") as ConfirmationDialog
@onready var attack_confirm: ConfirmationDialog = $CanvasLayer/AttackConfirm
@onready var move_confirm: ConfirmationDialog = $CanvasLayer/MoveCancelConfirm
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
@onready var floating_end_turn_button: Button = get_node_or_null("CanvasLayer/LeftFloatingEndTurnButton") as Button
@onready var floating_friendly_auto_button: Button = get_node_or_null("CanvasLayer/LeftFloatingFriendlyAutoButton") as Button

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
		"debug_victory",
		"debug_defeat",
		"terrain_color_editor",
		"fog_debug",
		"bgm_editor",
		"event_editor",
		"unit_param_editor",
		"enemy_ai_production_editor"
	])
	_ensure_tile_info_label()
	_fix_left_info_order()
	_setup_status_log_panel()
	_configure_left_panel_layout()
	_apply_stage_map_settings()
	board.bind_ui(turn_label, status_label, unit_info_label, tile_info_label)
	board.set_attack_confirm_handler(_on_attack_confirm_requested)
	board.set_move_confirm_handler(_on_move_confirm_requested)
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
	move_confirm.confirmed.connect(_on_move_confirmed)
	move_confirm.canceled.connect(_on_move_canceled)
	if turn_start_dialog != null:
		turn_start_dialog.get_ok_button().hide()
	if transport_goal_dialog != null:
		transport_goal_dialog.get_ok_button().hide()
	_hide_left_panel_debug_buttons()
	_setup_left_floating_action_buttons()
	if unit_header_label != null:
		unit_header_label.visible = false
	unit_info_label.visible = false
	_refresh_layout()
	_apply_stage_initial_camera_if_needed()
	_apply_battle_background()
	_refresh_action_buttons_state()
	_start_initial_deployment_phase_if_available()

func _ensure_tile_info_label() -> void:
	if tile_info_label != null:
		return
	tile_info_label = Label.new()
	tile_info_label.name = "TileInfo"
	tile_info_label.text = "カーソル: -\n地形: -\n移動コスト: -"
	tile_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel_vbox.add_child(tile_info_label)

func _fix_left_info_order() -> void:
	if left_panel_vbox == null or turn_label == null or tile_info_label == null:
		return
	if turn_label.get_parent() != left_panel_vbox or tile_info_label.get_parent() != left_panel_vbox:
		return
	left_panel_vbox.move_child(turn_label, 0)
	left_panel_vbox.move_child(tile_info_label, 1)

func _process(delta: float) -> void:
	var next_pan := camera_controller.apply_pan_input(delta, board_pan)
	if next_pan != board_pan:
		board_pan = next_pan
		_apply_board_transform()
	_update_unit_hp_overlays()

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
	_layout_status_log_panel()
	_layout_left_floating_action_buttons()
	if hud_controller != null:
		hud_controller.layout_buttons()
	_apply_battle_background()
	_update_unit_hp_overlays()

func _setup_status_log_panel() -> void:
	if status_label == null:
		return
	if status_log_panel == null:
		status_log_panel = PanelContainer.new()
		status_log_panel.name = "StatusLogPanel"
		$CanvasLayer.add_child(status_log_panel)
	status_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if status_label.get_parent() != status_log_panel:
		var old_parent := status_label.get_parent()
		if old_parent != null:
			old_parent.remove_child(status_label)
		status_log_panel.add_child(status_label)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layout_status_log_panel()

func _layout_status_log_panel() -> void:
	if status_log_panel == null:
		return
	var width := maxf(180.0, left_panel.size.x - 24.0)
	var height := 110.0
	status_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_log_panel.offset_right = -VIEW_PADDING
	status_log_panel.offset_top = VIEW_PADDING
	status_log_panel.offset_left = status_log_panel.offset_right - width
	status_log_panel.offset_bottom = status_log_panel.offset_top + height

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
	_setup_result_debug_buttons()

func _setup_result_debug_buttons() -> void:
	if hud_controller == null:
		return
	hud_controller.ensure_button(
		"debug_victory",
		"DebugVictoryFloatingButton",
		"勝利デバッグ",
		Vector2(120.0, 34.0),
		Callable(self, "_on_debug_victory_pressed")
	)
	hud_controller.ensure_button(
		"debug_defeat",
		"DebugDefeatFloatingButton",
		"敗北デバッグ",
		Vector2(120.0, 34.0),
		Callable(self, "_on_debug_defeat_pressed")
	)
	hud_controller.layout_buttons()

func _hide_left_panel_debug_buttons() -> void:
	if debug_victory_button != null:
		debug_victory_button.visible = false
		debug_victory_button.disabled = true
	if debug_defeat_button != null:
		debug_defeat_button.visible = false
		debug_defeat_button.disabled = true

func _on_end_turn_button_pressed() -> void:
	if not _can_use_end_turn_button():
		return
	end_turn_confirm.popup_centered()

func _on_end_turn_confirmed() -> void:
	board.end_turn()

func _on_friendly_auto_button_pressed() -> void:
	if friendly_auto_confirm == null:
		_on_friendly_auto_confirmed()
		return
	friendly_auto_confirm.popup_centered()

func _on_friendly_auto_confirmed() -> void:
	_set_action_buttons_locked(true)
	await board.run_current_faction_auto_actions()
	_refresh_action_buttons_state()

func _on_attack_confirm_requested(text: String) -> void:
	attack_confirm.dialog_text = text
	attack_confirm.popup_centered()
	_refresh_action_buttons_state()

func _on_attack_confirmed() -> void:
	board.confirm_pending_attack()
	_refresh_action_buttons_state()

func _on_attack_canceled() -> void:
	board.cancel_pending_attack()
	_refresh_action_buttons_state()

func _on_move_confirm_requested(text: String) -> void:
	move_confirm.title = "移動確認"
	move_confirm.dialog_text = text
	move_confirm.popup_centered()
	_refresh_action_buttons_state()

func _on_move_confirmed() -> void:
	board.confirm_pending_move()
	_refresh_action_buttons_state()

func _on_move_canceled() -> void:
	board.cancel_pending_move()
	_refresh_action_buttons_state()

func _on_turn_started(faction: String) -> void:
	_refresh_action_buttons_state()
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
	_refresh_action_buttons_state()

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
	var local_position := Vector2.ZERO
	var local_position_variant: Variant = payload.get("local_position", Vector2.ZERO)
	if local_position_variant is Vector2:
		local_position = local_position_variant
	elif payload.has("tile"):
		local_position = board.map_to_local(board.query_to_vec2i(payload.get("tile", Vector2i.ZERO)))
	_play_defeat_effect(local_position)

func _on_defeat_condition_met(_reason: String) -> void:
	_report_battle_result_once(false)

func _load_defeat_effect_config() -> void:
	var fallback := BattleDefeatEffectService.default_config()
	defeat_effect_config = BattleDefeatEffectService.load_config(DEFEAT_EFFECT_CONFIG_PATH, fallback)

func _play_defeat_effect(local_position: Vector2) -> void:
	BattleDefeatEffectService.play_defeat_effect(board, local_position, defeat_effect_config)

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
	var can_use := false
	can_use = bool(board.can_run_current_faction_auto_actions())
	if friendly_auto_button != null:
		friendly_auto_button.disabled = not can_use
	if floating_friendly_auto_button != null:
		floating_friendly_auto_button.disabled = not can_use

func _refresh_action_buttons_state() -> void:
	_refresh_left_floating_action_buttons_visibility()
	_refresh_friendly_auto_ui_state()
	_refresh_end_turn_button_state()

func _set_action_buttons_locked(locked: bool) -> void:
	if floating_end_turn_button != null:
		floating_end_turn_button.disabled = locked
	if end_turn_button != null:
		end_turn_button.disabled = locked
	if floating_friendly_auto_button != null:
		floating_friendly_auto_button.disabled = locked
	if friendly_auto_button != null:
		friendly_auto_button.disabled = locked

func _can_use_end_turn_button() -> bool:
	if board == null:
		return false
	if bool(board.query_is_ai_running()):
		return false
	if bool(board.query_has_pending_attack()) or bool(board.query_has_pending_move_confirmation()):
		return false
	if bool(board.query_is_deployment_active()):
		return false
	return str(board.query_current_faction()) != str(board.query_ai_faction())

func _refresh_end_turn_button_state() -> void:
	var can_use := _can_use_end_turn_button()
	if floating_end_turn_button != null:
		floating_end_turn_button.disabled = not can_use

func _refresh_left_floating_action_buttons_visibility() -> void:
	var visible := true
	if board != null and bool(board.query_is_deployment_active()):
		visible = false
	if floating_end_turn_button != null:
		floating_end_turn_button.visible = visible
	if floating_friendly_auto_button != null:
		floating_friendly_auto_button.visible = visible

func _setup_left_floating_action_buttons() -> void:
	if end_turn_button != null:
		end_turn_button.visible = false
		end_turn_button.disabled = true
	if friendly_auto_button != null:
		friendly_auto_button.visible = false
		friendly_auto_button.disabled = true
	if floating_end_turn_button == null:
		floating_end_turn_button = Button.new()
		floating_end_turn_button.name = "LeftFloatingEndTurnButton"
		floating_end_turn_button.text = "ターン終了"
		floating_end_turn_button.custom_minimum_size = Vector2(0.0, LEFT_FLOATING_BUTTON_HEIGHT)
		$CanvasLayer.add_child(floating_end_turn_button)
	if not floating_end_turn_button.pressed.is_connected(_on_end_turn_button_pressed):
		floating_end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	if floating_friendly_auto_button == null:
		floating_friendly_auto_button = Button.new()
		floating_friendly_auto_button.name = "LeftFloatingFriendlyAutoButton"
		floating_friendly_auto_button.text = "味方自動行動"
		floating_friendly_auto_button.custom_minimum_size = Vector2(0.0, LEFT_FLOATING_BUTTON_HEIGHT)
		$CanvasLayer.add_child(floating_friendly_auto_button)
	if not floating_friendly_auto_button.pressed.is_connected(_on_friendly_auto_button_pressed):
		floating_friendly_auto_button.pressed.connect(_on_friendly_auto_button_pressed)
	_layout_left_floating_action_buttons()
	_refresh_action_buttons_state()

func _layout_left_floating_action_buttons() -> void:
	if floating_end_turn_button == null or floating_friendly_auto_button == null:
		return
	var width := maxf(120.0, left_panel.size.x - VIEW_PADDING * 2.0)
	var height := LEFT_FLOATING_BUTTON_HEIGHT
	var base_bottom := -VIEW_PADDING
	floating_end_turn_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	floating_end_turn_button.offset_left = VIEW_PADDING
	floating_end_turn_button.offset_right = VIEW_PADDING + width
	floating_end_turn_button.offset_bottom = base_bottom
	floating_end_turn_button.offset_top = base_bottom - height
	floating_friendly_auto_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	floating_friendly_auto_button.offset_left = VIEW_PADDING
	floating_friendly_auto_button.offset_right = VIEW_PADDING + width
	floating_friendly_auto_button.offset_bottom = base_bottom - (height + LEFT_FLOATING_BUTTON_GAP)
	floating_friendly_auto_button.offset_top = floating_friendly_auto_button.offset_bottom - height

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
	var setup := BattleStageSetupService.apply_stage_map_settings(board, stage_data)
	stage_background_path = str(setup.get("background_path", ""))
	has_stage_camera_config = bool(setup.get("has_camera_config", false))
	var config_variant: Variant = setup.get("camera_config", {})
	stage_camera_config = (config_variant as Dictionary).duplicate(true) if config_variant is Dictionary else {}

func _apply_stage_initial_camera_if_needed() -> void:
	var camera_result := BattleStageSetupService.compute_initial_camera(
		board,
		has_stage_camera_config,
		stage_camera_config,
		board_rect,
		left_panel.size.x,
		VIEW_PADDING,
		get_viewport_rect(),
		board_anchor
	)
	if not bool(camera_result.get("applied", false)):
		return
	board_zoom = float(camera_result.get("zoom", board_zoom))
	board_pan = camera_result.get("pan", board_pan) as Vector2
	_apply_board_transform()

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
	_fix_left_info_order()
	_refresh_action_buttons_state()

func _start_initial_deployment_phase_if_available() -> void:
	if board == null:
		return
	board.cmd_start_initial_deployment_phase()
	_refresh_action_buttons_state()

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
