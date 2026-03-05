extends RefCounted
class_name BattleDebugToolsController

const BoardRendererService = preload("res://scripts/board/board_renderer_service.gd")
const BgmEditorController = preload("res://scripts/ui/bgm_editor_controller.gd")
const EventEditorController = preload("res://scripts/ui/event_editor_controller.gd")

var canvas_layer: CanvasLayer
var board: HexBoard
var hud_controller: BattleHudController

var terrain_color_editor_button: Button
var terrain_color_editor_dialog: AcceptDialog
var fog_debug_button: Button
var unit_param_editor_button: Button
var unit_param_editor_dialog: AcceptDialog
var enemy_ai_production_editor_button: Button
var enemy_ai_production_editor_dialog: AcceptDialog

var terrain_color_buttons := {}
var terrain_cost_spins := {}
var is_fog_debug_revealed := false
var unit_param_controls := {}
var unit_param_class_select: OptionButton
var unit_param_new_class_input: LineEdit
var unit_param_tiled_hint: TextEdit
var enemy_ai_production_checks := {}
var enemy_ai_production_enable_check: CheckBox
var bgm_editor_controller: BgmEditorController
var event_editor_controller: EventEditorController

func setup(layer: CanvasLayer, board_node: HexBoard, hud: BattleHudController) -> void:
	canvas_layer = layer
	board = board_node
	hud_controller = hud
	_ensure_terrain_color_editor()
	_ensure_fog_debug_button()
	_ensure_bgm_editor()
	_ensure_event_editor()
	_ensure_unit_param_editor()
	_ensure_enemy_ai_production_editor()

