extends Control

@onready var girl_option: OptionButton = $Margin/VBox/GirlRow/GirlOption
@onready var stage_list: VBoxContainer = $Margin/VBox/StageList
@onready var info_label: Label = $Margin/VBox/Info

func _ready() -> void:
	_populate_girl_options()
	_refresh_view()

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
		var button := Button.new()
		var index := int(stage.get("index", 0))
		var unlocked := bool(stage.get("unlocked", false))
		var cleared := bool(stage.get("cleared", false))
		var exists := bool(stage.get("exists", false))
		button.text = _build_stage_label(index, unlocked, cleared, exists)
		button.disabled = not unlocked or not exists
		button.pressed.connect(_on_stage_pressed.bind(index))
		stage_list.add_child(button)
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
	info_label.text = "%s を選択中。開放済みステージを選んでください。" % GameFlow.get_selected_girl_name()

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
