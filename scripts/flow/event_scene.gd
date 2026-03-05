extends Control

@onready var background_rect: TextureRect = $Background
@onready var title_label: Label = $BottomPanel/VBox/Title
@onready var body_label: Label = $BottomPanel/VBox/Body
@onready var continue_button: Button = $BottomPanel/VBox/Continue

var pages: Array[Dictionary] = []
var current_page_index := 0
var payload_default_image := ""
var payload_default_bgm := ""
var payload_default_se := ""
var current_page_lines: Array[String] = []
var revealed_line_count := 0

func _ready() -> void:
	var payload := GameFlow.get_current_event_payload()
	payload_default_image = str(payload.get("image", "")).strip_edges()
	payload_default_bgm = str(payload.get("bgm", "")).strip_edges()
	payload_default_se = str(payload.get("se", "")).strip_edges()
	pages = _build_pages(payload)
	current_page_index = 0
	_render_current_page()
	continue_button.visible = false
	continue_button.disabled = true

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_continue_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_on_continue_pressed()
			get_viewport().set_input_as_handled()

func _build_pages(payload: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var title := str(payload.get("title", "イベント"))
	var body: Variant = payload.get("text", "")
	var cuts_variant: Variant = payload.get("cuts", [])
	if cuts_variant is Array and not (cuts_variant as Array).is_empty():
		for item in cuts_variant:
			if item is Dictionary:
				var cut := item as Dictionary
				result.append({
					"title": str(cut.get("title", title)),
					"text": _to_text(cut.get("text", "")),
					"image": str(cut.get("image", "")).strip_edges(),
					"bgm": str(cut.get("bgm", "")).strip_edges(),
					"se": str(cut.get("se", "")).strip_edges()
				})
		if not result.is_empty():
			return result
	var pages_variant: Variant = payload.get("pages", [])
	if pages_variant is Array and not (pages_variant as Array).is_empty():
		for item in pages_variant:
			if item is Dictionary:
				var page_data := item as Dictionary
				result.append({
					"title": str(page_data.get("title", title)),
					"text": _to_text(page_data.get("text", "")),
					"image": str(page_data.get("image", "")).strip_edges(),
					"bgm": str(page_data.get("bgm", "")).strip_edges(),
					"se": str(page_data.get("se", "")).strip_edges()
				})
		if not result.is_empty():
			return result
	if body is Array:
		for line in body:
			result.append({
				"title": title,
				"text": str(line),
				"image": payload_default_image,
				"bgm": payload_default_bgm,
				"se": ""
			})
	else:
		result.append({
			"title": title,
			"text": _to_text(body),
			"image": payload_default_image,
			"bgm": payload_default_bgm,
			"se": payload_default_se
		})
	return result

func _render_current_page() -> void:
	if pages.is_empty():
		return
	current_page_index = clampi(current_page_index, 0, pages.size() - 1)
	var page := pages[current_page_index]
	title_label.text = str(page.get("title", "イベント"))
	current_page_lines = _split_lines(str(page.get("text", "")))
	revealed_line_count = mini(1, current_page_lines.size())
	_update_visible_text()
	_apply_background_texture(str(page.get("image", "")).strip_edges())
	_apply_audio(
		str(page.get("bgm", "")).strip_edges(),
		str(page.get("se", "")).strip_edges()
	)

func _has_next_page() -> bool:
	return current_page_index < pages.size() - 1

func _has_hidden_lines() -> bool:
	return revealed_line_count < current_page_lines.size()

func _split_lines(text: String) -> Array[String]:
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	var packed_lines := normalized.split("\n", true)
	if packed_lines.is_empty():
		return [""]
	var lines: Array[String] = []
	for line in packed_lines:
		lines.append(str(line))
	return lines

func _update_visible_text() -> void:
	if current_page_lines.is_empty():
		body_label.text = ""
		return
	var visible_count := clampi(revealed_line_count, 0, current_page_lines.size())
	body_label.text = current_page_lines[visible_count - 1]

func _apply_background_texture(page_image: String) -> void:
	var image_path := page_image
	if image_path == "":
		image_path = payload_default_image
	if image_path == "":
		background_rect.texture = null
		return
	if not ResourceLoader.exists(image_path):
		background_rect.texture = null
		return
	var texture := load(image_path) as Texture2D
	background_rect.texture = texture

func _apply_audio(page_bgm: String, page_se: String) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return
	var bgm_path := page_bgm
	if bgm_path == "":
		bgm_path = payload_default_bgm
	if bgm_path != "" and audio_manager.has_method("play_bgm"):
		audio_manager.play_bgm(bgm_path)
	var se_path := page_se
	if se_path == "":
		se_path = payload_default_se
	if se_path != "" and audio_manager.has_method("play_se"):
		audio_manager.play_se(se_path)

func _to_text(value: Variant) -> String:
	if value is Array:
		var lines: PackedStringArray = []
		for item in value:
			lines.append(str(item))
		return "\n".join(lines)
	return str(value)

func _on_continue_pressed() -> void:
	if _has_hidden_lines():
		revealed_line_count += 1
		_update_visible_text()
		return
	if _has_next_page():
		current_page_index += 1
		_render_current_page()
		return
	GameFlow.continue_from_event()
