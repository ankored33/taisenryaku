extends Node

const EVENT_SCENE_PATH := "res://scenes/flow/event_scene.tscn"
const PREP_SCENE_PATH := "res://scenes/flow/prep_scene.tscn"
const STAGE_SELECT_SCENE_PATH := "res://scenes/flow/stage_select_scene.tscn"
const TiledStageLoader = preload("res://scripts/data/tiled_stage_loader.gd")
const CAMPAIGN_DATA_PATH := "res://data/campaign.json"
const PROGRESSION_PATH := "user://campaign_progress.json"

var campaign_girls: Array[Dictionary] = []
var selected_girl_id := ""
var selected_stage_index := -1
var current_stage_data: Dictionary = {}
var current_stage_source_data: Dictionary = {}
var current_stage_source_path := ""
var current_stage_id := ""
var current_phase := ""
var last_battle_victory := true
var progress_unlocked := {}
var progress_cleared := {}
var stage_select_notice := ""

func start_new_game() -> void:
	_load_campaign_data()
	_load_progress()
	if selected_girl_id == "":
		if campaign_girls.is_empty():
			current_stage_data = {}
			current_stage_source_data = {}
			current_stage_source_path = ""
			current_stage_id = ""
			_change_phase("complete")
			return
		selected_girl_id = str(campaign_girls[0].get("id", ""))
	selected_stage_index = -1
	current_stage_data = {}
	current_stage_source_data = {}
	current_stage_source_path = ""
	current_stage_id = ""
	stage_select_notice = ""
	_change_phase("stage_select")

func get_current_stage_id() -> String:
	return current_stage_id

func get_current_stage_data() -> Dictionary:
	return current_stage_data

func get_current_phase() -> String:
	return current_phase

func get_campaign_girls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for girl in campaign_girls:
		var girl_id := str(girl.get("id", ""))
		var stage_count := _get_stage_count(girl_id)
		result.append({
			"id": girl_id,
			"name": str(girl.get("name", girl_id)),
			"stage_count": stage_count,
			"unlocked_count": _get_unlocked_count(girl_id)
		})
	return result

func get_selected_girl_id() -> String:
	return selected_girl_id

func get_selected_girl_name() -> String:
	var idx := _find_girl_index(selected_girl_id)
	if idx == -1:
		return selected_girl_id
	return str(campaign_girls[idx].get("name", selected_girl_id))

func select_girl(girl_id: String) -> bool:
	var normalized := girl_id.strip_edges().to_lower()
	if _find_girl_index(normalized) == -1:
		return false
	selected_girl_id = normalized
	selected_stage_index = -1
	stage_select_notice = ""
	return true

func get_selected_girl_stages() -> Array[Dictionary]:
	return _build_stage_entries(selected_girl_id)

func get_stage_select_notice() -> String:
	return stage_select_notice

func start_selected_stage(stage_index: int) -> bool:
	return start_stage(selected_girl_id, stage_index)

func select_stage_for_edit(stage_index: int) -> bool:
	return _prepare_stage_selection(selected_girl_id, stage_index)

func debug_start_stage_battle(girl_id: String, stage_index: int) -> bool:
	if not _prepare_stage_selection(girl_id, stage_index):
		return false
	last_battle_victory = true
	_change_phase("battle")
	return true

func start_stage(girl_id: String, stage_index: int) -> bool:
	if not _prepare_stage_selection(girl_id, stage_index, true):
		return false
	_change_phase("event_before")
	return true

func get_current_stage_audio_config() -> Dictionary:
	return _normalize_audio_config(_get_audio_config())

func get_current_event_payload() -> Dictionary:
	if current_phase == "complete":
		return {
			"title": "作戦完了",
			"text": "設定された全ステージをクリアしました。",
			"image": ""
		}
	if current_phase == "event_before":
		return current_stage_data.get("event_before", {})
	if current_phase == "event_after":
		var key := "event_after_victory" if last_battle_victory else "event_after_defeat"
		return current_stage_data.get(key, {})
	return {}

func get_event_continue_label() -> String:
	if current_phase == "event_before":
		return "準備へ"
	if current_phase == "event_after":
		return "ステージ選択へ"
	if current_phase == "complete":
		return "最初から"
	return "続ける"

