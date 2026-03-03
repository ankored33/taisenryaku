extends RefCounted
class_name DeploymentDialogController

const UnitCatalogDialogUtils = preload("res://scripts/ui/unit_catalog_dialog_utils.gd")

var canvas_layer: CanvasLayer
var board: HexBoard
var select_handler: Callable
var finish_handler: Callable
var left_panel_container: Control

var root_panel: PanelContainer
var header_label: Label
var mp_label: Label
var catalog_list: VBoxContainer
var detail_label: Label
var finish_button: Button
var footer_finish_button: Button
var option_group: ButtonGroup
var detail_expand_panel: PanelContainer
var detail_expand_label: Label
var finish_confirm_dialog: ConfirmationDialog
var replaced_nodes: Array[Dictionary] = []

var entries: Array[Dictionary] = []
var class_by_index := {}
var entry_by_index := {}
var deployment_faction := "player"
var current_mp := -1

func setup(layer: CanvasLayer, board_node: HexBoard, on_select: Callable, on_finish: Callable, panel_container: Control = null) -> void:
	canvas_layer = layer
	board = board_node
	select_handler = on_select
	finish_handler = on_finish
	left_panel_container = panel_container
	_ensure_ui()

func is_deployment_menu_payload(payload: Dictionary) -> bool:
	return str(payload.get("menu_type", "")).strip_edges().to_lower() == "deployment"

func open_from_payload(payload: Dictionary) -> void:
	_ensure_ui()
	if root_panel == null:
		return
	_enter_replacement_mode()
	entries.clear()
	class_by_index.clear()
	entry_by_index.clear()
	deployment_faction = str(payload.get("faction", "player")).strip_edges().to_lower()
	current_mp = int(payload.get("mp", -1))
	var items_variant: Variant = payload.get("items", [])
	if items_variant is Array:
		for item_variant in (items_variant as Array):
			if item_variant is Dictionary:
				entries.append((item_variant as Dictionary).duplicate(true))
	if header_label != null:
		header_label.text = "初期配置"
	_update_mp_label()
	if detail_label != null:
		detail_label.text = "ユニットを選択すると、右側に性能を表示します。"
	_hide_expanded_detail()
	_populate_catalog()
	_show_panel_finish_button()
	root_panel.visible = true
	_layout_expanded_detail_panel()
	_hide_footer_finish_button()

