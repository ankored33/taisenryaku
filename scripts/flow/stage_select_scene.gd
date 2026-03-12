extends Control

const EventEditorController = preload("res://scripts/ui/event_editor_controller.gd")
const CHARACTER_PANEL_COUNT := 5
const PORTRAIT_RATIO := 600.0 / 1280.0

@onready var character_scroll: ScrollContainer = $Margin/VBox/CharacterScroll
@onready var character_row: HBoxContainer = $Margin/VBox/CharacterScroll/CharacterRow

var event_editor_controller: EventEditorController
var overlay_girl_id := ""
var character_cards: Array[Button] = []
var card_overlay_by_girl := {}

func _ready() -> void:
	_setup_event_editor()
	_build_character_panels()
	resized.connect(_apply_panel_layout)
	get_viewport().size_changed.connect(_apply_panel_layout)
	call_deferred("_apply_panel_layout")
	_close_stage_overlay()

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

func _build_character_panels() -> void:
	for child in character_row.get_children():
		child.queue_free()
	character_cards.clear()
	card_overlay_by_girl.clear()
	var girls := GameFlow.get_campaign_girls()
	var selected_id := GameFlow.get_selected_girl_id()
	for i in CHARACTER_PANEL_COUNT:
		var girl: Dictionary = girls[i] if i < girls.size() else {}
		var card := _create_character_card(i, girl)
		character_row.add_child(card)
		character_cards.append(card)
	_refresh_character_card_states(selected_id)

func _create_character_card(slot_index: int, girl: Dictionary) -> Button:
	var card := Button.new()
	card.size_flags_horizontal = 0
	card.size_flags_vertical = 0
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.text = ""

	var has_girl := not girl.is_empty()
	var girl_id := str(girl.get("id", ""))
	var girl_name := str(girl.get("name", "未設定"))

	card.set_meta("girl_id", girl_id)
	card.disabled = not has_girl
	if has_girl:
		card.pressed.connect(_on_character_panel_pressed.bind(girl_id, girl_name))

	var root := Control.new()
	root.layout_mode = 1
	root.anchors_preset = PRESET_FULL_RECT
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(root)

	var portrait := PanelContainer.new()
	portrait.layout_mode = 1
	portrait.anchors_preset = PRESET_FULL_RECT
	portrait.anchor_right = 1.0
	portrait.anchor_bottom = 1.0
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait)

	var portrait_path := str(girl.get("portrait", "")).strip_edges()
	if has_girl and portrait_path != "" and ResourceLoader.exists(portrait_path):
		var texture := load(portrait_path) as Texture2D
		if texture != null:
			var texture_rect := TextureRect.new()
			texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			texture_rect.anchors_preset = PRESET_FULL_RECT
			texture_rect.anchor_right = 1.0
			texture_rect.anchor_bottom = 1.0
			texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			texture_rect.texture = texture
			portrait.add_child(texture_rect)
	else:
		var fallback := ColorRect.new()
		fallback.layout_mode = 1
		fallback.anchors_preset = PRESET_FULL_RECT
		fallback.anchor_right = 1.0
		fallback.anchor_bottom = 1.0
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.color = Color.from_hsv(fmod(0.09 * float(slot_index + 1), 1.0), 0.45, 0.42)
		portrait.add_child(fallback)

		var placeholder := Label.new()
		placeholder.layout_mode = 1
		placeholder.anchors_preset = PRESET_CENTER
		placeholder.anchor_left = 0.5
		placeholder.anchor_top = 0.5
		placeholder.anchor_right = 0.5
		placeholder.anchor_bottom = 0.5
		placeholder.offset_left = -90.0
		placeholder.offset_top = -18.0
		placeholder.offset_right = 90.0
		placeholder.offset_bottom = 18.0
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder.text = "NO IMAGE" if has_girl else "COMING SOON"
		portrait.add_child(placeholder)

	var overlay := PanelContainer.new()
	overlay.visible = false
	overlay.layout_mode = 1
	overlay.anchors_preset = PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.add_child(overlay)

	var overlay_root := VBoxContainer.new()
	overlay_root.layout_mode = 1
	overlay_root.anchors_preset = PRESET_FULL_RECT
	overlay_root.anchor_right = 1.0
	overlay_root.anchor_bottom = 1.0
	overlay_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay_root.add_theme_constant_override("separation", 6)
	overlay.add_child(overlay_root)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	overlay_root.add_child(header)

	var overlay_title := Label.new()
	overlay_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	overlay_title.text = "%s / STAGE" % girl_name
	header.add_child(overlay_title)

	var overlay_close := Button.new()
	overlay_close.text = "閉"
	overlay_close.custom_minimum_size = Vector2(36.0, 0.0)
	overlay_close.pressed.connect(_on_overlay_close_pressed)
	header.add_child(overlay_close)

	var stage_scroll := ScrollContainer.new()
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.horizontal_scroll_mode = 0
	overlay_root.add_child(stage_scroll)

	var stage_list := VBoxContainer.new()
	stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_list.add_theme_constant_override("separation", 6)
	stage_scroll.add_child(stage_list)

	if has_girl and girl_id != "":
		card_overlay_by_girl[girl_id] = {
			"overlay": overlay,
			"stage_list": stage_list,
			"title": overlay_title,
			"girl_name": girl_name
		}

	return card