func get_current_stage_event_data(event_key: String) -> Dictionary:
	var key := _normalize_event_key(event_key)
	if key == "":
		return {}
	var value: Variant = current_stage_data.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}

func update_current_stage_event_data(event_key: String, event_data: Dictionary) -> bool:
	if current_stage_source_path == "":
		return false
	var key := _normalize_event_key(event_key)
	if key == "":
		return false
	current_stage_source_data[key] = _normalize_stage_event_data(event_data)
	return _save_current_stage_source()

func continue_from_event() -> void:
	if current_phase == "event_before":
		_change_phase("prep")
		return
	if current_phase == "event_after":
		_change_phase("stage_select")
		return
	if current_phase == "complete":
		start_new_game()

func start_battle_from_prep() -> void:
	if current_phase != "prep":
		return
	_change_phase("battle")

func report_battle_result(victory: bool) -> void:
	if current_phase != "battle":
		return
	last_battle_victory = victory
	if victory:
		_mark_stage_cleared_and_unlock_next()
	_change_phase("event_after")

func play_battle_turn_bgm(turn_faction: String, ai_faction: String = "enemy") -> void:
	if current_phase != "battle":
		return
	var path := _resolve_battle_turn_bgm(turn_faction, ai_faction)
	if path == "":
		return
	_play_bgm(path)

func update_current_stage_audio(audio_config: Dictionary) -> bool:
	if current_stage_source_path == "":
		return false
	current_stage_source_data["audio"] = _normalize_audio_config(audio_config)
	var saved := _save_current_stage_source()
	if saved:
		_play_phase_bgm(current_phase)
	return saved

func update_current_stage_enemy_ai_production(unit_classes: Array, enabled: bool = true) -> bool:
	if current_stage_source_path == "":
		return false
	var normalized := _normalize_unit_class_list(unit_classes)
	var ai_variant: Variant = current_stage_source_data.get("ai_production", {})
	var ai_production := ai_variant as Dictionary if ai_variant is Dictionary else {}
	if not enabled:
		ai_production.erase("enemy")
	else:
		ai_production["enemy"] = normalized
	if ai_production.is_empty():
		current_stage_source_data.erase("ai_production")
	else:
		current_stage_source_data["ai_production"] = ai_production
	return _save_current_stage_source()

func _change_phase(next_phase: String) -> void:
	current_phase = next_phase
	_play_phase_bgm(next_phase)
	if next_phase == "battle":
		var battle_scene := str(current_stage_data.get("battle_scene", "res://scenes/battle/battle_scene.tscn"))
		get_tree().call_deferred("change_scene_to_file", battle_scene)
		return
	if next_phase == "prep":
		get_tree().call_deferred("change_scene_to_file", PREP_SCENE_PATH)
		return
	if next_phase == "stage_select":
		get_tree().call_deferred("change_scene_to_file", STAGE_SELECT_SCENE_PATH)
		return
	get_tree().call_deferred("change_scene_to_file", EVENT_SCENE_PATH)

func _prepare_stage_selection(girl_id: String, stage_index: int, require_unlocked: bool = false) -> bool:
	stage_select_notice = ""
	if campaign_girls.is_empty():
		_load_campaign_data()
	if require_unlocked and progress_unlocked.is_empty():
		_load_progress()
	var normalized := girl_id.strip_edges().to_lower()
	if _find_girl_index(normalized) == -1:
		stage_select_notice = "存在しないキャラクターです。"
		return false
	if require_unlocked and not _is_stage_unlocked(normalized, stage_index):
		stage_select_notice = "このステージは未開放です。"
		return false
	var stage_id := _get_stage_id_for_index(normalized, stage_index)
	if stage_id == "":
		return false
	selected_girl_id = normalized
	selected_stage_index = stage_index
	current_stage_id = stage_id
	_load_stage_data_by_id(stage_id)
	if current_stage_data.is_empty():
		stage_select_notice = "ステージデータの読み込みに失敗しました。"
		return false
	return true

func _get_stage_id_for_index(girl_id: String, stage_index: int) -> String:
	var stage_ids := _get_stage_ids(girl_id)
	if stage_index < 0 or stage_index >= stage_ids.size():
		stage_select_notice = "存在しないステージです。"
		return ""
	var stage_id := str(stage_ids[stage_index])
	if stage_id == "":
		stage_select_notice = "ステージIDが設定されていません。"
		return ""
	if not _stage_file_exists(stage_id):
		stage_select_notice = "このステージはまだ未実装です。"
		return ""
	return stage_id