func _ensure_ui() -> void:
	if left_panel_container == null:
		var fallback := canvas_layer.get_node_or_null("LeftPanel/Margin/VBox")
		left_panel_container = fallback as Control if fallback is Control else null
	if left_panel_container == null:
		return
	if root_panel == null:
		var existing := left_panel_container.get_node_or_null("DeploymentPanel")
		root_panel = existing as PanelContainer if existing is PanelContainer else null
	if root_panel == null:
		root_panel = PanelContainer.new()
		root_panel.name = "DeploymentPanel"
		root_panel.visible = false
		root_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_panel_container.add_child(root_panel)

	var margin_nodes: Array[Node] = []
	for child in root_panel.get_children():
		if child is MarginContainer and str((child as Node).name) == "Margin":
			margin_nodes.append(child)
	if margin_nodes.size() > 1:
		for i in range(1, margin_nodes.size()):
			margin_nodes[i].queue_free()

	var root_existing := root_panel.get_node_or_null("Margin/Root")
	if root_existing == null:
		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_panel.add_child(margin)

		var root := VBoxContainer.new()
		root.name = "Root"
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_theme_constant_override("separation", 6)
		margin.add_child(root)

		header_label = Label.new()
		header_label.name = "Header"
		header_label.text = "初期配置"
		header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(header_label)
		
		mp_label = Label.new()
		mp_label.name = "MpLabel"
		mp_label.text = "現MP: 0"
		root.add_child(mp_label)

		finish_button = Button.new()
		finish_button.name = "FinishDeploymentButton"
		finish_button.text = "配置終了"
		finish_button.custom_minimum_size = Vector2(0.0, 44.0)
		finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		finish_button.size_flags_vertical = Control.SIZE_SHRINK_END
		finish_button.size_flags_stretch_ratio = 0.0
		finish_button.add_theme_font_size_override("font_size", 16)
		finish_button.visible = false
		root.add_child(finish_button)

		var content := VBoxContainer.new()
		content.name = "Content"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 6)
		root.add_child(content)

		var option_header := Label.new()
		option_header.text = "配置ユニット"
		content.add_child(option_header)

		var option_scroll := ScrollContainer.new()
		option_scroll.name = "OptionScroll"
		option_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(option_scroll)

		catalog_list = VBoxContainer.new()
		catalog_list.name = "OptionList"
		catalog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		catalog_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		catalog_list.add_theme_constant_override("separation", 4)
		option_scroll.add_child(catalog_list)

		var detail_header := Label.new()
		detail_header.text = "性能"
		content.add_child(detail_header)

		detail_label = Label.new()
		detail_label.name = "DetailLabel"
		detail_label.text = "ユニットを選択してください。"
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		content.add_child(detail_label)

	if header_label == null:
		header_label = root_panel.get_node_or_null("Margin/Root/Header") as Label
	if mp_label == null:
		mp_label = root_panel.get_node_or_null("Margin/Root/MpLabel") as Label
	if catalog_list == null:
		catalog_list = root_panel.get_node_or_null("Margin/Root/Content/OptionScroll/OptionList") as VBoxContainer
	if detail_label == null:
		detail_label = root_panel.get_node_or_null("Margin/Root/Content/DetailLabel") as Label
	if finish_button == null:
		finish_button = root_panel.get_node_or_null("Margin/Root/FinishDeploymentButton") as Button
	if finish_button == null:
		var root := root_panel.get_node_or_null("Margin/Root") as VBoxContainer
		if root != null:
			finish_button = Button.new()
			finish_button.name = "FinishDeploymentButton"
			root.add_child(finish_button)
	if finish_button != null:
		finish_button.text = "配置終了"
		finish_button.custom_minimum_size = Vector2(0.0, 44.0)
		finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		finish_button.size_flags_vertical = Control.SIZE_SHRINK_END
		finish_button.size_flags_stretch_ratio = 0.0
		if not finish_button.pressed.is_connected(_on_finish_pressed):
			finish_button.pressed.connect(_on_finish_pressed)
		var root := root_panel.get_node_or_null("Margin/Root") as VBoxContainer
		if root != null:
			root.move_child(finish_button, mini(2, root.get_child_count() - 1))
	_ensure_expanded_detail_ui()
	_ensure_finish_confirm_dialog()
	_hide_footer_finish_button()

