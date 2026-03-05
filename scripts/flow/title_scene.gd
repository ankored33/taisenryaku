extends Control

@onready var start_button: Button = $Margin/VBox/Menu/StartButton
@onready var continue_button: Button = $Margin/VBox/Menu/ContinueButton
@onready var settings_button: Button = $Margin/VBox/Menu/SettingsButton
@onready var quit_button: Button = $Margin/VBox/Menu/QuitButton
@onready var settings_dialog: AcceptDialog = $SettingsDialog
@onready var bgm_slider: HSlider = $SettingsDialog/Margin/VBox/BgmRow/BgmSlider
@onready var bgm_value_label: Label = $SettingsDialog/Margin/VBox/BgmRow/BgmValue
@onready var se_slider: HSlider = $SettingsDialog/Margin/VBox/SeRow/SeSlider
@onready var se_value_label: Label = $SettingsDialog/Margin/VBox/SeRow/SeValue
@onready var notice_label: Label = $Margin/VBox/Notice

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	bgm_slider.value_changed.connect(_on_bgm_changed)
	se_slider.value_changed.connect(_on_se_changed)
	_load_volume_values()
	notice_label.text = "続きから: 現在は「はじめる」と同じ動作です。"

func _on_start_pressed() -> void:
	GameFlow.start_new_game()

func _on_continue_pressed() -> void:
	GameFlow.start_new_game()

func _on_settings_pressed() -> void:
	settings_dialog.popup_centered(Vector2i(560, 300))

func _on_quit_pressed() -> void:
	get_tree().quit()

func _load_volume_values() -> void:
	var bgm_db := -8.0
	var se_db := -6.0
	if has_node("/root/AudioManager"):
		if AudioManager.has_method("get_bgm_volume_db"):
			bgm_db = float(AudioManager.get_bgm_volume_db())
		if AudioManager.has_method("get_se_volume_db"):
			se_db = float(AudioManager.get_se_volume_db())
	bgm_slider.value = bgm_db
	se_slider.value = se_db
	_update_value_labels()

func _on_bgm_changed(value: float) -> void:
	if has_node("/root/AudioManager") and AudioManager.has_method("set_bgm_volume_db"):
		AudioManager.set_bgm_volume_db(value)
	_update_value_labels()

func _on_se_changed(value: float) -> void:
	if has_node("/root/AudioManager") and AudioManager.has_method("set_se_volume_db"):
		AudioManager.set_se_volume_db(value)
	_update_value_labels()

func _update_value_labels() -> void:
	bgm_value_label.text = "%.1f dB" % bgm_slider.value
	se_value_label.text = "%.1f dB" % se_slider.value
