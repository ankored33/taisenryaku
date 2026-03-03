extends Control

@onready var title_label: Label = $Margin/VBox/Title
@onready var summary_label: Label = $Margin/VBox/Summary
@onready var start_button: Button = $Margin/VBox/StartBattle

func _ready() -> void:
	var stage_id := GameFlow.get_current_stage_id()
	var stage_data := GameFlow.get_current_stage_data()
	title_label.text = "準備: %s" % stage_id
	summary_label.text = str(stage_data.get("prep_text", "編成を確認して出撃してください。"))
	start_button.pressed.connect(_on_start_battle_pressed)

func _on_start_battle_pressed() -> void:
	GameFlow.start_battle_from_prep()