func _ensure_terrain_color_editor() -> void:
	if hud_controller != null:
		terrain_color_editor_button = hud_controller.ensure_button(
			"terrain_color_editor",
			"TerrainColorEditorButton",
			"地形色",
			Vector2(96.0, 34.0),
			Callable(self, "_on_open_terrain_color_editor_pressed")
		)
	if hud_controller != null:
		hud_controller.layout_buttons()

	if terrain_color_editor_dialog == null:
		var existing := canvas_layer.get_node_or_null("TerrainColorEditorDialog")
		terrain_color_editor_dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if terrain_color_editor_dialog == null:
		terrain_color_editor_dialog = AcceptDialog.new()
		terrain_color_editor_dialog.name = "TerrainColorEditorDialog"
		terrain_color_editor_dialog.title = "地形色エディタ"
		terrain_color_editor_dialog.dialog_text = ""
		canvas_layer.add_child(terrain_color_editor_dialog)

	var existing_root := terrain_color_editor_dialog.get_node_or_null("Root")
	if existing_root != null:
		return
	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "地形色エディタ"
	root.add_child(title)

	var terrain_names: Array[String] = []
	for key in BoardRendererService.TERRAIN_COLORS.keys():
		terrain_names.append(str(key))
	terrain_names.sort()
	for terrain in terrain_names:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = terrain
		name_label.custom_minimum_size = Vector2(80.0, 0.0)
		row.add_child(name_label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(64.0, 24.0)
		picker.color = _terrain_editor_color_for(terrain)
		picker.color_changed.connect(_on_terrain_color_changed.bind(terrain))
		row.add_child(picker)
		var cost_label := Label.new()
		cost_label.text = "コスト"
		cost_label.custom_minimum_size = Vector2(48.0, 0.0)
		row.add_child(cost_label)
		var cost_spin := SpinBox.new()
		cost_spin.min_value = 1.0
		cost_spin.max_value = 99.0
		cost_spin.step = 1.0
		cost_spin.custom_minimum_size = Vector2(72.0, 0.0)
		cost_spin.value = float(_terrain_editor_cost_for(terrain))
		if board != null and board.has_method("query_is_terrain_impassable") and bool(board.query_is_terrain_impassable(terrain)):
			cost_spin.editable = false
			cost_spin.tooltip_text = "通行不可地形のため変更できません。"
		else:
			cost_spin.value_changed.connect(_on_terrain_move_cost_changed.bind(terrain))
		row.add_child(cost_spin)
		terrain_color_buttons[terrain] = picker
		terrain_cost_spins[terrain] = cost_spin
		root.add_child(row)

	var reset_button := Button.new()
	reset_button.text = "地形設定をリセット"
	reset_button.pressed.connect(_on_reset_terrain_colors_pressed)
	root.add_child(reset_button)
	terrain_color_editor_dialog.add_child(root)

func _ensure_fog_debug_button() -> void:
	if hud_controller != null:
		fog_debug_button = hud_controller.ensure_button(
			"fog_debug",
			"FogDebugButton",
			"",
			Vector2(110.0, 34.0),
			Callable(self, "_on_fog_debug_button_pressed")
		)
	_update_fog_debug_button_text()
	if hud_controller != null:
		hud_controller.layout_buttons()

func _on_fog_debug_button_pressed() -> void:
	is_fog_debug_revealed = not is_fog_debug_revealed
	if board != null and board.has_method("set_debug_reveal_all"):
		board.set_debug_reveal_all(is_fog_debug_revealed)
	_update_fog_debug_button_text()

func _update_fog_debug_button_text() -> void:
	if fog_debug_button == null:
		return
	var text := "霧:OFF" if is_fog_debug_revealed else "霧:ON"
	fog_debug_button.text = text
	if hud_controller != null:
		hud_controller.set_button_text("fog_debug", text)

func _ensure_bgm_editor() -> void:
	if bgm_editor_controller == null:
		bgm_editor_controller = BgmEditorController.new()
		bgm_editor_controller.setup(
			canvas_layer,
			hud_controller,
			Callable(self, "_current_stage_audio_config"),
			Callable(self, "_save_stage_audio_config"),
			Callable(self, "_on_stage_audio_saved")
		)
	if hud_controller != null:
		hud_controller.layout_buttons()

func _current_stage_audio_config() -> Dictionary:
	var game_flow := _game_flow()
	if game_flow != null and game_flow.has_method("get_current_stage_audio_config"):
		var audio_variant: Variant = game_flow.get_current_stage_audio_config()
		if audio_variant is Dictionary:
			return (audio_variant as Dictionary).duplicate(true)
	var stage_variant: Variant = game_flow.get_current_stage_data() if game_flow != null and game_flow.has_method("get_current_stage_data") else {}
	var stage: Dictionary = stage_variant if stage_variant is Dictionary else {}
	var audio_variant_fallback: Variant = stage.get("audio", {})
	return audio_variant_fallback if audio_variant_fallback is Dictionary else {}

func _save_stage_audio_config(next_audio: Dictionary) -> bool:
	var game_flow := _game_flow()
	if game_flow != null and game_flow.has_method("update_current_stage_audio"):
		return bool(game_flow.update_current_stage_audio(next_audio))
	return false

func _on_stage_audio_saved() -> void:
	if board == null or not board.has_method("query_current_faction"):
		return
	var game_flow := _game_flow()
	if game_flow != null and game_flow.has_method("play_battle_turn_bgm"):
		var current_faction := str(board.query_current_faction())
		var ai_faction := str(board.get("ai_faction"))
		game_flow.play_battle_turn_bgm(current_faction, ai_faction)

func _ensure_event_editor() -> void:
	if event_editor_controller == null:
		event_editor_controller = EventEditorController.new()
		event_editor_controller.setup(
			canvas_layer,
			hud_controller,
			Callable(self, "_current_stage_event_config"),
			Callable(self, "_save_stage_event_config"),
			Callable(self, "_on_stage_event_saved")
		)
	if hud_controller != null:
		hud_controller.layout_buttons()

func _current_stage_event_config(event_key: String) -> Dictionary:
	var game_flow := _game_flow()
	if game_flow != null and game_flow.has_method("get_current_stage_event_data"):
		var value: Variant = game_flow.get_current_stage_event_data(event_key)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	var stage_variant: Variant = game_flow.get_current_stage_data() if game_flow != null and game_flow.has_method("get_current_stage_data") else {}
	if not (stage_variant is Dictionary):
		return {}
	var stage := stage_variant as Dictionary
	var event_value: Variant = stage.get(event_key, {})
	return (event_value as Dictionary).duplicate(true) if event_value is Dictionary else {}

func _save_stage_event_config(event_key: String, event_data: Dictionary) -> bool:
	var game_flow := _game_flow()
	if game_flow != null and game_flow.has_method("update_current_stage_event_data"):
		return bool(game_flow.update_current_stage_event_data(event_key, event_data))
	return false

func _on_stage_event_saved(message: String) -> void:
	if board != null and board.has_method("cmd_update_status"):
		board.cmd_update_status(message)

func _ensure_unit_param_editor() -> void:
	if hud_controller != null:
		unit_param_editor_button = hud_controller.ensure_button(
			"unit_param_editor",
			"UnitParamEditorButton",
			"ユニット設定",
			Vector2(120.0, 34.0),
			Callable(self, "_on_open_unit_param_editor_pressed")
		)
	if hud_controller != null:
		hud_controller.layout_buttons()

	if unit_param_editor_dialog == null:
		var existing := canvas_layer.get_node_or_null("UnitParamEditorDialog")
		unit_param_editor_dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if unit_param_editor_dialog == null:
		unit_param_editor_dialog = AcceptDialog.new()
		unit_param_editor_dialog.name = "UnitParamEditorDialog"
		unit_param_editor_dialog.title = "ユニットパラメータ"
		unit_param_editor_dialog.dialog_text = ""
		canvas_layer.add_child(unit_param_editor_dialog)
		unit_param_editor_dialog.confirmed.connect(_on_unit_param_editor_confirmed)

	var existing_root := unit_param_editor_dialog.get_node_or_null("ContentScroll/Root")
	if existing_root != null:
		return

	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	unit_param_editor_dialog.add_child(scroll)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)

	var class_row := HBoxContainer.new()
	var class_label := Label.new()
	class_label.text = "兵科"
	class_label.custom_minimum_size = Vector2(90.0, 0.0)
	class_row.add_child(class_label)
	unit_param_class_select = OptionButton.new()
	unit_param_class_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_param_class_select.item_selected.connect(_on_unit_param_class_selected)
	class_row.add_child(unit_param_class_select)
	root.add_child(class_row)

	var add_row := HBoxContainer.new()
	var add_label := Label.new()
	add_label.text = "追加"
	add_label.custom_minimum_size = Vector2(90.0, 0.0)
	add_row.add_child(add_label)
	unit_param_new_class_input = LineEdit.new()
	unit_param_new_class_input.placeholder_text = "new_unit_class"
	unit_param_new_class_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(unit_param_new_class_input)
	var add_button := Button.new()
	add_button.text = "新規追加"
	add_button.pressed.connect(_on_unit_param_add_pressed)
	add_row.add_child(add_button)
	root.add_child(add_row)

	var tiled_label := Label.new()
	tiled_label.text = "Tiled配置設定"
	root.add_child(tiled_label)
	unit_param_tiled_hint = TextEdit.new()
	unit_param_tiled_hint.custom_minimum_size = Vector2(0.0, 96.0)
	unit_param_tiled_hint.editable = false
	unit_param_tiled_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(unit_param_tiled_hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)

	_add_unit_param_spin(grid, "name", "名前", true)
	_add_unit_param_spin(grid, "cost", "コスト")
	_add_unit_param_spin(grid, "hp", "HP")
	_add_unit_param_spin(grid, "atk", "攻撃")
	_add_unit_param_spin(grid, "move", "移動")
	_add_unit_param_spin(grid, "vision", "視界")
	_add_unit_param_spin(grid, "min_range", "最小射程")
	_add_unit_param_spin(grid, "range", "最大射程")
	_add_unit_param_spin(grid, "delivery_score", "輸送スコア")
	_add_unit_param_check(grid, "can_attack", "攻撃可")
	_add_unit_param_check(grid, "is_transport", "輸送扱い")
	_add_unit_param_spin(grid, "icon", "アイコン", true)
	_add_unit_param_spin(grid, "icon_player", "味方アイコン", true)
	_add_unit_param_spin(grid, "icon_enemy", "敵アイコン", true)

	scroll.add_child(root)
	_refresh_unit_param_tiled_hint()

