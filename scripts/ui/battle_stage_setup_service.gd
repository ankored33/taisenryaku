class_name BattleStageSetupService
extends RefCounted

static func apply_stage_map_settings(board: HexBoard, stage_data: Dictionary) -> Dictionary:
	var result := {
		"background_path": "",
		"has_camera_config": false,
		"camera_config": {}
	}
	var map_data_variant: Variant = stage_data.get("map", {})
	if not (map_data_variant is Dictionary):
		return result
	var map_data: Dictionary = map_data_variant
	board.cols = maxi(1, int(map_data.get("cols", board.cols)))
	board.rows = maxi(1, int(map_data.get("rows", board.rows)))
	var tile_width := maxi(1, int(map_data.get("tile_width", int(board.get("tile_width")))))
	var tile_height := maxi(1, int(map_data.get("tile_height", int(board.get("tile_height")))))
	var hex_side_length := maxi(0, int(map_data.get("hex_side_length", int(board.get("hex_side_length")))))
	var stagger_axis := str(map_data.get("stagger_axis", str(board.get("stagger_axis"))))
	var stagger_index := str(map_data.get("stagger_index", str(board.get("stagger_index"))))
	board.configure_hex_metrics(tile_width, tile_height, hex_side_length, stagger_axis, stagger_index)
	board.apply_stage_terrain(stage_data)
	result["background_path"] = str(map_data.get("background_image", ""))
	var camera_variant: Variant = map_data.get("camera", {})
	result["has_camera_config"] = camera_variant is Dictionary
	result["camera_config"] = (camera_variant as Dictionary).duplicate(true) if camera_variant is Dictionary else {}
	return result

static func compute_initial_camera(board: HexBoard, has_stage_camera_config: bool, stage_camera_config: Dictionary, board_rect: Rect2, left_panel_width: float, view_padding: float, viewport_rect: Rect2, board_anchor: Vector2) -> Dictionary:
	if not has_stage_camera_config:
		return {"applied": false, "pan": Vector2.ZERO, "zoom": 1.0}
	var target_local := stage_camera_target_local(board, has_stage_camera_config, stage_camera_config, board_rect)
	var target_zoom := stage_camera_target_zoom()
	var side_gutter := left_panel_width + view_padding
	var view_left := side_gutter
	var view_top := view_padding
	var view_right := viewport_rect.size.x - side_gutter
	var view_bottom := viewport_rect.size.y - view_padding
	var view_center := Vector2(
		(view_left + view_right) * 0.5,
		(view_top + view_bottom) * 0.5
	)
	var pan := view_center - board_anchor - (target_local * target_zoom)
	return {"applied": true, "pan": pan, "zoom": target_zoom}

static func stage_camera_target_zoom() -> float:
	return 1.0

static func stage_camera_target_local(board: HexBoard, has_stage_camera_config: bool, stage_camera_config: Dictionary, board_rect: Rect2) -> Vector2:
	var fallback := board_rect.position + board_rect.size * 0.5
	if not has_stage_camera_config:
		return fallback
	if stage_camera_config.has("tile"):
		var tile_raw: Variant = stage_camera_config.get("tile", [])
		if tile_raw is Array and (tile_raw as Array).size() >= 2:
			var tile := tile_raw as Array
			var q := int(tile[0])
			var r := int(tile[1])
			return board.map_to_local(Vector2i(q, r))
	if stage_camera_config.has("local_pos"):
		var pos_raw: Variant = stage_camera_config.get("local_pos", [])
		if pos_raw is Array and (pos_raw as Array).size() >= 2:
			var pos := pos_raw as Array
			return Vector2(float(pos[0]), float(pos[1]))
	return fallback
