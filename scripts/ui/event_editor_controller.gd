extends RefCounted
class_name EventEditorController

const POPUP_SIZE := Vector2i(860, 620)
const POPUP_MARGIN := Vector2(100.0, 140.0)
const EVENT_KEYS := ["event_before", "event_after_victory", "event_after_defeat"]

var canvas_layer: Node
var hud_controller: BattleHudController
var read_event_handler: Callable
var save_event_handler: Callable
var status_handler: Callable

var dialog: AcceptDialog
var event_type_select: OptionButton
var cut_select: OptionButton
var title_field: LineEdit
var text_field: TextEdit
var image_field: LineEdit
var bgm_field: LineEdit
var se_field: LineEdit

var event_cache := {}
var current_event_key := EVENT_KEYS[0]
var current_cut_index := 0

func setup(
	layer: Node,
	hud: BattleHudController,
	read_handler: Callable,
	save_handler: Callable,
	on_status: Callable = Callable()
) -> void:
	canvas_layer = layer
	hud_controller = hud
	read_event_handler = read_handler
	save_event_handler = save_handler
	status_handler = on_status
	_ensure_ui()

func open() -> void:
	_on_open_pressed()

func layout() -> void:
	if hud_controller != null:
		hud_controller.layout_buttons()

func _ensure_ui() -> void:
	if hud_controller != null:
		hud_controller.ensure_button(
			"event_editor",
			"EventEditorButton",
			"イベント",
			Vector2(120.0, 34.0),
			Callable(self, "_on_open_pressed")
		)
	_ensure_dialog()

func _ensure_dialog() -> void:
	if dialog == null:
		var existing := canvas_layer.get_node_or_null("EventEditorDialog")
		dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if dialog == null:
		dialog = AcceptDialog.new()
		dialog.name = "EventEditorDialog"
		dialog.title = "イベント(cut)エディタ"
		dialog.dialog_text = ""
		canvas_layer.add_child(dialog)
		dialog.confirmed.connect(_on_confirmed)
	var ok_button := dialog.get_ok_button()
	if ok_button != null:
		ok_button.text = "保存"

	var root_existing := dialog.get_node_or_null("ContentScroll/Root")
	if root_existing != null:
		return

	var scroll := ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	dialog.add_child(scroll)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	var event_row := HBoxContainer.new()
	var event_label := Label.new()
	event_label.text = "イベント"
	event_label.custom_minimum_size = Vector2(90.0, 0.0)
	event_row.add_child(event_label)
	event_type_select = OptionButton.new()
	event_type_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_type_select.item_selected.connect(_on_event_type_selected)
	event_row.add_child(event_type_select)
	root.add_child(event_row)

	var cut_row := HBoxContainer.new()
	var cut_label := Label.new()
	cut_label.text = "cut"
	cut_label.custom_minimum_size = Vector2(90.0, 0.0)
	cut_row.add_child(cut_label)
	cut_select = OptionButton.new()
	cut_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cut_select.item_selected.connect(_on_cut_selected)
	cut_row.add_child(cut_select)
	var add_button := Button.new()
	add_button.text = "+"
	add_button.pressed.connect(_on_add_cut_pressed)
	cut_row.add_child(add_button)
	var remove_button := Button.new()
	remove_button.text = "-"
	remove_button.pressed.connect(_on_remove_cut_pressed)
	cut_row.add_child(remove_button)
	var up_button := Button.new()
	up_button.text = "↑"
	up_button.pressed.connect(_on_move_cut_up_pressed)
	cut_row.add_child(up_button)
	var down_button := Button.new()
	down_button.text = "↓"
	down_button.pressed.connect(_on_move_cut_down_pressed)
	cut_row.add_child(down_button)
	root.add_child(cut_row)

	title_field = _add_line_row(root, "タイトル")

	var text_label := Label.new()
	text_label.text = "テキスト"
	root.add_child(text_label)
	text_field = TextEdit.new()
	text_field.custom_minimum_size = Vector2(0.0, 220.0)
	text_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(text_field)

	image_field = _add_line_row(root, "画像")
	bgm_field = _add_line_row(root, "BGM")
	se_field = _add_line_row(root, "SE")

	var hint := Label.new()
	hint.text = "cut未設定の項目はイベント共通値へフォールバックされます。画像を空欄にすると非表示です。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	scroll.add_child(root)
	_refresh_event_type_options()

func _add_line_row(parent: VBoxContainer, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90.0, 0.0)
	row.add_child(label)
	var line := LineEdit.new()
	line.placeholder_text = "res://..."
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	parent.add_child(row)
	return line

