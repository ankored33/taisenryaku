class_name BattleDefeatEffectService
extends RefCounted

static func load_config(path: String, fallback_config: Dictionary) -> Dictionary:
	var config := fallback_config.duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return config
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		config = (parsed as Dictionary).duplicate(true)
	return config

static func play_enemy_defeat_explosion(board: HexBoard, local_position: Vector2, config: Dictionary) -> void:
	var vfx_variant: Variant = config.get("vfx", {})
	var vfx: Dictionary = vfx_variant if vfx_variant is Dictionary else {}
	var vfx_type := str(vfx.get("type", "particles")).strip_edges().to_lower()
	var offset_y := 1.0
	var offset_variant: Variant = vfx.get("offset", [0, 1.0, 0])
	if offset_variant is Array:
		var offset_array := offset_variant as Array
		if offset_array.size() >= 2:
			offset_y = float(offset_array[1])
	var scale_factor := maxf(0.1, float(vfx.get("scale", 1.0)))
	var lifetime_sec := maxf(0.8, float(vfx.get("lifetime_sec", 1.8)))
	var effect_node := Node2D.new()
	effect_node.position = local_position + Vector2(0.0, -float(board.tile_height) * 0.5 * offset_y)
	board.add_child(effect_node)

	if vfx_type == "sprite_sheet":
		if _play_sprite_sheet(effect_node, vfx, scale_factor):
			_schedule_cleanup(board, effect_node, maxf(0.1, _sprite_sheet_duration_sec(vfx)))
			return

	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.lifetime = lifetime_sec
	particles.explosiveness = 1.0
	particles.amount = maxi(1, int(vfx.get("particle_count", 42)))
	particles.spread = 180.0
	particles.direction = Vector2.RIGHT
	particles.initial_velocity_min = maxf(0.0, float(vfx.get("particle_speed_min", 80.0))) * scale_factor
	particles.initial_velocity_max = maxf(particles.initial_velocity_min, float(vfx.get("particle_speed_max", 240.0)) * scale_factor)
	particles.gravity = Vector2(0.0, 280.0)
	particles.scale_amount_min = 0.7 * scale_factor
	particles.scale_amount_max = 1.6 * scale_factor

	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.76, 1.0),
		Color(1.0, 0.52, 0.22, 0.92),
		Color(0.36, 0.08, 0.05, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	particles.color_ramp = grad

	effect_node.add_child(particles)
	particles.emitting = true

	_schedule_cleanup(board, effect_node, lifetime_sec + 0.45)

static func _play_sprite_sheet(effect_node: Node2D, vfx: Dictionary, scale_factor: float) -> bool:
	var sheet_variant: Variant = vfx.get("sprite_sheet", {})
	if not (sheet_variant is Dictionary):
		return false
	var sheet := sheet_variant as Dictionary
	var texture_path := str(sheet.get("texture", "")).strip_edges()
	if texture_path == "":
		return false
	var loaded := load(texture_path)
	if not (loaded is Texture2D):
		return false
	var texture := loaded as Texture2D

	var frame_size := _sprite_frame_size(sheet, texture)
	var frame_w := int(frame_size.x)
	var frame_h := int(frame_size.y)
	if frame_w <= 0 or frame_h <= 0:
		return false
	var columns := maxi(1, int(sheet.get("columns", maxi(1, texture.get_width() / frame_w))))
	var rows := maxi(1, int(sheet.get("rows", maxi(1, texture.get_height() / frame_h))))
	var max_frames := maxi(1, columns * rows)
	var frames_count := clampi(int(sheet.get("frames", max_frames)), 1, max_frames)

	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("explode")
	sprite_frames.set_animation_loop("explode", false)
	sprite_frames.set_animation_speed("explode", maxf(1.0, float(sheet.get("fps", 24.0))))
	for frame_index in range(frames_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		var col := frame_index % columns
		var row := frame_index / columns
		atlas.region = Rect2(float(col * frame_w), float(row * frame_h), float(frame_w), float(frame_h))
		sprite_frames.add_frame("explode", atlas)

	var sprite := AnimatedSprite2D.new()
	sprite.centered = true
	sprite.scale = Vector2.ONE * scale_factor
	sprite.sprite_frames = sprite_frames
	sprite.animation = "explode"
	effect_node.add_child(sprite)
	sprite.play()
	return true

static func _sprite_frame_size(sheet: Dictionary, texture: Texture2D) -> Vector2i:
	var frame_w := int(sheet.get("frame_width", 0))
	var frame_h := int(sheet.get("frame_height", 0))
	if frame_w > 0 and frame_h > 0:
		return Vector2i(frame_w, frame_h)
	var size_variant: Variant = sheet.get("frame_size", [])
	if size_variant is Array:
		var size_array := size_variant as Array
		if size_array.size() >= 2:
			frame_w = int(size_array[0])
			frame_h = int(size_array[1])
	if frame_w > 0 and frame_h > 0:
		return Vector2i(frame_w, frame_h)
	var columns := maxi(1, int(sheet.get("columns", 1)))
	var rows := maxi(1, int(sheet.get("rows", 1)))
	return Vector2i(maxi(1, texture.get_width() / columns), maxi(1, texture.get_height() / rows))

static func _sprite_sheet_duration_sec(vfx: Dictionary) -> float:
	var sheet_variant: Variant = vfx.get("sprite_sheet", {})
	if not (sheet_variant is Dictionary):
		return maxf(0.1, float(vfx.get("lifetime_sec", 0.8)))
	var sheet := sheet_variant as Dictionary
	var fps := maxf(1.0, float(sheet.get("fps", 24.0)))
	var frames := maxi(1, int(sheet.get("frames", 1)))
	return maxf(0.1, float(vfx.get("lifetime_sec", float(frames) / fps)))

static func _schedule_cleanup(board: HexBoard, effect_node: Node2D, wait_sec: float) -> void:
	var timer := board.get_tree().create_timer(wait_sec + 0.08)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(effect_node):
			effect_node.queue_free()
	)
