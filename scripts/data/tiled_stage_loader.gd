extends RefCounted
class_name TiledStageLoader

const GID_CLEAR_MASK := 0x1FFFFFFF

static func apply_tiled_map(stage_data: Dictionary, stage_json_path: String = "") -> Dictionary:
	var merged := stage_data.duplicate(true)
	var tiled_map_variant: Variant = merged.get("tiled_map", null)
	if tiled_map_variant == null:
		return merged

	var tiled_map: Dictionary = tiled_map_variant if tiled_map_variant is Dictionary else {}
	var tmj_path := _resolve_tmj_path(tiled_map, stage_json_path)
	if tmj_path == "":
		return merged

	var tmj: Dictionary = _load_json_dict(tmj_path)
	if tmj.is_empty():
		push_warning("Tiledマップの読み込みに失敗しました: %s" % tmj_path)
		return merged

	var width := maxi(1, int(tmj.get("width", 1)))
	var height := maxi(1, int(tmj.get("height", 1)))
	var tile_width := maxi(1, int(tmj.get("tilewidth", 1)))
	var tile_height := maxi(1, int(tmj.get("tileheight", 1)))
	var hex_side_length := maxi(0, int(tmj.get("hexsidelength", 0)))
	var orientation := str(tmj.get("orientation", ""))
	var stagger_axis := str(tmj.get("staggeraxis", ""))
	var stagger_index := str(tmj.get("staggerindex", ""))
	var terrain_layer := str(tiled_map.get("terrain_layer", "terrain"))
	var default_terrain := str(tiled_map.get("default_terrain", "plain"))
	var gid_to_terrain := _normalize_gid_map(tiled_map.get("gid_terrain", {}))
	var map_block_variant: Variant = merged.get("map", {})
	var map_block: Dictionary = map_block_variant if map_block_variant is Dictionary else {}
	var camera_config := _extract_camera_from_tmj(tmj, map_block)

	merged["map"] = {
		"cols": width,
		"rows": height,
		"background_image": str(map_block.get("background_image", "")),
		"camera": camera_config,
		"tile_width": tile_width,
		"tile_height": tile_height,
		"hex_side_length": hex_side_length,
		"orientation": orientation,
		"stagger_axis": stagger_axis,
		"stagger_index": stagger_index
	}
	merged["terrain"] = _extract_terrain_from_tmj(tmj, terrain_layer, default_terrain, gid_to_terrain)
	merged["unit_spawns"] = _extract_unit_spawns_from_tmj(tmj)
	var transport_goal := _extract_transport_goal_from_tmj(tmj)
	if not transport_goal.is_empty():
		merged["transport_goal"] = transport_goal
	var capture_points := _extract_capture_points_from_tmj(tmj)
	if not capture_points.is_empty():
		merged["capture_points"] = capture_points
	return merged

static func _extract_camera_from_tmj(tmj: Dictionary, map_block: Dictionary) -> Dictionary:
	var camera := {}
	var existing_variant: Variant = map_block.get("camera", {})
	if existing_variant is Dictionary:
		camera = (existing_variant as Dictionary).duplicate(true)
	var camera_object := _find_camera_object_from_tmj(tmj)
	if not camera_object.is_empty():
		camera["local_pos"] = [
			float(camera_object.get("x", 0.0)),
			float(camera_object.get("y", 0.0))
		]
		return camera
	if not camera.is_empty():
		return camera
	return {}

static func _find_camera_object_from_tmj(tmj: Dictionary) -> Dictionary:
	var layers_variant: Variant = tmj.get("layers", [])
	if not (layers_variant is Array):
		return {}
	for layer_item in layers_variant:
		if not (layer_item is Dictionary):
			continue
		var layer := layer_item as Dictionary
		if str(layer.get("type", "")) != "objectgroup":
			continue
		var layer_name := str(layer.get("name", "")).strip_edges().to_lower()
		var objects_variant: Variant = layer.get("objects", [])
		if not (objects_variant is Array):
			continue
		var objects := objects_variant as Array
		if layer_name == "camera_start" or layer_name == "camera":
			for object_item in objects:
				if object_item is Dictionary:
					return object_item as Dictionary
		for object_item in objects:
			if not (object_item is Dictionary):
				continue
			var object_dict := object_item as Dictionary
			var object_name := str(object_dict.get("name", "")).strip_edges().to_lower()
			var object_type := str(object_dict.get("type", "")).strip_edges().to_lower()
			var props := _properties_to_dict(object_dict.get("properties", []))
			var objective := str(props.get("objective", "")).strip_edges().to_lower()
			if object_name == "camera_start" or object_name == "camera":
				return object_dict
			if object_type == "camera_start" or object_type == "camera":
				return object_dict
			if objective == "camera_start" or objective == "camera":
				return object_dict
	return {}