func _refresh_event_type_options() -> void:
	if event_type_select == null:
		return
	event_type_select.clear()
	event_type_select.add_item("ブリーフィング")
	event_type_select.add_item("戦闘後(勝利)")
	event_type_select.add_item("戦闘後(敗北)")
	event_type_select.select(0)

func _on_open_pressed() -> void:
	_load_all_events_from_stage()
	current_event_key = EVENT_KEYS[0]
	current_cut_index = 0
	if event_type_select != null:
		event_type_select.select(0)
	_reload_cut_options()
	_render_current_cut()
	if dialog != null:
		dialog.popup_centered(_compute_popup_size())

func _compute_popup_size() -> Vector2i:
	if canvas_layer == null:
		return POPUP_SIZE
	var viewport := canvas_layer.get_viewport()
	if viewport == null:
		return POPUP_SIZE
	var visible := viewport.get_visible_rect().size
	var max_width := maxi(360.0, visible.x - POPUP_MARGIN.x)
	var max_height := maxi(320.0, visible.y - POPUP_MARGIN.y)
	var width := int(clampf(float(POPUP_SIZE.x), 360.0, max_width))
	var height := int(clampf(float(POPUP_SIZE.y), 320.0, max_height))
	return Vector2i(width, height)

func _load_all_events_from_stage() -> void:
	event_cache.clear()
	for key in EVENT_KEYS:
		event_cache[key] = _normalize_event(_read_stage_event(key))

func _read_stage_event(event_key: String) -> Dictionary:
	if not read_event_handler.is_valid():
		return {}
	var value: Variant = read_event_handler.call(event_key)
	return value as Dictionary if value is Dictionary else {}

