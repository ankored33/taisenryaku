extends RefCounted
class_name ProductionDialogController

const POPUP_SIZE := Vector2i(720, 420)
const UnitCatalogDialogUtils = preload("res://scripts/ui/unit_catalog_dialog_utils.gd")

var canvas_layer: CanvasLayer
var board: HexBoard
var choose_action_handler: Callable
var clear_pending_handler: Callable

var entry_dialog: AcceptDialog
var confirm_dialog: ConfirmationDialog
var panel_header_label: Label
var catalog_panel: HBoxContainer
var catalog_grid: GridContainer
var detail_label: Label
var execute_button: Button
var option_group: ButtonGroup

var entries: Array[Dictionary] = []
var action_by_index := {}
var entry_by_index := {}
var button_by_index := {}
var selected_action := ""
var selected_entry: Dictionary = {}
var state_committing := false

func setup(
	layer: CanvasLayer,
	board_node: HexBoard,
	chosen_handler: Callable,
	cleared_handler: Callable
) -> void:
	canvas_layer = layer
	board = board_node
	choose_action_handler = chosen_handler
	clear_pending_handler = cleared_handler
	_ensure_ui()

func is_production_menu_payload(payload: Dictionary) -> bool:
	if str(payload.get("menu_type", "")).strip_edges().to_lower() == "production":
		return true
	var tile_variant: Variant = payload.get("tile", null)
	if tile_variant == null:
		return false
	var items_variant: Variant = payload.get("items", [])
	if not (items_variant is Array):
		return false
	for item_variant in (items_variant as Array):
		if not (item_variant is Dictionary):
			continue
		var action := str((item_variant as Dictionary).get("action", "")).strip_edges().to_lower()
		if action.begins_with("produce:"):
			return true
	return false

func open_from_payload(payload: Dictionary) -> void:
	_ensure_ui()
	if entry_dialog == null:
		return
	state_committing = false
	selected_action = ""
	selected_entry = {}
	action_by_index.clear()
	entry_by_index.clear()
	button_by_index.clear()
	entries.clear()
	var items_variant: Variant = payload.get("items", [])
	if items_variant is Array:
		for item_variant in (items_variant as Array):
			if item_variant is Dictionary:
				entries.append((item_variant as Dictionary).duplicate(true))
	var tile_text := ""
	var tile_variant: Variant = payload.get("tile", null)
	if tile_variant is Vector2i:
		var tile := tile_variant as Vector2i
		tile_text = "(%d,%d)" % [tile.x, tile.y]
	if panel_header_label != null:
		panel_header_label.text = "拠点 %s" % tile_text if tile_text != "" else "生産"
	if catalog_panel != null:
		catalog_panel.visible = true
	if detail_label != null:
		detail_label.text = "ユニットを選択してください。"
	if execute_button != null:
		execute_button.disabled = true
	_populate_catalog()
	entry_dialog.popup_centered(POPUP_SIZE)

func _ensure_ui() -> void:
	if entry_dialog == null:
		var existing := canvas_layer.get_node_or_null("ProductionEntryDialog")
		entry_dialog = existing as AcceptDialog if existing is AcceptDialog else null
	if entry_dialog == null:
		entry_dialog = AcceptDialog.new()
		entry_dialog.name = "ProductionEntryDialog"
		entry_dialog.title = "生産"
		entry_dialog.dialog_text = ""
		entry_dialog.exclusive = false
		canvas_layer.add_child(entry_dialog)
	if confirm_dialog == null:
		var existing_confirm := canvas_layer.get_node_or_null("ProductionConfirmDialog")
		confirm_dialog = existing_confirm as ConfirmationDialog if existing_confirm is ConfirmationDialog else null
	if confirm_dialog == null:
		confirm_dialog = ConfirmationDialog.new()
		confirm_dialog.name = "ProductionConfirmDialog"
		confirm_dialog.title = "生産確認"
		canvas_layer.add_child(confirm_dialog)

	var root_existing := entry_dialog.get_node_or_null("Root")
	if root_existing == null:
		var root := VBoxContainer.new()
		root.name = "Root"
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_theme_constant_override("separation", 8)
		entry_dialog.add_child(root)

		panel_header_label = Label.new()
		panel_header_label.name = "Header"
		panel_header_label.text = "生産"
		root.add_child(panel_header_label)

		catalog_panel = HBoxContainer.new()
		catalog_panel.name = "CatalogPanel"
		catalog_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		catalog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		catalog_panel.add_theme_constant_override("separation", 10)
		root.add_child(catalog_panel)

		var left_scroll := ScrollContainer.new()
		left_scroll.name = "OptionScroll"
		left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_scroll.custom_minimum_size = Vector2(420.0, 280.0)
		catalog_panel.add_child(left_scroll)

		catalog_grid = GridContainer.new()
		catalog_grid.name = "OptionGrid"
		catalog_grid.columns = 3
		catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		catalog_grid.add_theme_constant_override("h_separation", 8)
		catalog_grid.add_theme_constant_override("v_separation", 8)
		left_scroll.add_child(catalog_grid)

		var right_panel := VBoxContainer.new()
		right_panel.name = "DetailPanel"
		right_panel.custom_minimum_size = Vector2(230.0, 280.0)
		right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_panel.add_theme_constant_override("separation", 8)
		catalog_panel.add_child(right_panel)

		var detail_header := Label.new()
		detail_header.text = "性能"
		right_panel.add_child(detail_header)

		detail_label = Label.new()
		detail_label.name = "DetailLabel"
		detail_label.text = "ユニットを選択してください。"
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_panel.add_child(detail_label)

		execute_button = Button.new()
		execute_button.name = "ExecuteProductionButton"
		execute_button.text = "生産"
		execute_button.disabled = true
		right_panel.add_child(execute_button)

	if panel_header_label == null:
		panel_header_label = entry_dialog.get_node_or_null("Root/Header") as Label
	if catalog_panel == null:
		catalog_panel = entry_dialog.get_node_or_null("Root/CatalogPanel") as HBoxContainer
	if catalog_grid == null:
		catalog_grid = entry_dialog.get_node_or_null("Root/CatalogPanel/OptionScroll/OptionGrid") as GridContainer
	if detail_label == null:
		detail_label = entry_dialog.get_node_or_null("Root/CatalogPanel/DetailPanel/DetailLabel") as Label
	if execute_button == null:
		execute_button = entry_dialog.get_node_or_null("Root/CatalogPanel/DetailPanel/ExecuteProductionButton") as Button

	if entry_dialog != null:
		entry_dialog.exclusive = false
		var ok_button := entry_dialog.get_ok_button()
		if ok_button != null:
			ok_button.hide()
		if not entry_dialog.canceled.is_connected(_on_entry_dialog_closed):
			entry_dialog.canceled.connect(_on_entry_dialog_closed)
		if not entry_dialog.close_requested.is_connected(_on_entry_dialog_closed):
			entry_dialog.close_requested.connect(_on_entry_dialog_closed)
	if execute_button != null and not execute_button.pressed.is_connected(_on_execute_pressed):
		execute_button.pressed.connect(_on_execute_pressed)
	if confirm_dialog != null and not confirm_dialog.confirmed.is_connected(_on_confirmed):
		confirm_dialog.confirmed.connect(_on_confirmed)