func _save_current_stage_source() -> bool:
	var file := FileAccess.open(current_stage_source_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(current_stage_source_data, "\t"))
	current_stage_data = TiledStageLoader.apply_tiled_map(current_stage_source_data.duplicate(true), current_stage_source_path)
	return true

func _load_stage_data_by_id(stage_id: String) -> void:
	if stage_id.strip_edges() == "":
		current_stage_data = {}
		current_stage_source_data = {}
		current_stage_source_path = ""
		return
	var path := "res://data/stages/%s.json" % stage_id
	current_stage_source_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		current_stage_data = {}
		current_stage_source_data = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	current_stage_source_data = parsed if parsed is Dictionary else {}
	current_stage_data = TiledStageLoader.apply_tiled_map(current_stage_source_data.duplicate(true), path)

func _load_campaign_data() -> void:
	campaign_girls.clear()
	var file := FileAccess.open(CAMPAIGN_DATA_PATH, FileAccess.READ)
	var parsed: Variant = null
	if file != null:
		parsed = JSON.parse_string(file.get_as_text())
	var src: Dictionary = parsed if parsed is Dictionary else _default_campaign_data()
	var girls_variant: Variant = src.get("girls", [])
	if girls_variant is Array:
		for item in girls_variant:
			if not (item is Dictionary):
				continue
			var raw := item as Dictionary
			var girl_id := str(raw.get("id", "")).strip_edges().to_lower()
			if girl_id == "":
				continue
			var stages: Array[String] = []
			var stages_variant: Variant = raw.get("stages", [])
			if stages_variant is Array:
				for stage_item in stages_variant:
					var stage_id := str(stage_item).strip_edges().to_lower()
					stages.append(stage_id)
			campaign_girls.append({
				"id": girl_id,
				"name": str(raw.get("name", girl_id)),
				"stages": stages
			})
	if campaign_girls.is_empty():
		var fallback := _default_campaign_data()
		var fallback_girls: Variant = fallback.get("girls", [])
		if fallback_girls is Array:
			for item in fallback_girls:
				if item is Dictionary:
					campaign_girls.append((item as Dictionary).duplicate(true))

func _default_campaign_data() -> Dictionary:
	return {
		"girls": [
			{
				"id": "girl_a",
				"name": "ガールA",
				"stages": ["stage_01", "girl_a_02", "girl_a_03", "girl_a_04", "girl_a_05"]
			},
			{
				"id": "girl_b",
				"name": "ガールB",
				"stages": ["girl_b_01", "girl_b_02", "girl_b_03", "girl_b_04", "girl_b_05"]
			},
			{
				"id": "girl_c",
				"name": "ガールC",
				"stages": ["girl_c_01", "girl_c_02", "girl_c_03", "girl_c_04", "girl_c_05"]
			}
		]
	}

func _load_progress() -> void:
	progress_unlocked = {}
	progress_cleared = {}
	var file := FileAccess.open(PROGRESSION_PATH, FileAccess.READ)
	var parsed: Variant = null
	if file != null:
		parsed = JSON.parse_string(file.get_as_text())
	var src: Dictionary = parsed if parsed is Dictionary else {}
	var unlocked_src: Dictionary = src.get("unlocked", {}) if src is Dictionary else {}
	var cleared_src: Dictionary = src.get("cleared", {}) if src is Dictionary else {}
	for girl in campaign_girls:
		var girl_id := str(girl.get("id", ""))
		var stage_count := _get_stage_count(girl_id)
		if stage_count <= 0:
			progress_unlocked[girl_id] = 0
			progress_cleared[girl_id] = []
			continue
		var unlocked_value := int(unlocked_src.get(girl_id, 1))
		progress_unlocked[girl_id] = clampi(unlocked_value, 1, stage_count)
		var cleared_flags: Array[bool] = []
		var saved_flags_variant: Variant = cleared_src.get(girl_id, [])
		var saved_flags: Array = saved_flags_variant as Array if saved_flags_variant is Array else []
		for i in stage_count:
			var flag := false
			if i < saved_flags.size():
				flag = bool(saved_flags[i])
			cleared_flags.append(flag)
		progress_cleared[girl_id] = cleared_flags
	_save_progress()