func _normalize_event(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var title := str(src.get("title", "イベント"))
	var image := str(src.get("image", "")).strip_edges()
	var bgm := str(src.get("bgm", "")).strip_edges()
	var se := str(src.get("se", "")).strip_edges()
	var cuts: Array[Dictionary] = []
	var cuts_variant: Variant = src.get("cuts", [])
	if cuts_variant is Array:
		for item in (cuts_variant as Array):
			if not (item is Dictionary):
				continue
			var cut := item as Dictionary
			cuts.append({
				"title": str(cut.get("title", title)),
				"text": str(cut.get("text", "")),
				"image": str(cut.get("image", "")).strip_edges(),
				"bgm": str(cut.get("bgm", "")).strip_edges(),
				"se": str(cut.get("se", "")).strip_edges()
			})
	if cuts.is_empty():
		var text_variant: Variant = src.get("text", "")
		if text_variant is Array and not (text_variant as Array).is_empty():
			for line in (text_variant as Array):
				cuts.append({
					"title": title,
					"text": str(line),
					"image": image,
					"bgm": bgm,
					"se": ""
				})
		else:
			cuts.append({
				"title": title,
				"text": str(text_variant),
				"image": image,
				"bgm": bgm,
				"se": se
			})
	return {
		"title": title,
		"text": src.get("text", ""),
		"image": image,
		"bgm": bgm,
		"se": se,
		"cuts": cuts
	}

func _current_event() -> Dictionary:
	var value: Variant = event_cache.get(current_event_key, {})
	return value as Dictionary if value is Dictionary else _normalize_event({})

func _update_current_event(event_data: Dictionary) -> void:
	event_cache[current_event_key] = event_data

func _current_cuts() -> Array[Dictionary]:
	var event_data := _current_event()
	var raw: Variant = event_data.get("cuts", [])
	var cuts: Array[Dictionary] = []
	if raw is Array:
		for item in (raw as Array):
			if item is Dictionary:
				cuts.append((item as Dictionary).duplicate(true))
	return cuts

func _save_current_cut_fields() -> void:
	if title_field == null or text_field == null:
		return
	var event_data := _current_event()
	var cuts := _current_cuts()
	if cuts.is_empty():
		cuts.append({"title": "", "text": "", "image": "", "bgm": "", "se": ""})
	current_cut_index = clampi(current_cut_index, 0, cuts.size() - 1)
	cuts[current_cut_index] = {
		"title": title_field.text.strip_edges(),
		"text": text_field.text,
		"image": image_field.text.strip_edges(),
		"bgm": bgm_field.text.strip_edges(),
		"se": se_field.text.strip_edges()
	}
	event_data["cuts"] = cuts
	_update_current_event(event_data)

func _render_current_cut() -> void:
	var cuts := _current_cuts()
	if cuts.is_empty():
		cuts.append({"title": "", "text": "", "image": "", "bgm": "", "se": ""})
		var event_data := _current_event()
		event_data["cuts"] = cuts
		_update_current_event(event_data)
	current_cut_index = clampi(current_cut_index, 0, cuts.size() - 1)
	var cut := cuts[current_cut_index]
	title_field.text = str(cut.get("title", ""))
	text_field.text = str(cut.get("text", ""))
	image_field.text = str(cut.get("image", ""))
	bgm_field.text = str(cut.get("bgm", ""))
	se_field.text = str(cut.get("se", ""))
	if cut_select != null and cut_select.item_count > 0:
		cut_select.select(current_cut_index)

func _reload_cut_options() -> void:
	if cut_select == null:
		return
	cut_select.clear()
	var cuts := _current_cuts()
	if cuts.is_empty():
		cut_select.add_item("cut 1")
		current_cut_index = 0
		return
	for i in cuts.size():
		cut_select.add_item("cut %d" % (i + 1))
	current_cut_index = clampi(current_cut_index, 0, cuts.size() - 1)
	cut_select.select(current_cut_index)

func _on_event_type_selected(index: int) -> void:
	_save_current_cut_fields()
	if index < 0 or index >= EVENT_KEYS.size():
		return
	current_event_key = EVENT_KEYS[index]
	current_cut_index = 0
	_reload_cut_options()
	_render_current_cut()

func _on_cut_selected(index: int) -> void:
	_save_current_cut_fields()
	current_cut_index = maxi(0, index)
	_render_current_cut()

func _on_add_cut_pressed() -> void:
	_save_current_cut_fields()
	var event_data := _current_event()
	var cuts := _current_cuts()
	var insert_index := clampi(current_cut_index + 1, 0, cuts.size())
	var next_title := title_field.text.strip_edges()
	cuts.insert(insert_index, {
		"title": next_title,
		"text": "",
		"image": image_field.text.strip_edges(),
		"bgm": bgm_field.text.strip_edges(),
		"se": ""
	})
	event_data["cuts"] = cuts
	_update_current_event(event_data)
	current_cut_index = insert_index
	_reload_cut_options()
	_render_current_cut()

func _on_remove_cut_pressed() -> void:
	_save_current_cut_fields()
	var event_data := _current_event()
	var cuts := _current_cuts()
	if cuts.is_empty():
		cuts.append({"title": "", "text": "", "image": "", "bgm": "", "se": ""})
	elif cuts.size() <= 1:
		cuts[0] = {"title": "", "text": "", "image": "", "bgm": "", "se": ""}
	else:
		current_cut_index = clampi(current_cut_index, 0, cuts.size() - 1)
		cuts.remove_at(current_cut_index)
		current_cut_index = clampi(current_cut_index, 0, cuts.size() - 1)
	event_data["cuts"] = cuts
	_update_current_event(event_data)
	_reload_cut_options()
	_render_current_cut()

func _on_move_cut_up_pressed() -> void:
	_save_current_cut_fields()
	var event_data := _current_event()
	var cuts := _current_cuts()
	if current_cut_index <= 0 or current_cut_index >= cuts.size():
		return
	var prev := current_cut_index - 1
	var tmp := cuts[prev]
	cuts[prev] = cuts[current_cut_index]
	cuts[current_cut_index] = tmp
	current_cut_index = prev
	event_data["cuts"] = cuts
	_update_current_event(event_data)
	_reload_cut_options()
	_render_current_cut()

func _on_move_cut_down_pressed() -> void:
	_save_current_cut_fields()
	var event_data := _current_event()
	var cuts := _current_cuts()
	if current_cut_index < 0 or current_cut_index >= cuts.size() - 1:
		return
	var next := current_cut_index + 1
	var tmp := cuts[next]
	cuts[next] = cuts[current_cut_index]
	cuts[current_cut_index] = tmp
	current_cut_index = next
	event_data["cuts"] = cuts
	_update_current_event(event_data)
	_reload_cut_options()
	_render_current_cut()

func _on_confirmed() -> void:
	_save_current_cut_fields()
	if not save_event_handler.is_valid():
		return
	var all_ok := true
	for key in EVENT_KEYS:
		var raw: Variant = event_cache.get(key, {})
		var event_data := _normalize_event(raw)
		var result: Variant = save_event_handler.call(key, event_data)
		if not bool(result):
			all_ok = false
	if status_handler.is_valid():
		var message := "イベント(cut)を保存しました。" if all_ok else "イベント(cut)の保存に失敗しました。"
		status_handler.call(message)
