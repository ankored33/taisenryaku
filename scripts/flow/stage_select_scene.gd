extends Control

const EventEditorController = preload("res://scripts/ui/event_editor_controller.gd")
const CHARACTER_PANEL_COUNT := 5
const PORTRAIT_RATIO := 600.0 / 1280.0
const CARD_BASE_COLORS := [
	Color("e79ab8"),
	Color("e6b97a"),
	Color("78bec4"),
	Color("9ba7e3"),
	Color("a7c779")
]

@onready var character_scroll: ScrollContainer = $Margin/VBox/CharacterScroll
@onready var character_row: HBoxContainer = $Margin/VBox/CharacterScroll/CharacterRow

var event_editor_controller: EventEditorController
var overlay_girl_id := ""
var character_cards: Array[Button] = []
var card_overlay_by_girl := {}

func _ready() -> void:
	_setup_event_editor()
	_apply_scene_theme()
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
	var accent := _accent_color(slot_index)
	card.add_theme_stylebox_override("normal", _make_card_style(accent, 0.96))
	card.add_theme_stylebox_override("hover", _make_card_style(accent.lightened(0.08), 1.0, 16.0))
	card.add_theme_stylebox_override("pressed", _make_card_style(accent.darkened(0.08), 1.0, 16.0))
	card.add_theme_stylebox_override("disabled", _make_card_style(Color("afb8c6"), 0.72))

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
	portrait.add_theme_stylebox_override("panel", _make_portrait_style(accent))
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
		placeholder.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		placeholder.add_theme_font_size_override("font_size", 20)
		placeholder.text = "NO IMAGE" if has_girl else "COMING SOON"
		portrait.add_child(placeholder)

	var overlay := PanelContainer.new()
	overlay.visible = false
	overlay.layout_mode = 1
	overlay.anchors_preset = PRESET_FULL_RECT
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_theme_stylebox_override("panel", _make_overlay_style(accent))
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
	overlay_title.add_theme_color_override("font_color", Color("5f335f"))
	overlay_title.add_theme_font_size_override("font_size", 18)
	overlay_title.text = "%s / STAGE" % girl_name
	header.add_child(overlay_title)

	var overlay_close := Button.new()
	overlay_close.text = "閉"
	overlay_close.custom_minimum_size = Vector2(36.0, 0.0)
	overlay_close.add_theme_stylebox_override("normal", _make_chip_style(Color("ffffff"), accent.darkened(0.1)))
	overlay_close.add_theme_stylebox_override("hover", _make_chip_style(Color("fff7d6"), accent))
	overlay_close.add_theme_stylebox_override("pressed", _make_chip_style(Color("ffe3ef"), accent.darkened(0.14)))
	overlay_close.add_theme_color_override("font_color", Color("5f335f"))
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
			"girl_name": girl_name,
			"accent": accent
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
			card.scale = Vector2.ONE * 1.02
		else:
			card.modulate = Color(0.94, 0.95, 1.0, 0.96)
			card.scale = Vector2.ONE

func _refresh_stage_overlay_list(target_stage_list: VBoxContainer) -> void:
	for child in target_stage_list.get_children():
		child.queue_free()
	var stages := GameFlow.get_selected_girl_stages()
	var accent := Color("ff8bb4")
	if card_overlay_by_girl.has(overlay_girl_id):
		var entry: Dictionary = card_overlay_by_girl.get(overlay_girl_id, {})
		var accent_value: Variant = entry.get("accent", accent)
		if accent_value is Color:
			accent = accent_value
	if stages.is_empty():
		var empty_label := Label.new()
		empty_label.text = "ステージが設定されていません。"
		empty_label.add_theme_color_override("font_color", Color("5f335f"))
		target_stage_list.add_child(empty_label)
		return
	for stage in stages:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		target_stage_list.add_child(box)

		var index := int(stage.get("index", 0))
		var unlocked := bool(stage.get("unlocked", false))
		var cleared := bool(stage.get("cleared", false))
		var exists := bool(stage.get("exists", false))

		var start_button := Button.new()
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start_button.text = _build_stage_label(index, unlocked, cleared, exists)
		start_button.disabled = not unlocked or not exists
		start_button.add_theme_stylebox_override("normal", _make_stage_button_style(accent, unlocked, cleared, exists))
		start_button.add_theme_stylebox_override("hover", _make_stage_button_style(accent.lightened(0.08), unlocked, cleared, exists))
		start_button.add_theme_stylebox_override("pressed", _make_stage_button_style(accent.darkened(0.06), unlocked, cleared, exists))
		start_button.add_theme_stylebox_override("disabled", _make_stage_button_style(Color("c8cfdb"), false, false, exists))
		start_button.add_theme_color_override("font_color", _stage_button_font_color(unlocked, cleared, exists))
		start_button.add_theme_font_size_override("font_size", 18)
		start_button.custom_minimum_size = Vector2(0.0, 46.0)
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

func _apply_scene_theme() -> void:
	character_scroll.add_theme_stylebox_override("panel", _make_scroll_style())

func _accent_color(slot_index: int) -> Color:
	return CARD_BASE_COLORS[slot_index % CARD_BASE_COLORS.size()]

func _make_card_style(accent: Color, alpha: float, shadow_size: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.992, 0.988, alpha)
	style.border_color = accent
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.corner_radius_top_left = 26
	style.corner_radius_top_right = 26
	style.corner_radius_bottom_right = 26
	style.corner_radius_bottom_left = 26
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.14)
	style.shadow_size = int(shadow_size)
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style

func _make_portrait_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	style.border_color = accent.lightened(0.08)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_right = 22
	style.corner_radius_bottom_left = 22
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	return style

func _make_overlay_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.992, 0.978, 0.986, 0.9)
	style.border_color = accent
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_right = 20
	style.corner_radius_bottom_left = 20
	style.shadow_color = Color(0.35, 0.2, 0.35, 0.1)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 12.0
	style.content_margin_top = 12.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 12.0
	return style

func _make_chip_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 14
	style.content_margin_left = 8.0
	style.content_margin_top = 4.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 4.0
	return style

func _make_scroll_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.34)
	style.corner_radius_top_left = 30
	style.corner_radius_top_right = 30
	style.corner_radius_bottom_right = 30
	style.corner_radius_bottom_left = 30
	style.content_margin_left = 18.0
	style.content_margin_top = 18.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 18.0
	return style

func _make_stage_button_style(accent: Color, unlocked: bool, cleared: bool, exists: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_right = 16
	style.corner_radius_bottom_left = 16
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	if not exists:
		style.bg_color = Color("ede7f0")
		style.border_color = Color("cbbfd6")
	elif cleared:
		style.bg_color = Color("f6e8a9")
		style.border_color = Color("ddb45d")
	elif unlocked:
		style.bg_color = accent.lightened(0.26)
		style.border_color = accent.darkened(0.02)
	else:
		style.bg_color = Color("e7ebf3")
		style.border_color = Color("c1cad8")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	return style

func _stage_button_font_color(unlocked: bool, cleared: bool, exists: bool) -> Color:
	if not exists:
		return Color("8a6f96")
	if cleared:
		return Color("7b4b00")
	if unlocked:
		return Color("59335f")
	return Color("6b7380")
