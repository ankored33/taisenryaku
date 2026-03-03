extends RefCounted
class_name BattleHudController

const BUTTON_GAP := 8.0
const DEFAULT_BUTTON_HEIGHT := 34.0

var canvas_layer: CanvasLayer
var view_padding := 12.0
var button_order: Array[String] = []
var button_map := {}

func _init(layer: CanvasLayer, padding: float = 12.0) -> void:
	canvas_layer = layer
	view_padding = padding

func set_button_order(order: Array[String]) -> void:
	button_order = order.duplicate()

func ensure_button(
	key: String,
	node_name: String,
	label: String,
	min_size: Vector2,
	pressed_handler: Callable
) -> Button:
	var existing_variant: Variant = button_map.get(key, null)
	if existing_variant is Button:
		var existing := existing_variant as Button
		_apply_button_props(existing, label, min_size)
		return existing

	var node := canvas_layer.get_node_or_null(node_name)
	var button: Button = node as Button if node is Button else null
	if button == null:
		button = Button.new()
		button.name = node_name
		canvas_layer.add_child(button)
	if pressed_handler.is_valid():
		if not button.pressed.is_connected(pressed_handler):
			button.pressed.connect(pressed_handler)
	_apply_button_props(button, label, min_size)
	button_map[key] = button
	return button

func set_button_text(key: String, label: String) -> void:
	var button := get_button(key)
	if button == null:
		return
	button.text = label

func get_button(key: String) -> Button:
	var value: Variant = button_map.get(key, null)
	return value as Button if value is Button else null

func layout_buttons() -> void:
	if canvas_layer == null:
		return
	var cursor_bottom := -view_padding
	for key in button_order:
		var button := get_button(key)
		if button == null:
			continue
		var width := button.custom_minimum_size.x
		var height := button.custom_minimum_size.y
		if height <= 0.0:
			height = DEFAULT_BUTTON_HEIGHT
		button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		button.offset_right = -view_padding
		button.offset_bottom = cursor_bottom
		button.offset_left = button.offset_right - width
		button.offset_top = button.offset_bottom - height
		cursor_bottom -= (height + BUTTON_GAP)

func _apply_button_props(button: Button, label: String, min_size: Vector2) -> void:
	button.text = label
	button.custom_minimum_size = min_size