func _save_progress() -> void:
	var payload := {
		"unlocked": progress_unlocked,
		"cleared": progress_cleared
	}
	var file := FileAccess.open(PROGRESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))

func _mark_stage_cleared_and_unlock_next() -> void:
	if selected_girl_id == "" or selected_stage_index < 0:
		return
	_set_stage_cleared(selected_girl_id, selected_stage_index, true)
	var stage_count := _get_stage_count(selected_girl_id)
	if stage_count <= 0:
		return
	var current_unlocked := _get_unlocked_count(selected_girl_id)
	var next_unlocked := mini(stage_count, selected_stage_index + 2)
	if next_unlocked > current_unlocked:
		progress_unlocked[selected_girl_id] = next_unlocked
	_save_progress()

func _set_stage_cleared(girl_id: String, stage_index: int, cleared: bool) -> void:
	var stage_count := _get_stage_count(girl_id)
	if stage_index < 0 or stage_index >= stage_count:
		return
	var flags_variant: Variant = progress_cleared.get(girl_id, [])
	var flags: Array[bool] = []
	if flags_variant is Array:
		for value in flags_variant:
			flags.append(bool(value))
	while flags.size() < stage_count:
		flags.append(false)
	flags[stage_index] = cleared
	progress_cleared[girl_id] = flags

func _find_girl_index(girl_id: String) -> int:
	var normalized := girl_id.strip_edges().to_lower()
	for i in campaign_girls.size():
		if str(campaign_girls[i].get("id", "")) == normalized:
			return i
	return -1

func _get_stage_ids(girl_id: String) -> Array[String]:
	var idx := _find_girl_index(girl_id)
	if idx == -1:
		return []
	var stages_variant: Variant = campaign_girls[idx].get("stages", [])
	var result: Array[String] = []
	if stages_variant is Array:
		for item in stages_variant:
			result.append(str(item))
	return result

func _get_stage_count(girl_id: String) -> int:
	return _get_stage_ids(girl_id).size()

func _get_unlocked_count(girl_id: String) -> int:
	var stage_count := _get_stage_count(girl_id)
	if stage_count <= 0:
		return 0
	var unlocked := int(progress_unlocked.get(girl_id, 1))
	return clampi(unlocked, 1, stage_count)

func _is_stage_unlocked(girl_id: String, stage_index: int) -> bool:
	return stage_index >= 0 and stage_index < _get_unlocked_count(girl_id)

func _is_stage_cleared(girl_id: String, stage_index: int) -> bool:
	var flags_variant: Variant = progress_cleared.get(girl_id, [])
	if not (flags_variant is Array):
		return false
	var flags := flags_variant as Array
	if stage_index < 0 or stage_index >= flags.size():
		return false
	return bool(flags[stage_index])

func _stage_file_exists(stage_id: String) -> bool:
	var path := "res://data/stages/%s.json" % stage_id.strip_edges().to_lower()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	file.close()
	return true

