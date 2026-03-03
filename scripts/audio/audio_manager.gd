extends Node

const SETTINGS_PATH := "user://system_settings.json"
const DEFAULT_BGM_VOLUME_DB := -8.0
const DEFAULT_SE_VOLUME_DB := -6.0

var bgm_player: AudioStreamPlayer
var current_bgm_path := ""
var bgm_volume_db := DEFAULT_BGM_VOLUME_DB
var se_volume_db := DEFAULT_SE_VOLUME_DB

func _ready() -> void:
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	bgm_player.autoplay = false
	_load_settings()

func play_bgm(path: String, volume_db: float = NAN) -> void:
	var normalized := path.strip_edges()
	if normalized == "":
		stop_bgm()
		return
	if normalized == current_bgm_path and bgm_player.playing:
		return
	var stream := load(normalized) as AudioStream
	if stream == null:
		push_warning("BGMの読み込みに失敗: %s" % normalized)
		return
	current_bgm_path = normalized
	bgm_player.stream = stream
	if is_nan(volume_db):
		bgm_player.volume_db = bgm_volume_db
	else:
		bgm_player.volume_db = volume_db
	bgm_player.play()

func stop_bgm() -> void:
	current_bgm_path = ""
	if bgm_player != null and bgm_player.playing:
		bgm_player.stop()

func set_bgm_volume_db(value: float) -> void:
	bgm_volume_db = clampf(value, -40.0, 6.0)
	if bgm_player != null:
		bgm_player.volume_db = bgm_volume_db
	_save_settings()

func get_bgm_volume_db() -> float:
	return bgm_volume_db

func set_se_volume_db(value: float) -> void:
	se_volume_db = clampf(value, -40.0, 6.0)
	_save_settings()

func get_se_volume_db() -> float:
	return se_volume_db

func _load_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var src := parsed as Dictionary
	bgm_volume_db = clampf(float(src.get("bgm_volume_db", DEFAULT_BGM_VOLUME_DB)), -40.0, 6.0)
	se_volume_db = clampf(float(src.get("se_volume_db", DEFAULT_SE_VOLUME_DB)), -40.0, 6.0)

func _save_settings() -> void:
	var payload := {
		"bgm_volume_db": bgm_volume_db,
		"se_volume_db": se_volume_db
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