func _clear_catalog_buttons() -> void:
	if catalog_grid == null:
		return
	for child in catalog_grid.get_children():
		child.queue_free()

func _populate_catalog() -> void:
	if catalog_grid == null:
		return
	_clear_catalog_buttons()
	action_by_index.clear()
	entry_by_index.clear()
	button_by_index.clear()
	selected_action = ""
	selected_entry = {}
	option_group = ButtonGroup.new()
	for i in entries.size():
		var entry := entries[i]
		var action := str(entry.get("action", "")).strip_edges().to_lower()
		if action == "":
			continue
		var unit_class := str(entry.get("unit_class", "")).strip_edges().to_lower()
		if unit_class == "":
			unit_class = action.trim_prefix("produce:")
		var catalog_entry := _catalog_entry_for(unit_class)
		var unit_name := str(entry.get("unit_name", catalog_entry.get("name", unit_class.capitalize())))
		var cost := int(entry.get("cost", catalog_entry.get("cost", 0)))
		var card := Button.new()
		card.custom_minimum_size = Vector2(132.0, 82.0)
		card.toggle_mode = true
		card.button_group = option_group
		card.expand_icon = true
		card.text = "%s\nMP %d" % [unit_name, cost]
		card.disabled = bool(entry.get("disabled", false))
		var preview_unit := _build_preview_unit(unit_class, catalog_entry)
		if board != null:
			card.icon = board.query_unit_icon_texture(preview_unit)
		card.pressed.connect(_on_option_pressed.bind(i))
		catalog_grid.add_child(card)
		action_by_index[i] = action
		entry_by_index[i] = catalog_entry
		button_by_index[i] = card
	if entries.is_empty() and detail_label != null:
		detail_label.text = "生産候補がありません。"
	if entries.is_empty() and execute_button != null:
		execute_button.disabled = true

func _catalog_entry_for(unit_class: String) -> Dictionary:
	return UnitCatalogDialogUtils.catalog_entry_for(board, unit_class)

func _build_preview_unit(unit_class: String, catalog_entry: Dictionary) -> Dictionary:
	return UnitCatalogDialogUtils.build_preview_unit(board, unit_class, catalog_entry, "player", true)

func _on_option_pressed(index: int) -> void:
	if not action_by_index.has(index):
		return
	selected_action = str(action_by_index.get(index, ""))
	selected_entry = entry_by_index.get(index, {}) as Dictionary
	var clicked_button_variant: Variant = button_by_index.get(index, null)
	var is_disabled := false
	if clicked_button_variant is Button:
		is_disabled = (clicked_button_variant as Button).disabled
	if execute_button != null:
		execute_button.disabled = is_disabled or selected_action == ""
	if detail_label != null:
		detail_label.text = _format_entry_text(selected_entry)

func _format_entry_text(entry: Dictionary) -> String:
	return UnitCatalogDialogUtils.format_entry_text(entry, true)

func _on_execute_pressed() -> void:
	if selected_action == "":
		return
	if confirm_dialog == null:
		return
	var name := str(selected_entry.get("name", "このユニット"))
	confirm_dialog.dialog_text = "%s を生産しますか？" % name
	confirm_dialog.popup_centered()

func _on_confirmed() -> void:
	if selected_action == "":
		return
	state_committing = true
	if choose_action_handler.is_valid():
		choose_action_handler.call(selected_action)
	if entry_dialog != null:
		entry_dialog.hide()
	state_committing = false

func _on_entry_dialog_closed() -> void:
	if state_committing:
		return
	if clear_pending_handler.is_valid():
		clear_pending_handler.call()
