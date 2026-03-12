extends Control

const EventEditorController = preload("res://scripts/ui/event_editor_controller.gd")
const TITLE_SCENE_PATH := "res://scenes/flow/title_scene.tscn"
const GIRL_SLOT_COUNT := 5
const STAGES_PER_GIRL := 2

@onready var back_button: Button = $Margin/VBox/TopRow/BackButton
@onready var rows_container: VBoxContainer = $Margin/VBox/Scroll/Rows
@onready var notice_label: Label = $Margin/VBox/Notice

var event_editor_controller: EventEditorController

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_setup_event_editor()
	_build_rows()

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

func _build_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	var girls := GameFlow.get_campaign_girls()
	if girls.is_empty():
		notice_label.text = "キャラクターデータがありません。"
		return
	for girl_index in GIRL_SLOT_COUNT:
		var girl: Dictionary = girls[girl_index] if girl_index < girls.size() else {}
		var girl_id := str(girl.get("id", ""))
		var girl_name := str(girl.get("name", "未設定"))
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		rows_container.add_child(section)

		var header := Label.new()
		header.text = girl_name if girl_id != "" else "未設定スロット"
		section.add_child(header)

		for stage_index in STAGES_PER_GIRL:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 8)
			section.add_child(row)

			var label := Label.new()
			label.custom_minimum_size = Vector2(140.0, 0.0)
			label.text = "STAGE %d" % (stage_index + 1)
			row.add_child(label)

			var event_button := Button.new()
			event_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			event_button.text = "イベントデバッグ"
			row.add_child(event_button)

			var stage_button := Button.new()
			stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stage_button.text = "ステージデバッグ"
			row.add_child(stage_button)

			var enabled := _is_debug_stage_available(girl_id, stage_index)
			event_button.disabled = not enabled
			stage_button.disabled = not enabled
			if enabled:
				event_button.pressed.connect(_on_event_debug_pressed.bind(girl_id, stage_index))
				stage_button.pressed.connect(_on_stage_debug_pressed.bind(girl_id, stage_index))

func _is_debug_stage_available(girl_id: String, stage_index: int) -> bool:
	if girl_id == "":
		return false
	if not GameFlow.has_method("get_girl_stages"):
		return false
	var entries: Variant = GameFlow.get_girl_stages(girl_id)
	if not (entries is Array):
		return false
	var stages := entries as Array
	if stage_index < 0 or stage_index >= stages.size():
		return false
	var value: Variant = stages[stage_index]
	if not (value is Dictionary):
		return false
	return bool((value as Dictionary).get("exists", false))

func _on_event_debug_pressed(girl_id: String, stage_index: int) -> void:
	if not GameFlow.select_girl(girl_id):
		notice_label.text = "キャラクター選択に失敗しました。"
		return
	var ok := GameFlow.select_stage_for_edit(stage_index)
	if not ok:
		notice_label.text = GameFlow.get_stage_select_notice()
		return
	if event_editor_controller != null:
		event_editor_controller.open()
	notice_label.text = "%s / STAGE %d のイベントを編集中。" % [GameFlow.get_selected_girl_name(), stage_index + 1]

func _on_stage_debug_pressed(girl_id: String, stage_index: int) -> void:
	if not GameFlow.has_method("debug_start_stage_battle"):
		notice_label.text = "ステージデバッグAPIが見つかりません。"
		return
	var started := bool(GameFlow.debug_start_stage_battle(girl_id, stage_index))
	if started:
		return
	notice_label.text = GameFlow.get_stage_select_notice()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)

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
	notice_label.text = message