func _apply_panel_layout() -> void:
	if character_cards.is_empty():
		return
	var available_width := character_scroll.size.x
	if available_width <= 0.0:
		available_width = character_row.size.x
	if available_width <= 0.0:
		return
	var separation := float(character_row.get_theme_constant("separation"))
	var total_separation := separation * float(CHARACTER_PANEL_COUNT - 1)
	var panel_width: float = floor((available_width - total_separation) / float(CHARACTER_PANEL_COUNT))
	panel_width = maxf(80.0, panel_width)
	var panel_height: float = floor(panel_width / PORTRAIT_RATIO)
	for card in character_cards:
		card.custom_minimum_size = Vector2(panel_width, panel_height)
	character_row.custom_minimum_size = Vector2(panel_width * float(CHARACTER_PANEL_COUNT) + total_separation, panel_height)
	character_scroll.custom_minimum_size = Vector2(0.0, panel_height)

func _refresh_character_card_states(selected_id: String) -> void:
	for card in character_cards:
		var card_id := str(card.get_meta("girl_id", ""))
		if card.disabled:
			card.modulate = Color(0.55, 0.55, 0.55, 0.85)
			continue
		if card_id == selected_id:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			card.modulate = Color(0.86, 0.86, 0.9, 1.0)

func _refresh_stage_overlay_list(target_stage_list: VBoxContainer) -> void:
	for child in target_stage_list.get_children():
		child.queue_free()
	var stages := GameFlow.get_selected_girl_stages()
	if stages.is_empty():
		var empty_label := Label.new()
		empty_label.text = "ステージが設定されていません。"
		target_stage_list.add_child(empty_label)
		return
	for stage in stages:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 0)
		target_stage_list.add_child(box)

		var index := int(stage.get("index", 0))
		var unlocked := bool(stage.get("unlocked", false))
		var cleared := bool(stage.get("cleared", false))
		var exists := bool(stage.get("exists", false))

		var start_button := Button.new()
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start_button.text = _build_stage_label(index, unlocked, cleared, exists)
		start_button.disabled = not unlocked or not exists
		start_button.pressed.connect(_on_stage_pressed.bind(index))
		box.add_child(start_button)

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
	return

func _on_character_panel_pressed(girl_id: String, girl_name: String) -> void:
	if not GameFlow.select_girl(girl_id):
		_update_info_label()
		return
	_refresh_character_card_states(girl_id)
	_open_stage_overlay_for(girl_id, girl_name)
	_update_info_label()

func _open_stage_overlay_for(girl_id: String, girl_name: String) -> void:
	_close_stage_overlay()
	if not card_overlay_by_girl.has(girl_id):
		return
	overlay_girl_id = girl_id
	var entry: Dictionary = card_overlay_by_girl.get(girl_id, {})
	var overlay := entry.get("overlay") as PanelContainer
	var stage_list := entry.get("stage_list") as VBoxContainer
	var title := entry.get("title") as Label
	if title != null:
		title.text = "%s / STAGE" % girl_name
	if stage_list != null:
		_refresh_stage_overlay_list(stage_list)
	if overlay != null:
		overlay.visible = true

func _refresh_open_overlay_list() -> void:
	if overlay_girl_id == "":
		return
	if not card_overlay_by_girl.has(overlay_girl_id):
		return
	var entry: Dictionary = card_overlay_by_girl.get(overlay_girl_id, {})
	var stage_list := entry.get("stage_list") as VBoxContainer
	if stage_list != null:
		_refresh_stage_overlay_list(stage_list)

func _on_overlay_close_pressed() -> void:
	_close_stage_overlay()

func _close_stage_overlay() -> void:
	overlay_girl_id = ""
	for value in card_overlay_by_girl.values():
		if not (value is Dictionary):
			continue
		var entry := value as Dictionary
		var overlay := entry.get("overlay") as PanelContainer
		if overlay != null:
			overlay.visible = false

func _on_stage_pressed(stage_index: int) -> void:
	var started := GameFlow.start_selected_stage(stage_index)
	if started:
		return
	_update_info_label()
	_refresh_open_overlay_list()

func _on_stage_event_edit_pressed(stage_index: int) -> void:
	var ok := GameFlow.select_stage_for_edit(stage_index)
	if not ok:
		_update_info_label()
		_refresh_open_overlay_list()
		return
	if event_editor_controller != null:
		event_editor_controller.open()
	_update_info_label()
	_refresh_open_overlay_list()

func _on_stage_editor_pressed(stage_index: int) -> void:
	if not GameFlow.has_method("debug_start_stage_battle"):
		return
	var girl_id := GameFlow.get_selected_girl_id()
	var started := bool(GameFlow.debug_start_stage_battle(girl_id, stage_index))
	if started:
		return
	_update_info_label()
	_refresh_open_overlay_list()

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

func _on_stage_event_saved(_message: String) -> void:
	_refresh_open_overlay_list()
