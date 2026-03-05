extends Control

const EventEditorController = preload("res://scripts/ui/event_editor_controller.gd")

@onready var girl_option: OptionButton = $Margin/VBox/GirlRow/GirlOption
@onready var stage_list: VBoxContainer = $Margin/VBox/StageList
@onready var info_label: Label = $Margin/VBox/Info

var event_editor_controller: EventEditorController

func _ready() -> void:
	_setup_event_editor()
	_populate_girl_options()
	_refresh_view()

func _setup_event_editor() -> void:
	if event_editor_controller != null:
		return
	event_editor_controller = EventEditorController.new()
	event_editor_controller.setup(
		self,
		null,
		Callable(self, "_current_stage_event_config"),
		Callable(self, "_save_stage_event_config"),
		Callable(self, "_on_stage_event_saved")
	)

func _populate_girl_options() -> void:
	girl_option.clear()
	var girls := GameFlow.get_campaign_girls()
	for i in girls.size():
		var girl := girls[i]
		var label := "%s (開放 %d/%d)" % [
			str(girl.get("name", "")),
			int(girl.get("unlocked_count", 0)),
			int(girl.get("stage_count", 0))
		]
		girl_option.add_item(label, i)
		girl_option.set_item_metadata(i, str(girl.get("id", "")))
	var selected_id := GameFlow.get_selected_girl_id()
	for i in girl_option.item_count:
		if str(girl_option.get_item_metadata(i)) == selected_id:
			girl_option.select(i)
			break
	if girl_option.item_count > 0 and girl_option.selected == -1:
		girl_option.select(0)
		var fallback_id := str(girl_option.get_item_metadata(0))
		GameFlow.select_girl(fallback_id)
	if not girl_option.item_selected.is_connected(_on_girl_selected):
		girl_option.item_selected.connect(_on_girl_selected)

func _refresh_view() -> void:
	for child in stage_list.get_children():
		child.queue_free()
	var stages := GameFlow.get_selected_girl_stages()
	for stage in stages:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := int(stage.get("index", 0))
		var unlocked := bool(stage.get("unlocked", false))
		var cleared := bool(stage.get("cleared", false))
		var exists := bool(stage.get("exists", false))
		button.text = _build_stage_label(index, unlocked, cleared, exists)
		button.disabled = not unlocked or not exists
		button.pressed.connect(_on_stage_pressed.bind(index))
		row.add_child(button)
		var edit_button := Button.new()
		edit_button.text = "イベント編集"
		edit_button.custom_minimum_size = Vector2(120.0, 0.0)
		edit_button.disabled = not exists
		edit_button.pressed.connect(_on_stage_event_edit_pressed.bind(index))
		row.add_child(edit_button)
		var stage_editor_button := Button.new()
		stage_editor_button.text = "ステージ編集"
		stage_editor_button.custom_minimum_size = Vector2(120.0, 0.0)
		stage_editor_button.disabled = not exists
		stage_editor_button.pressed.connect(_on_stage_editor_pressed.bind(index))
		row.add_child(stage_editor_button)
		stage_list.add_child(row)
	_update_info_label()

func _build_stage_label(index: int, unlocked: bool, cleared: bool, exists: bool) -> String:
	var status := "LOCK"
	if unlocked:
		status = "OPEN"
	if cleared:
		status = "CLEAR"
	if not exists:
		status = "未実装"
	return "STAGE %d [%s]" % [index + 1, status]

func _update_info_label() -> void:
	var notice := GameFlow.get_stage_select_notice()
	if notice != "":
		info_label.text = notice
		return
	info_label.text = "%s を選択中。ステージ開始 / イベント編集 / ステージ編集を選んでください。" % GameFlow.get_selected_girl_name()

func _on_girl_selected(index: int) -> void:
	var girl_id := str(girl_option.get_item_metadata(index))
	if not GameFlow.select_girl(girl_id):
		return
	_refresh_view()

func _on_stage_pressed(stage_index: int) -> void:
	var started := GameFlow.start_selected_stage(stage_index)
	if started:
		return
	_update_info_label()

func _on_stage_event_edit_pressed(stage_index: int) -> void:
	var ok := GameFlow.select_stage_for_edit(stage_index)
	if not ok:
		_update_info_label()
		return
	if event_editor_controller != null:
		event_editor_controller.open()
	_update_info_label()

func _on_stage_editor_pressed(stage_index: int) -> void:
	if not GameFlow.has_method("debug_start_stage_battle"):
		info_label.text = "ステージ編集APIが見つかりません。"
		return
	var girl_id := GameFlow.get_selected_girl_id()
	var started := bool(GameFlow.debug_start_stage_battle(girl_id, stage_index))
	if started:
		return
	_update_info_label()

func _current_stage_event_config(event_key: String) -> Dictionary:
	if GameFlow.has_method("get_current_stage_event_data"):
		var value: Variant = GameFlow.get_current_stage_event_data(event_key)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}

func _save_stage_event_config(event_key: String, event_data: Dictionary) -> bool:
	if GameFlow.has_method("update_current_stage_event_data"):
		return bool(GameFlow.update_current_stage_event_data(event_key, event_data))
	return false

func _on_stage_event_saved(message: String) -> void:
	info_label.text = message