func _build_stage_entries(girl_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stage_ids := _get_stage_ids(girl_id)
	for i in stage_ids.size():
		var stage_id := str(stage_ids[i])
		var unlocked := _is_stage_unlocked(girl_id, i)
		var cleared := _is_stage_cleared(girl_id, i)
		var exists := _stage_file_exists(stage_id)
		result.append({
			"index": i,
			"label": "STAGE %d" % (i + 1),
			"stage_id": stage_id,
			"unlocked": unlocked,
			"cleared": cleared,
			"exists": exists
		})
	return result

func _play_phase_bgm(phase: String) -> void:
	var path := _resolve_phase_bgm(phase)
	if path == "":
		return
	_play_bgm(path)

func _play_bgm(path: String) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return
	audio_manager.play_bgm(path)

func _resolve_phase_bgm(phase: String) -> String:
	var audio := _get_audio_config()
	var intermission_bgm := str(audio.get("intermission", ""))
	if phase == "battle":
		var player_turn_bgm := _resolve_battle_turn_bgm("player", "enemy")
		return player_turn_bgm if player_turn_bgm != "" else intermission_bgm
	if phase == "stage_select":
		return intermission_bgm
	if phase == "prep":
		return intermission_bgm
	if phase == "event_before":
		return intermission_bgm
	if phase == "event_after":
		if last_battle_victory:
			return str(audio.get("victory", intermission_bgm))
		return str(audio.get("defeat", intermission_bgm))
	if phase == "complete":
		return str(audio.get("complete", intermission_bgm))
	return intermission_bgm

func _resolve_battle_turn_bgm(turn_faction: String, ai_faction: String) -> String:
	var audio := _get_audio_config()
	var battle_variant: Variant = audio.get("battle", {})
	var battle: Dictionary = battle_variant if battle_variant is Dictionary else {}
	var key := "enemy_turn" if turn_faction == ai_faction else "player_turn"
	var path := str(battle.get(key, ""))
	if path != "":
		return path
	return str(audio.get("intermission", ""))

func _get_audio_config() -> Dictionary:
	var audio_variant: Variant = current_stage_data.get("audio", {})
	return audio_variant if audio_variant is Dictionary else {}

func _normalize_audio_config(audio_variant: Variant) -> Dictionary:
	var src: Dictionary = audio_variant if audio_variant is Dictionary else {}
	var battle_variant: Variant = src.get("battle", {})
	var battle_src: Dictionary = battle_variant if battle_variant is Dictionary else {}
	return {
		"intermission": str(src.get("intermission", "")),
		"victory": str(src.get("victory", "")),
		"defeat": str(src.get("defeat", "")),
		"complete": str(src.get("complete", "")),
		"battle": {
			"player_turn": str(battle_src.get("player_turn", "")),
			"enemy_turn": str(battle_src.get("enemy_turn", ""))
		}
	}

func _normalize_unit_class_list(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (raw is Array):
		return result
	var seen := {}
	for item in (raw as Array):
		var unit_class := str(item).strip_edges().to_lower()
		if unit_class == "" or seen.has(unit_class):
			continue
		seen[unit_class] = true
		result.append(unit_class)
	return result

func _normalize_event_key(event_key: String) -> String:
	var key := event_key.strip_edges().to_lower()
	if key == "event_before" or key == "event_after_victory" or key == "event_after_defeat":
		return key
	return ""

func _normalize_stage_event_data(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var title := str(src.get("title", "イベント"))
	var image := str(src.get("image", "")).strip_edges()
	var bgm := str(src.get("bgm", "")).strip_edges()
	var se := str(src.get("se", "")).strip_edges()
	var cuts := _normalize_event_cuts(src, image, bgm, se)
	return {
		"title": title,
		"text": src.get("text", ""),
		"image": image,
		"bgm": bgm,
		"se": se,
		"cuts": cuts
	}

func _normalize_event_cuts(src: Dictionary, default_image: String, default_bgm: String, default_se: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cuts_variant: Variant = src.get("cuts", [])
	if cuts_variant is Array and not (cuts_variant as Array).is_empty():
		for item in (cuts_variant as Array):
			if not (item is Dictionary):
				continue
			var cut := item as Dictionary
			result.append({
				"title": str(cut.get("title", "")),
				"text": str(cut.get("text", "")),
				"image": str(cut.get("image", "")).strip_edges(),
				"bgm": str(cut.get("bgm", "")).strip_edges(),
				"se": str(cut.get("se", "")).strip_edges()
			})
		if not result.is_empty():
			return result
	var pages_variant: Variant = src.get("pages", [])
	if pages_variant is Array and not (pages_variant as Array).is_empty():
		for item in (pages_variant as Array):
			if not (item is Dictionary):
				continue
			var page := item as Dictionary
			result.append({
				"title": str(page.get("title", "")),
				"text": str(page.get("text", "")),
				"image": str(page.get("image", "")).strip_edges(),
				"bgm": str(page.get("bgm", "")).strip_edges(),
				"se": str(page.get("se", "")).strip_edges()
			})
		if not result.is_empty():
			return result
	var text_variant: Variant = src.get("text", "")
	if text_variant is Array:
		for line in (text_variant as Array):
			result.append({
				"title": "",
				"text": str(line),
				"image": default_image,
				"bgm": default_bgm,
				"se": ""
			})
	else:
		result.append({
			"title": "",
			"text": str(text_variant),
			"image": default_image,
			"bgm": default_bgm,
			"se": default_se
		})
	return result