static func _resolve_tmj_path(tiled_map: Dictionary, stage_json_path: String) -> String:
	var raw := str(tiled_map.get("path", ""))
	if raw == "":
		return ""
	if raw.begins_with("res://") or raw.begins_with("user://"):
		return raw
	if stage_json_path == "" or not stage_json_path.begins_with("res://"):
		return raw
	return stage_json_path.get_base_dir().path_join(raw)

static func _load_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func _normalize_gid_map(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for key in raw.keys():
		var gid := int(str(key))
		if gid <= 0:
			continue
		result[gid] = str(raw[key])
	return result

static func _extract_terrain_from_tmj(tmj: Dictionary, terrain_layer: String, default_terrain: String, gid_to_terrain: Dictionary) -> Dictionary:
	var layers_variant: Variant = tmj.get("layers", [])
	if not (layers_variant is Array):
		return {"default": default_terrain, "paint": []}
	var layer := _find_tile_layer(layers_variant, terrain_layer)
	if layer.is_empty():
		return {"default": default_terrain, "paint": []}

	var width := maxi(1, int(tmj.get("width", 1)))
	var height := maxi(1, int(tmj.get("height", 1)))
	var data := _flatten_layer_data(layer.get("data", []))
	if data.is_empty():
		return {"default": default_terrain, "paint": []}

	var paint_by_type := {}
	for y in height:
		for x in width:
			var idx := y * width + x
			if idx >= data.size():
				break
			var gid := int(data[idx]) & GID_CLEAR_MASK
			if gid == 0:
				continue
			var terrain := str(gid_to_terrain.get(gid, default_terrain))
			if terrain == default_terrain:
				continue
			if not paint_by_type.has(terrain):
				paint_by_type[terrain] = []
			(paint_by_type[terrain] as Array).append([x, y])

	var paint := []
	for terrain_type in paint_by_type.keys():
		paint.append({
			"type": terrain_type,
			"tiles": paint_by_type[terrain_type]
		})
	return {"default": default_terrain, "paint": paint}

static func _find_tile_layer(layers: Array, layer_name: String) -> Dictionary:
	for item in layers:
		if not (item is Dictionary):
			continue
		var layer := item as Dictionary
		if str(layer.get("type", "")) != "tilelayer":
			continue
		if str(layer.get("name", "")) == layer_name:
			return layer
	for item in layers:
		if not (item is Dictionary):
			continue
		var layer := item as Dictionary
		if str(layer.get("type", "")) == "tilelayer":
			return layer
	return {}

static func _flatten_layer_data(raw_data: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw_data is Array:
		for value in raw_data:
			result.append(int(value))
		return result
	if raw_data is PackedInt32Array:
		for value in raw_data:
			result.append(int(value))
	return result

static func _extract_unit_spawns_from_tmj(tmj: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layers_variant: Variant = tmj.get("layers", [])
	if not (layers_variant is Array):
		return result
	for layer_item in layers_variant:
		if not (layer_item is Dictionary):
			continue
		var layer := layer_item as Dictionary
		if str(layer.get("type", "")) != "objectgroup":
			continue
		var layer_name := str(layer.get("name", "")).to_lower()
		if layer_name != "spawn_player" and layer_name != "spawn_enemy":
			continue
		var faction := "player" if layer_name == "spawn_player" else "enemy"
		var objects_variant: Variant = layer.get("objects", [])
		if not (objects_variant is Array):
			continue
		for object_item in objects_variant:
			if not (object_item is Dictionary):
				continue
			var object_dict := object_item as Dictionary
			var props := _properties_to_dict(object_dict.get("properties", []))
			var object_name := str(object_dict.get("name", "")).strip_edges()
			var unit_id := str(props.get("unit_id", "")).strip_edges()
			var unit_class := str(props.get("unit_class", "")).strip_edges().to_lower()
			if unit_id == "" and unit_class == "":
				# Backward compatibility: object name can be treated as unit_id.
				unit_id = object_name
			if unit_id == "" and unit_class == "":
				continue
			var spawn: Dictionary = {
				"faction": faction
			}
			if unit_id != "":
				spawn["unit_id"] = unit_id
			if unit_class != "":
				spawn["unit_class"] = unit_class
			var unit_name := str(props.get("unit_name", object_name)).strip_edges()
			if unit_name != "":
				spawn["unit_name"] = unit_name
			var ai_group := str(props.get("ai_group", "")).strip_edges().to_lower()
			if ai_group != "":
				spawn["ai_group"] = ai_group
			if props.has("q") and props.has("r"):
				spawn["tile"] = Vector2i(int(props["q"]), int(props["r"]))
			else:
				spawn["x"] = float(object_dict.get("x", 0.0))
				spawn["y"] = float(object_dict.get("y", 0.0))
			result.append(spawn)
	return result

static func _extract_transport_goal_from_tmj(tmj: Dictionary) -> Dictionary:
	var layers_variant: Variant = tmj.get("layers", [])
	if not (layers_variant is Array):
		return {}
	for layer_item in layers_variant:
		if not (layer_item is Dictionary):
			continue
		var layer := layer_item as Dictionary
		if str(layer.get("type", "")) != "objectgroup":
			continue
		var layer_name := str(layer.get("name", "")).to_lower()
		if layer_name != "goal_transport":
			continue
		var objects_variant: Variant = layer.get("objects", [])
		if not (objects_variant is Array):
			continue
		for object_item in objects_variant:
			if not (object_item is Dictionary):
				continue
			var object_dict := object_item as Dictionary
			var goal := {
				"x": float(object_dict.get("x", 0.0)),
				"y": float(object_dict.get("y", 0.0))
			}
			return goal
	return {}

static func _extract_capture_points_from_tmj(tmj: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var layers_variant: Variant = tmj.get("layers", [])
	if not (layers_variant is Array):
		return result
	for layer_item in layers_variant:
		if not (layer_item is Dictionary):
			continue
		var layer := layer_item as Dictionary
		if str(layer.get("type", "")) != "objectgroup":
			continue
		var layer_name := str(layer.get("name", "")).strip_edges().to_lower()
		var objects_variant: Variant = layer.get("objects", [])
		if not (objects_variant is Array):
			continue
		for object_item in objects_variant:
			if not (object_item is Dictionary):
				continue
			var object_dict := object_item as Dictionary
			var props := _properties_to_dict(object_dict.get("properties", []))
			var objective := str(props.get("objective", "")).strip_edges().to_lower()
			if layer_name != "capture_points" and objective != "capture_point":
				continue
			var object_name := str(object_dict.get("name", "")).strip_edges()
			var owner := str(props.get("owner", props.get("faction", "neutral"))).strip_edges().to_lower()
			if owner != "player" and owner != "enemy":
				owner = "neutral"
			var base_name := str(props.get("name", props.get("base_name", object_name))).strip_edges()
			var income := int(props.get("income", 0))
			var entry: Dictionary = {
				"owner": owner,
				"name": base_name,
				"income": income
			}
			if props.has("q") and props.has("r"):
				entry["tile"] = Vector2i(int(props["q"]), int(props["r"]))
			else:
				entry["x"] = float(object_dict.get("x", 0.0))
				entry["y"] = float(object_dict.get("y", 0.0))
			result.append(entry)
	return result

static func _properties_to_dict(raw_props: Variant) -> Dictionary:
	var result := {}
	if not (raw_props is Array):
		return result
	for prop_item in raw_props:
		if not (prop_item is Dictionary):
			continue
		var prop := prop_item as Dictionary
		var key := str(prop.get("name", "")).strip_edges()
		if key == "":
			continue
		result[key] = prop.get("value", null)
	return result