func _populate_catalog() -> void:
	if catalog_list == null:
		return
	for child in catalog_list.get_children():
		child.queue_free()
	option_group = ButtonGroup.new()
	for i in entries.size():
		var entry := entries[i]
		var action := str(entry.get("action", "")).strip_edges().to_lower()
		var unit_class := str(entry.get("unit_class", "")).strip_edges().to_lower()
		if unit_class == "" and action.begins_with("deploy:"):
			unit_class = action.trim_prefix("deploy:")
		if unit_class == "":
			continue
		var catalog_entry := _catalog_entry_for(unit_class)
		var unit_name := str(entry.get("unit_name", catalog_entry.get("name", unit_class.capitalize())))
		var cost := int(entry.get("cost", catalog_entry.get("cost", 0)))
		var card := Button.new()
		card.custom_minimum_size = Vector2(0.0, 64.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.toggle_mode = true
		card.button_group = option_group
		card.expand_icon = true
		card.text = "%s\nMP %d" % [unit_name, cost]
		card.disabled = bool(entry.get("disabled", false))
		var preview_unit := _build_preview_unit(unit_class, catalog_entry)
		if board != null:
			card.icon = board.query_unit_icon_texture(preview_unit)
		card.pressed.connect(_on_option_pressed.bind(i))
		catalog_list.add_child(card)
		class_by_index[i] = unit_class
		entry_by_index[i] = catalog_entry
	if entries.is_empty() and detail_label != null:
		detail_label.text = "配置候補がありません。"

func _catalog_entry_for(unit_class: String) -> Dictionary:
	return UnitCatalogDialogUtils.catalog_entry_for(board, unit_class)

func _build_preview_unit(unit_class: String, catalog_entry: Dictionary) -> Dictionary:
	return UnitCatalogDialogUtils.build_preview_unit(board, unit_class, catalog_entry)

func _on_option_pressed(index: int) -> void:
	if not class_by_index.has(index):
		return
	var unit_class := str(class_by_index.get(index, ""))
	if unit_class == "":
		return
	if select_handler.is_valid():
		select_handler.call(unit_class)
	var entry := entry_by_index.get(index, {}) as Dictionary
	if detail_label != null:
		detail_label.text = "%s を選択中" % str(entry.get("name", unit_class))
	_show_expanded_detail(entry)

func _format_entry_text(entry: Dictionary) -> String:
	return UnitCatalogDialogUtils.format_entry_text(entry)

func _on_finish_pressed() -> void:
	_ensure_finish_confirm_dialog()
	if finish_confirm_dialog != null:
		finish_confirm_dialog.popup_centered()
		return
	_finalize_finish_phase()

func _on_finish_confirmed() -> void:
	_finalize_finish_phase()

func _finalize_finish_phase() -> void:
	if finish_handler.is_valid():
		finish_handler.call()
	if root_panel != null:
		root_panel.visible = false
	_hide_panel_finish_button()
	_hide_footer_finish_button()
	_hide_expanded_detail()
	_exit_replacement_mode()

func _enter_replacement_mode() -> void:
	if left_panel_container == null:
		return
	if not replaced_nodes.is_empty():
		return
	for child in left_panel_container.get_children():
		var control := child as Control
		if control == null or control == root_panel or control == footer_finish_button:
			continue
		replaced_nodes.append({
			"node": control,
			"index": control.get_index(),
			"visible": control.visible
		})
		left_panel_container.remove_child(control)

func _exit_replacement_mode() -> void:
	if left_panel_container == null:
		replaced_nodes.clear()
		return
	for item in replaced_nodes:
		if not (item is Dictionary):
			continue
		var node_variant: Variant = (item as Dictionary).get("node", null)
		if not (node_variant is Control):
			continue
		var control := node_variant as Control
		if not is_instance_valid(control):
			continue
		if control.get_parent() != left_panel_container:
			left_panel_container.add_child(control)
		var target_index := int((item as Dictionary).get("index", left_panel_container.get_child_count() - 1))
		target_index = clampi(target_index, 0, left_panel_container.get_child_count() - 1)
		left_panel_container.move_child(control, target_index)
		control.visible = bool((item as Dictionary).get("visible", true))
	replaced_nodes.clear()

func _update_mp_label() -> void:
	if mp_label == null:
		return
	var mp := 0
	if current_mp >= 0:
		mp = current_mp
	elif board != null:
		mp = int(board.query_faction_mp(deployment_faction))
	mp_label.text = "現MP: %d" % mp

func _ensure_expanded_detail_ui() -> void:
	if canvas_layer == null:
		return
	if detail_expand_panel == null:
		var existing := canvas_layer.get_node_or_null("DeploymentDetailExpand")
		detail_expand_panel = existing as PanelContainer if existing is PanelContainer else null
	if detail_expand_panel == null:
		detail_expand_panel = PanelContainer.new()
		detail_expand_panel.name = "DeploymentDetailExpand"
		detail_expand_panel.visible = false
		detail_expand_panel.custom_minimum_size = Vector2(260.0, 260.0)
		canvas_layer.add_child(detail_expand_panel)
		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		detail_expand_panel.add_child(margin)
		var body := VBoxContainer.new()
		body.name = "Body"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		margin.add_child(body)
		var title := Label.new()
		title.text = "ユニット性能"
		body.add_child(title)
		detail_expand_label = Label.new()
		detail_expand_label.name = "DetailExpandLabel"
		detail_expand_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_expand_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		detail_expand_label.text = ""
		body.add_child(detail_expand_label)
	if detail_expand_label == null:
		detail_expand_label = detail_expand_panel.get_node_or_null("Margin/Body/DetailExpandLabel") as Label

func _layout_expanded_detail_panel() -> void:
	if detail_expand_panel == null:
		return
	var left_panel := _resolve_left_panel()
	if left_panel == null:
		return
	var viewport := left_panel.get_viewport_rect().size
	var pos_x := left_panel.global_position.x + left_panel.size.x + 8.0
	var pos_y := left_panel.global_position.y + 8.0
	var max_width := maxf(220.0, viewport.x - pos_x - 12.0)
	detail_expand_panel.position = Vector2(pos_x, pos_y)
	detail_expand_panel.custom_minimum_size.x = minf(320.0, max_width)

func _resolve_left_panel() -> Control:
	if left_panel_container == null:
		return null
	var margin := left_panel_container.get_parent() as Control
	if margin == null:
		return null
	return margin.get_parent() as Control

func _show_expanded_detail(entry: Dictionary) -> void:
	_ensure_expanded_detail_ui()
	_layout_expanded_detail_panel()
	if detail_expand_panel == null or detail_expand_label == null:
		return
	detail_expand_label.text = _format_entry_text(entry)
	detail_expand_panel.visible = true

func _hide_expanded_detail() -> void:
	if detail_expand_panel != null:
		detail_expand_panel.visible = false

func _ensure_finish_confirm_dialog() -> void:
	if canvas_layer == null:
		return
	if finish_confirm_dialog == null:
		var existing := canvas_layer.get_node_or_null("DeploymentFinishConfirm")
		finish_confirm_dialog = existing as ConfirmationDialog if existing is ConfirmationDialog else null
	if finish_confirm_dialog == null:
		finish_confirm_dialog = ConfirmationDialog.new()
		finish_confirm_dialog.name = "DeploymentFinishConfirm"
		finish_confirm_dialog.title = "配置終了"
		finish_confirm_dialog.dialog_text = "初期配置を終了して第1ターンを開始しますか？"
		canvas_layer.add_child(finish_confirm_dialog)
	if not finish_confirm_dialog.confirmed.is_connected(_on_finish_confirmed):
		finish_confirm_dialog.confirmed.connect(_on_finish_confirmed)

func _show_panel_finish_button() -> void:
	if finish_button == null:
		return
	finish_button.visible = true

func _hide_panel_finish_button() -> void:
	if finish_button == null:
		return
	finish_button.visible = false

func _ensure_footer_finish_button() -> void:
	if left_panel_container == null:
		return
	var left_panel := _resolve_left_panel()
	if footer_finish_button == null:
		var existing := left_panel_container.get_node_or_null("DeploymentFooterFinishButton")
		if existing == null and left_panel != null:
			existing = left_panel.get_node_or_null("DeploymentFooterFinishButton")
		footer_finish_button = existing as Button if existing is Button else null
	if footer_finish_button == null:
		footer_finish_button = Button.new()
		footer_finish_button.name = "DeploymentFooterFinishButton"
		footer_finish_button.text = "配置終了"
		footer_finish_button.custom_minimum_size = Vector2(0.0, 44.0)
		footer_finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer_finish_button.size_flags_vertical = Control.SIZE_SHRINK_END
		footer_finish_button.add_theme_font_size_override("font_size", 16)
		footer_finish_button.visible = false
		left_panel_container.add_child(footer_finish_button)
	else:
		if footer_finish_button.get_parent() != left_panel_container:
			var old_parent := footer_finish_button.get_parent()
			if old_parent != null:
				old_parent.remove_child(footer_finish_button)
			left_panel_container.add_child(footer_finish_button)
		footer_finish_button.custom_minimum_size = Vector2(0.0, 44.0)
		footer_finish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer_finish_button.size_flags_vertical = Control.SIZE_SHRINK_END
	if not footer_finish_button.pressed.is_connected(_on_finish_pressed):
		footer_finish_button.pressed.connect(_on_finish_pressed)

func _show_footer_finish_button() -> void:
	_ensure_footer_finish_button()
	if footer_finish_button == null:
		return
	footer_finish_button.visible = true
	if left_panel_container != null:
		left_panel_container.move_child(footer_finish_button, left_panel_container.get_child_count() - 1)

func _hide_footer_finish_button() -> void:
	if footer_finish_button == null:
		return
	footer_finish_button.visible = false