func _ensure_enemy_ai_production_editor() -> void:
	if hud_controller != null:
		enemy_ai_production_editor_button = hud_controller.ensure_button(
			"enemy_ai_production_editor",
			"EnemyAIProductionEditorButton",
			"敵生産AI",
			Vector2(120.0, 34.0),
			Callable(self, "_on_open_enemy_ai_production_editor_pressed")
		)
	if hud_controller != null:
		hud_controller.layout_buttons()

	if enemy_ai_production_editor_dialog == null:
		var existing := canvas_layer.get_node_or_null("EnemyAIProductionEditorDialog")
		enemy_ai_production_editor_dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if enemy_ai_production_editor_dialog == null:
		enemy_ai_production_editor_dialog = AcceptDialog.new()
		enemy_ai_production_editor_dialog.name = "EnemyAIProductionEditorDialog"
		enemy_ai_production_editor_dialog.title = "敵AI生産ユニット"
		enemy_ai_production_editor_dialog.dialog_text = ""
		canvas_layer.add_child(enemy_ai_production_editor_dialog)
		enemy_ai_production_editor_dialog.confirmed.connect(_on_enemy_ai_production_editor_confirmed)
	var ok_button := enemy_ai_production_editor_dialog.get_ok_button()
	if ok_button != null:
		ok_button.text = "保存"

	var existing_root := enemy_ai_production_editor_dialog.get_node_or_null("Root")
	if existing_root != null:
		return

	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	enemy_ai_production_editor_dialog.add_child(root)

	var help := Label.new()
	help.text = "敵AIの生産候補をステージごとに指定します。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(help)

	enemy_ai_production_enable_check = CheckBox.new()
	enemy_ai_production_enable_check.name = "EnableLimitCheck"
	enemy_ai_production_enable_check.text = "このステージで敵生産を制限する"
	enemy_ai_production_enable_check.toggled.connect(_on_enemy_ai_production_enable_toggled)
	root.add_child(enemy_ai_production_enable_check)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	var all_on := Button.new()
	all_on.text = "全選択"
	all_on.pressed.connect(_on_enemy_ai_production_select_all_pressed)
	actions.add_child(all_on)

	var all_off := Button.new()
	all_off.text = "全解除"
	all_off.pressed.connect(_on_enemy_ai_production_clear_all_pressed)
	actions.add_child(all_off)

	var scroll := ScrollContainer.new()
	scroll.name = "ClassScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(420.0, 260.0)
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "ClassList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

