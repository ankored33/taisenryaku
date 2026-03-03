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

	var timer := board.get_tree().create_timer(lifetime_sec + 0.45)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(effect_node):
			effect_node.queue_free()
	)
