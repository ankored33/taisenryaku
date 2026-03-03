extends RefCounted
class_name BgmEditorController

const FIELD_HINT := "res://... .ogg"
const POPUP_SIZE := Vector2i(720, 360)

var canvas_layer: CanvasLayer
var hud_controller: BattleHudController
var read_audio_config_handler: Callable
var save_audio_config_handler: Callable
var after_save_handler: Callable

var dialog: AcceptDialog
var path_fields := {}

func setup(
	layer: CanvasLayer,
	hud: BattleHudController,
	read_handler: Callable,
	save_handler: Callable,
	saved_handler: Callable = Callable()
) -> void:
	canvas_layer = layer
	hud_controller = hud
	read_audio_config_handler = read_handler
	save_audio_config_handler = save_handler
	after_save_handler = saved_handler
	_ensure_ui()

func layout() -> void:
	if hud_controller != null:
		hud_controller.layout_buttons()

func _ensure_ui() -> void:
	if hud_controller != null:
		hud_controller.ensure_button(
			"bgm_editor",
			"BgmEditorButton",
			"BGM設定",
			Vector2(120.0, 34.0),
			Callable(self, "_on_open_pressed")
		)
	_ensure_dialog()
	_sync_fields_from_stage()

func _ensure_dialog() -> void:
	if dialog == null:
		var existing := canvas_layer.get_node_or_null("BgmEditorDialog")
		dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if dialog == null:
		dialog = AcceptDialog.new()
		dialog.name = "BgmEditorDialog"
		dialog.title = "BGMエディタ"
		dialog.dialog_text = ""
		canvas_layer.add_child(dialog)
		dialog.confirmed.connect(_on_confirmed)

	var root_existing := dialog.get_node_or_null("Root")
	if root_existing != null:
		return

	var root := VBoxContainer.new()
	root.name = "Root"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "ステージBGM"
	root.add_child(title)

	_add_row(root, "インターミッション", "intermission")
	_add_row(root, "勝利", "victory")
	_add_row(root, "敗北", "defeat")
	_add_row(root, "完了", "complete")
	_add_row(root, "バトル(味方ターン)", "battle.player_turn")
	_add_row(root, "バトル(敵ターン)", "battle.enemy_turn")

	var hint := Label.new()
	hint.text = "例: res://assets/audio/bgm/stage01_player.ogg"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	dialog.add_child(root)

func _add_row(parent: VBoxContainer, label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(label)
	var line := LineEdit.new()
	line.placeholder_text = FIELD_HINT
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	path_fields[key] = line
	parent.add_child(row)

func _on_open_pressed() -> void:
	_sync_fields_from_stage()
	if dialog != null:
		dialog.popup_centered(POPUP_SIZE)

func _sync_fields_from_stage() -> void:
	var audio := _read_stage_audio_config()
	var battle_variant: Variant = audio.get("battle", {})
	var battle: Dictionary = battle_variant if battle_variant is Dictionary else {}
	_set_field("intermission", str(audio.get("intermission", "")))
	_set_field("victory", str(audio.get("victory", "")))
	_set_field("defeat", str(audio.get("defeat", "")))
	_set_field("complete", str(audio.get("complete", "")))
	_set_field("battle.player_turn", str(battle.get("player_turn", "")))
	_set_field("battle.enemy_turn", str(battle.get("enemy_turn", "")))

func _set_field(key: String, value: String) -> void:
	var field_variant: Variant = path_fields.get(key, null)
	if field_variant is LineEdit:
		(field_variant as LineEdit).text = value

func _get_field(key: String) -> String:
	var field_variant: Variant = path_fields.get(key, null)
	if field_variant is LineEdit:
		return str((field_variant as LineEdit).text).strip_edges()
	return ""

func _read_stage_audio_config() -> Dictionary:
	if not read_audio_config_handler.is_valid():
		return {}
	var value: Variant = read_audio_config_handler.call()
	return value as Dictionary if value is Dictionary else {}

func _on_confirmed() -> void:
	if not save_audio_config_handler.is_valid():
		return
	var next_audio := {
		"intermission": _get_field("intermission"),
		"victory": _get_field("victory"),
		"defeat": _get_field("defeat"),
		"complete": _get_field("complete"),
		"battle": {
			"player_turn": _get_field("battle.player_turn"),
			"enemy_turn": _get_field("battle.enemy_turn")
		}
	}
	var result: Variant = save_audio_config_handler.call(next_audio)
	if bool(result) and after_save_handler.is_valid():
		after_save_handler.call()