func _add_unit_param_spin(parent: GridContainer, key: String, label_text: String, is_text: bool = false) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	if is_text:
		var line := LineEdit.new()
		line.placeholder_text = ""
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_param_controls[key] = line
		parent.add_child(line)
		return
	var spin := SpinBox.new()
	spin.step = 1.0
	spin.min_value = 0.0
	spin.max_value = 999.0
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_param_controls[key] = spin
	parent.add_child(spin)

func _add_unit_param_check(parent: GridContainer, key: String, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var check := CheckBox.new()
	check.text = ""
	unit_param_controls[key] = check
	parent.add_child(check)

func _on_open_unit_param_editor_pressed() -> void:
	_refresh_unit_param_class_select()
	_refresh_unit_param_tiled_hint()
	_load_unit_param_from_selected_class()
	if unit_param_editor_dialog != null:
		var viewport_size := canvas_layer.get_viewport().get_visible_rect().size
		var width := int(clampf(viewport_size.x * 0.82, 320.0, 520.0))
		var height := int(clampf(viewport_size.y * 0.82, 320.0, 640.0))
		unit_param_editor_dialog.popup_centered(Vector2i(width, height))

func _refresh_unit_param_class_select() -> void:
	if unit_param_class_select == null or board == null or not board.has_method("get_unit_catalog_classes"):
		return
	var classes: Array[String] = board.get_unit_catalog_classes()
	var previous := unit_param_class_select.get_item_text(unit_param_class_select.selected) if unit_param_class_select.item_count > 0 and unit_param_class_select.selected >= 0 else ""
	unit_param_class_select.clear()
	for unit_class in classes:
		unit_param_class_select.add_item(unit_class)
	if unit_param_class_select.item_count == 0:
		return
	var selected_idx := 0
	for i in unit_param_class_select.item_count:
		if unit_param_class_select.get_item_text(i) == previous:
			selected_idx = i
			break
	unit_param_class_select.select(selected_idx)

func _on_unit_param_class_selected(_index: int) -> void:
	_load_unit_param_from_selected_class()
	_refresh_unit_param_tiled_hint()

func _on_unit_param_add_pressed() -> void:
	if board == null or not board.has_method("update_unit_catalog_entry"):
		return
	if unit_param_new_class_input == null:
		return
	var raw := unit_param_new_class_input.text.strip_edges().to_lower()
	if raw == "":
		return
	var unit_class := ""
	for ch in raw:
		var c := str(ch)
		var is_lower := c >= "a" and c <= "z"
		var is_digit := c >= "0" and c <= "9"
		if is_lower or is_digit or c == "_":
			unit_class += c
	if unit_class == "":
		return
	var existing: Dictionary = {}
	if board.has_method("get_unit_catalog_entry"):
		existing = board.get_unit_catalog_entry(unit_class)
	if existing.is_empty():
		var default_entry := {
			"unit_class": unit_class,
			"name": unit_class.capitalize(),
			"cost": 1,
			"hp": 3,
			"atk": 1,
			"move": 3,
			"vision": 3,
			"min_range": 1,
			"range": 1,
			"can_attack": true,
			"is_transport": false,
			"delivery_score": 100,
			"icon": "res://icon.svg",
			"icon_player": "",
			"icon_enemy": ""
		}
		board.update_unit_catalog_entry(unit_class, default_entry)
		if board.has_method("save_unit_catalog"):
			board.save_unit_catalog()
	_refresh_unit_param_class_select()
	_refresh_unit_param_tiled_hint()
	_select_unit_param_class(unit_class)
	_load_unit_param_from_selected_class()
	unit_param_new_class_input.text = ""

func _select_unit_param_class(unit_class: String) -> void:
	if unit_param_class_select == null:
		return
	for i in unit_param_class_select.item_count:
		if unit_param_class_select.get_item_text(i) == unit_class:
			unit_param_class_select.select(i)
			return

func _selected_unit_param_class() -> String:
	if unit_param_class_select == null or unit_param_class_select.item_count == 0:
		return ""
	var idx := maxi(0, unit_param_class_select.selected)
	return unit_param_class_select.get_item_text(idx)

func _load_unit_param_from_selected_class() -> void:
	var unit_class := _selected_unit_param_class()
	if unit_class == "" or board == null or not board.has_method("get_unit_catalog_entry"):
		return
	var entry: Dictionary = board.get_unit_catalog_entry(unit_class)
	_set_unit_param_control_value("name", str(entry.get("name", unit_class.capitalize())))
	_set_unit_param_control_value("cost", int(entry.get("cost", 0)))
	_set_unit_param_control_value("hp", int(entry.get("hp", 1)))
	_set_unit_param_control_value("atk", int(entry.get("atk", 0)))
	_set_unit_param_control_value("move", int(entry.get("move", 0)))
	_set_unit_param_control_value("vision", int(entry.get("vision", 3)))
	_set_unit_param_control_value("min_range", int(entry.get("min_range", 1)))
	_set_unit_param_control_value("range", int(entry.get("range", 1)))
	_set_unit_param_control_value("delivery_score", int(entry.get("delivery_score", 100)))
	_set_unit_param_control_value("can_attack", bool(entry.get("can_attack", true)))
	_set_unit_param_control_value("is_transport", bool(entry.get("is_transport", false)))
	_set_unit_param_control_value("icon", str(entry.get("icon", "")))
	_set_unit_param_control_value("icon_player", str(entry.get("icon_player", "")))
	_set_unit_param_control_value("icon_enemy", str(entry.get("icon_enemy", "")))

func _set_unit_param_control_value(key: String, value: Variant) -> void:
	if not unit_param_controls.has(key):
		return
	var control: Variant = unit_param_controls[key]
	if control is SpinBox:
		(control as SpinBox).value = float(value)
	elif control is CheckBox:
		(control as CheckBox).button_pressed = bool(value)
	elif control is LineEdit:
		(control as LineEdit).text = str(value)

func _get_unit_param_control_value(key: String, fallback: Variant) -> Variant:
	if not unit_param_controls.has(key):
		return fallback
	var control: Variant = unit_param_controls[key]
	if control is SpinBox:
		return int((control as SpinBox).value)
	if control is CheckBox:
		return (control as CheckBox).button_pressed
	if control is LineEdit:
		return str((control as LineEdit).text).strip_edges()
	return fallback

func _on_unit_param_editor_confirmed() -> void:
	var unit_class := _selected_unit_param_class()
	if unit_class == "" or board == null or not board.has_method("update_unit_catalog_entry"):
		return
	var next_entry := {
		"unit_class": unit_class,
		"name": _get_unit_param_control_value("name", unit_class.capitalize()),
		"cost": _get_unit_param_control_value("cost", 0),
		"hp": _get_unit_param_control_value("hp", 1),
		"atk": _get_unit_param_control_value("atk", 0),
		"move": _get_unit_param_control_value("move", 0),
		"vision": _get_unit_param_control_value("vision", 3),
		"min_range": _get_unit_param_control_value("min_range", 1),
		"range": _get_unit_param_control_value("range", 1),
		"can_attack": _get_unit_param_control_value("can_attack", true),
		"is_transport": _get_unit_param_control_value("is_transport", false),
		"delivery_score": _get_unit_param_control_value("delivery_score", 100),
		"icon": _get_unit_param_control_value("icon", ""),
		"icon_player": _get_unit_param_control_value("icon_player", ""),
		"icon_enemy": _get_unit_param_control_value("icon_enemy", "")
	}
	board.update_unit_catalog_entry(unit_class, next_entry)
	if board.has_method("save_unit_catalog"):
		board.save_unit_catalog()
	_refresh_unit_param_tiled_hint()

func _refresh_unit_param_tiled_hint() -> void:
	if unit_param_tiled_hint == null:
		return
	var selected_class := _selected_unit_param_class()
	if selected_class == "":
		unit_param_tiled_hint.text = ""
		return
	unit_param_tiled_hint.text = "Tiled object custom property\nkey: unit_class\nvalue: %s" % selected_class

func _on_open_terrain_color_editor_pressed() -> void:
	_sync_terrain_color_button_values()
	_sync_terrain_cost_spin_values()
	if terrain_color_editor_dialog != null:
		terrain_color_editor_dialog.popup_centered(Vector2i(520, 420))

func _sync_terrain_color_button_values() -> void:
	for terrain in terrain_color_buttons.keys():
		var button_variant: Variant = terrain_color_buttons[terrain]
		if button_variant is ColorPickerButton:
			var button := button_variant as ColorPickerButton
			button.color = _terrain_editor_color_for(str(terrain))

func _sync_terrain_cost_spin_values() -> void:
	for terrain in terrain_cost_spins.keys():
		var spin_variant: Variant = terrain_cost_spins[terrain]
		if spin_variant is SpinBox:
			var spin := spin_variant as SpinBox
			spin.value = float(_terrain_editor_cost_for(str(terrain)))

func _terrain_editor_color_for(terrain: String) -> Color:
	if board != null:
		return board.query_terrain_base_color(terrain)
	var fallback: Variant = BoardRendererService.TERRAIN_COLORS.get(terrain, Color(0.16, 0.18, 0.22))
	if fallback is Color:
		return fallback as Color
	return Color(0.16, 0.18, 0.22)

func _terrain_editor_cost_for(terrain: String) -> int:
	if board != null and board.has_method("query_terrain_move_cost"):
		return int(board.query_terrain_move_cost(terrain))
	return 1

func _on_terrain_color_changed(color: Color, terrain: String) -> void:
	if board == null or not board.has_method("set_terrain_base_color"):
		return
	board.set_terrain_base_color(terrain, color)
	if board.has_method("save_terrain_base_colors"):
		board.save_terrain_base_colors()

func _on_terrain_move_cost_changed(value: float, terrain: String) -> void:
	if board == null or not board.has_method("set_terrain_move_cost"):
		return
	board.set_terrain_move_cost(terrain, int(value))
	if board.has_method("save_terrain_base_colors"):
		board.save_terrain_base_colors()

func _on_reset_terrain_colors_pressed() -> void:
	if board != null and board.has_method("clear_all_terrain_base_colors"):
		board.clear_all_terrain_base_colors()
		if board.has_method("clear_all_terrain_move_costs"):
			board.clear_all_terrain_move_costs()
		if board.has_method("save_terrain_base_colors"):
			board.save_terrain_base_colors()
	_sync_terrain_color_button_values()
	_sync_terrain_cost_spin_values()

func _on_open_enemy_ai_production_editor_pressed() -> void:
	_refresh_enemy_ai_production_editor()
	if enemy_ai_production_editor_dialog != null:
		enemy_ai_production_editor_dialog.popup_centered(Vector2i(520, 520))

func _refresh_enemy_ai_production_editor() -> void:
	var class_list := _enemy_ai_production_class_list()
	if class_list == null:
		return
	for child in class_list.get_children():
		child.queue_free()
	enemy_ai_production_checks.clear()

	var classes: Array[String] = []
	if board != null and board.has_method("get_unit_catalog_classes"):
		classes = board.get_unit_catalog_classes()
	classes.sort()

	for unit_class in classes:
		var check := CheckBox.new()
		check.text = unit_class
		class_list.add_child(check)
		enemy_ai_production_checks[unit_class] = check

	var cfg := _current_stage_enemy_ai_production_config()
	var enabled := bool(cfg.get("enabled", false))
	var allowed := _normalize_unit_class_list(cfg.get("classes", []))
	if enemy_ai_production_enable_check != null:
		enemy_ai_production_enable_check.button_pressed = enabled
	for unit_class in enemy_ai_production_checks.keys():
		var check_variant: Variant = enemy_ai_production_checks[unit_class]
		if not (check_variant is CheckBox):
			continue
		var check := check_variant as CheckBox
		check.button_pressed = allowed.has(str(unit_class))
	_update_enemy_ai_production_check_editability()

func _enemy_ai_production_class_list() -> VBoxContainer:
	if enemy_ai_production_editor_dialog == null:
		return null
	var node := enemy_ai_production_editor_dialog.get_node_or_null("Root/ClassScroll/ClassList")
	return node as VBoxContainer if node is VBoxContainer else null

func _current_stage_enemy_ai_production_config() -> Dictionary:
	var game_flow := _game_flow()
	var stage_variant: Variant = game_flow.get_current_stage_data() if game_flow != null and game_flow.has_method("get_current_stage_data") else {}
	if not (stage_variant is Dictionary):
		return {"enabled": false, "classes": []}
	var stage := stage_variant as Dictionary
	var ai_variant: Variant = stage.get("ai_production", {})
	if not (ai_variant is Dictionary):
		return {"enabled": false, "classes": []}
	var ai_production := ai_variant as Dictionary
	if not ai_production.has("enemy"):
		return {"enabled": false, "classes": []}
	var classes := _normalize_unit_class_list(ai_production.get("enemy", []))
	return {"enabled": true, "classes": classes}

func _normalize_unit_class_list(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (raw is Array):
		return result
	var seen := {}
	for item in (raw as Array):
		var unit_class := str(item).strip_edges().to_lower()
		if unit_class == "" or seen.has(unit_class):
			continue
		seen[unit_class] = true
		result.append(unit_class)
	return result

func _on_enemy_ai_production_enable_toggled(_pressed: bool) -> void:
	_update_enemy_ai_production_check_editability()

func _update_enemy_ai_production_check_editability() -> void:
	var enabled := enemy_ai_production_enable_check != null and enemy_ai_production_enable_check.button_pressed
	for check_variant in enemy_ai_production_checks.values():
		if check_variant is CheckBox:
			(check_variant as CheckBox).disabled = not enabled

func _on_enemy_ai_production_select_all_pressed() -> void:
	var enabled := enemy_ai_production_enable_check != null and enemy_ai_production_enable_check.button_pressed
	if not enabled:
		return
	for check_variant in enemy_ai_production_checks.values():
		if check_variant is CheckBox:
			(check_variant as CheckBox).button_pressed = true

func _on_enemy_ai_production_clear_all_pressed() -> void:
	var enabled := enemy_ai_production_enable_check != null and enemy_ai_production_enable_check.button_pressed
	if not enabled:
		return
	for check_variant in enemy_ai_production_checks.values():
		if check_variant is CheckBox:
			(check_variant as CheckBox).button_pressed = false

func _on_enemy_ai_production_editor_confirmed() -> void:
	var game_flow := _game_flow()
	if game_flow == null or not game_flow.has_method("update_current_stage_enemy_ai_production"):
		if board != null and board.has_method("cmd_update_status"):
			board.cmd_update_status("ステージ保存APIが見つからないため、敵生産AI設定を保存できません。")
		return
	var enabled := enemy_ai_production_enable_check != null and enemy_ai_production_enable_check.button_pressed
	var selected: Array[String] = []
	if enabled:
		for key in enemy_ai_production_checks.keys():
			var check_variant: Variant = enemy_ai_production_checks[key]
			if check_variant is CheckBox and bool((check_variant as CheckBox).button_pressed):
				selected.append(str(key))
	selected.sort()
	var ok := bool(game_flow.update_current_stage_enemy_ai_production(selected, enabled))
	if not ok:
		if board != null and board.has_method("cmd_update_status"):
			board.cmd_update_status("敵生産AI設定の保存に失敗しました。")
		return
	if board != null and board.has_method("apply_stage_ai_production"):
		var stage_variant: Variant = game_flow.get_current_stage_data() if game_flow.has_method("get_current_stage_data") else {}
		if stage_variant is Dictionary:
			board.apply_stage_ai_production(stage_variant as Dictionary)
	if board != null and board.has_method("cmd_update_status"):
		board.cmd_update_status("敵生産AI設定を保存しました。")

func _game_flow() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree := loop as SceneTree
	if tree.root == null:
		return null
	var node := tree.root.get_node_or_null("GameFlow")
	return node as Node if node is Node else null
