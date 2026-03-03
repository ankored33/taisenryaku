class_name BattleCameraController
extends RefCounted

var speed := 1152.0
var zoom_step := 1.12
var min_zoom := 0.60
var max_zoom := 2.40
var view_padding := 12.0

func _init(
	camera_speed: float = 1152.0,
	step: float = 1.12,
	min_zoom_value: float = 0.60,
	max_zoom_value: float = 2.40,
	padding: float = 12.0
) -> void:
	speed = camera_speed
	zoom_step = step
	min_zoom = min_zoom_value
	max_zoom = max_zoom_value
	view_padding = padding

func apply_pan_input(delta: float, board_pan: Vector2) -> Vector2:
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if input_dir == Vector2.ZERO:
		return board_pan
	return board_pan - input_dir.normalized() * speed * delta

func should_handle_zoom_event(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return false
	return mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN

func zoom_factor_from_event(event: InputEventMouseButton) -> float:
	return zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step

func is_mouse_over_board(board: Node2D, board_rect: Rect2, mouse_position: Vector2) -> bool:
	var board_local := board.to_local(mouse_position)
	return board_rect.has_point(board_local)

func zoom_at(pivot_screen: Vector2, board_anchor: Vector2, board_pan: Vector2, board_zoom: float, zoom_factor: float) -> Dictionary:
	var old_zoom := board_zoom
	var new_zoom := clampf(old_zoom * zoom_factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return {"changed": false, "zoom": board_zoom, "pan": board_pan}
	var anchor_to_pivot := pivot_screen - board_anchor
	var local_before_zoom := (anchor_to_pivot - board_pan) / old_zoom
	var next_pan := anchor_to_pivot - local_before_zoom * new_zoom
	return {"changed": true, "zoom": new_zoom, "pan": next_pan}

func clamp_pan_and_apply(
	board: Node2D,
	left_panel_width: float,
	board_rect: Rect2,
	board_anchor: Vector2,
	board_pan: Vector2,
	board_zoom: float
) -> Vector2:
	var viewport_rect := board.get_viewport_rect()
	var side_gutter := left_panel_width + view_padding
	var view_left := side_gutter
	var view_top := view_padding
	var view_right := viewport_rect.size.x - side_gutter
	var view_bottom := viewport_rect.size.y - view_padding
	var view_width: float = maxf(1.0, view_right - view_left)
	var view_height: float = maxf(1.0, view_bottom - view_top)
	var scaled_pos := board_rect.position * board_zoom
	var scaled_size := board_rect.size * board_zoom

	var min_pan_x: float
	var max_pan_x: float
	var min_pan_y: float
	var max_pan_y: float

	if scaled_size.x <= view_width:
		min_pan_x = view_left - (board_anchor.x + scaled_pos.x)
		max_pan_x = min_pan_x
	else:
		min_pan_x = view_right - (board_anchor.x + scaled_pos.x + scaled_size.x)
		max_pan_x = view_left - (board_anchor.x + scaled_pos.x)

	if scaled_size.y <= view_height:
		min_pan_y = view_top - (board_anchor.y + scaled_pos.y)
		max_pan_y = min_pan_y
	else:
		min_pan_y = view_bottom - (board_anchor.y + scaled_pos.y + scaled_size.y)
		max_pan_y = view_top - (board_anchor.y + scaled_pos.y)

	var clamped_pan := board_pan
	clamped_pan.x = clamp(clamped_pan.x, min_pan_x, max_pan_x)
	clamped_pan.y = clamp(clamped_pan.y, min_pan_y, max_pan_y)
	board.position = board_anchor + clamped_pan
	board.scale = Vector2.ONE * board_zoom
	return clamped_pan
