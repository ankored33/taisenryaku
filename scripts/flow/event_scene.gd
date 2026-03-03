extends Control

@onready var title_label: Label = $Margin/VBox/Title
@onready var body_label: Label = $Margin/VBox/Body
@onready var continue_button: Button = $Margin/VBox/Continue

func _ready() -> void:
	var payload := GameFlow.get_current_event_payload()
	title_label.text = str(payload.get("title", "イベント"))
	body_label.text = _to_text(payload.get("text", ""))
	continue_button.text = GameFlow.get_event_continue_label()
	continue_button.pressed.connect(_on_continue_pressed)

func _to_text(value: Variant) -> String:
	if value is Array:
		var lines: PackedStringArray = []
		for item in value:
			lines.append(str(item))
		return "\n".join(lines)
	return str(value)

func _on_continue_pressed() -> void:
	GameFlow.continue_from_event()
