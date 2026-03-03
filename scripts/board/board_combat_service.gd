class_name BoardCombatService
extends RefCounted

const UnitModel = preload("res://scripts/board/unit_model.gd")

static func validate_attack_request(board: HexBoard, attacker_idx: int, defender_idx: int, distance: int) -> String:
	if attacker_idx < 0 or defender_idx < 0:
		return "攻撃対象が無効になりました。"
	if attacker_idx >= board.units.size() or defender_idx >= board.units.size():
		return "攻撃対象が無効になりました。"
	var attacker := UnitModel.new(board.units[attacker_idx])
	var defender := UnitModel.new(board.units[defender_idx])
	if attacker.faction() != board.current_faction:
		return "現在の手番陣営ではないため攻撃できません。"
	if defender.faction() == board.current_faction:
		return "味方は攻撃できません。"
	if attacker.is_attacked():
		return "%s はこのターンすでに攻撃済みです。" % attacker.name()
	if not board.query_can_unit_attack_at_range(attacker.data, distance):
		return "攻撃可能距離外です。"
	return ""

static func resolve_attack(board: HexBoard, attacker_idx: int, defender_idx: int, distance: int) -> void:
	if attacker_idx < 0 or defender_idx < 0:
		return
	if attacker_idx >= board.units.size() or defender_idx >= board.units.size():
		return
	board.is_battle_sequence_playing = true
	await board.cmd_play_attack_sequence(attacker_idx, defender_idx, distance)
	if attacker_idx >= board.units.size() or defender_idx >= board.units.size():
		board.is_battle_sequence_playing = false
		board.cmd_update_status("攻撃対象が無効になりました。")
		return
	var attacker := UnitModel.new(board.units[attacker_idx])
	var defender := UnitModel.new(board.units[defender_idx])
	var attacker_name := attacker.name()
	var defender_name := defender.name()
	var events: PackedStringArray = []

	var damage := attacker.atk()
	defender.set_hp(defender.hp() - damage)
	attacker.set_moved(true)
	attacker.set_attacked(true)
	board.action_sequence += 1
	board.cmd_clear_last_move_record()
	events.append("%s が %s に %d ダメージ" % [attacker_name, defender_name, damage])

	if defender.hp() <= 0:
		events.append("%s を撃破" % defender_name)
		board.cmd_remove_unit_at(defender_idx, "defeat")
		if defender_idx < attacker_idx:
			attacker_idx -= 1
	else:
		if board.query_can_unit_attack_at_range(defender.data, distance):
			var counter_damage := defender.atk()
			attacker.set_hp(attacker.hp() - counter_damage)
			events.append("%s の反撃で %d ダメージ" % [defender_name, counter_damage])
			if attacker.hp() <= 0:
				events.append("%s を撃破" % attacker_name)
				board.cmd_remove_unit_at(attacker_idx, "defeat")

	board.cmd_update_status("%s。準備ができたら「ターン終了」を押してください。" % "、".join(events))
	board.selected_unit_idx = -1
	board.cmd_set_unit_action_mode("")
	board.cmd_clear_unit_info()
	board.queue_redraw()
	board.is_battle_sequence_playing = false
