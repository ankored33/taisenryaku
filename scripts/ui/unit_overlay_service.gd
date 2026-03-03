class_name UnitOverlayService
extends RefCounted

const UnitState = preload("res://scripts/board/unit_state.gd")

func ensure_layer(canvas_layer: CanvasLayer, existing: Control) -> Control:
	if existing != null:
		return existing
	var layer := Control.new()
	layer.name = "UnitHpOverlayLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(layer)
	return layer

func update(
	layer: Control,
	board: HexBoard,
	hp_labels: Dictionary,
	moved_markers: Dictionary,
	hp_offset_factor: Vector2,
	moved_offset_factor: Vector2
) -> void:
	if layer == null or board == null:
		return
	var zoom := board.scale.x
	var font_size := maxi(8, int(round(10.0 * zoom)))
	var marker_font_size := maxi(7, int(round(8.0 * zoom)))
	var hp_offset := Vector2(float(board.hex_size) * hp_offset_factor.x, float(board.hex_size) * hp_offset_factor.y) * zoom
	var moved_offset := Vector2(float(board.hex_size) * moved_offset_factor.x, float(board.hex_size) * moved_offset_factor.y) * zoom
	var active := {}
	var moved_active := {}
	for idx in board.query_unit_count():
		var unit: Dictionary = board.query_unit(idx)
		if unit.is_empty():
			continue
		if UnitState.faction(unit) != "player" and not board.query_is_unit_visible_to_player(idx):
			continue
		var tile := board.query_to_vec2i(UnitState.pos(unit))
		if not board.query_is_valid_hex(tile):
			continue
		var key := _overlay_key(unit, idx)
		active[key] = true
		var label := _ensure_label(layer, hp_labels, "Hp_%s" % key, key)
		label.add_theme_font_size_override("font_size", font_size)
		label.text = str(UnitState.hp(unit))
		var world_pos: Vector2 = board.to_global(board.query_unit_draw_position(unit))
		var screen_pos := world_pos + hp_offset
		label.position = Vector2(floor(screen_pos.x), floor(screen_pos.y))

		var unit_id := UnitState.id(unit)
		var is_animating := board.query_is_unit_animating(unit_id)
		var is_moved := UnitState.is_moved(unit)
		var is_current_faction := UnitState.faction(unit) == board.query_current_faction()
		if is_moved and is_current_faction and not is_animating:
			moved_active[key] = true
			var marker := _ensure_label(layer, moved_markers, "Moved_%s" % key, key)
			marker.text = "●"
			marker.add_theme_color_override("font_color", Color(0.26, 0.26, 0.26, 0.98))
			marker.add_theme_font_size_override("font_size", marker_font_size)
			marker.position = Vector2(floor(world_pos.x + moved_offset.x), floor(world_pos.y + moved_offset.y))
	_cleanup_stale(hp_labels, active)
	_cleanup_stale(moved_markers, moved_active)

func _overlay_key(unit: Dictionary, idx: int) -> String:
	var unit_id := UnitState.id(unit)
	if unit_id != "":
		return unit_id
	return "__idx_%d" % idx

func _ensure_label(layer: Control, registry: Dictionary, node_name: String, key: String) -> Label:
	if registry.has(key):
		var existing: Variant = registry[key]
		if existing is Label:
			return existing as Label
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	registry[key] = label
	return label

func _cleanup_stale(registry: Dictionary, active: Dictionary) -> void:
	for key in registry.keys():
		if active.has(key):
			continue
		var node_variant: Variant = registry[key]
		if node_variant is Label:
			var node := node_variant as Label
			if is_instance_valid(node):
				node.queue_free()
		registry.erase(key)
