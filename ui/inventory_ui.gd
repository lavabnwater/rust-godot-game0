class_name InventoryUI
extends CanvasLayer

static var instance: InventoryUI = null
static var is_open: bool = false
static var selected_slot: int = -1

var window_panel: Panel = null
var slot_panels: Array = []
var name_labels: Array = []
var count_labels: Array = []
var slots_data: Array = []

func _ready() -> void:
	instance = self
	layer = 15
	visible = false
	is_open = false
	selected_slot = -1

	slots_data.clear()
	for i in range(Inventory.TOTAL_SLOTS):
		slots_data.append({"id": "", "count": 0})

	_build_ui()

func _build_ui() -> void:
	var root := Control.new()
	root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	window_panel = Panel.new()
	window_panel.layout_direction = Control.LAYOUT_DIRECTION_LTR
	window_panel.anchor_left = 0.5
	window_panel.anchor_right = 0.5
	window_panel.anchor_top = 0.5
	window_panel.anchor_bottom = 0.5
	window_panel.offset_left = -230.0
	window_panel.offset_right = 230.0
	window_panel.offset_top = -190.0
	window_panel.offset_bottom = 170.0
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	sb.border_color = Color(0.25, 0.27, 0.3, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	window_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(window_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	window_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	for i in range(6):
		slot_panels.append(null)
		name_labels.append(null)
		count_labels.append(null)

	for slot_idx in range(6, Inventory.TOTAL_SLOTS):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_slot_gui_input.bind(slot_idx))
		grid.add_child(panel)
		slot_panels.append(panel)

		var name_lbl := Label.new()
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_lbl)
		name_labels.append(name_lbl)

		var cnt_lbl := Label.new()
		cnt_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cnt_lbl.offset_right = -4.0
		cnt_lbl.offset_bottom = -2.0
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cnt_lbl.add_theme_font_size_override("font_size", 11)
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cnt_lbl)
		count_labels.append(cnt_lbl)

	var hint := Label.new()
	hint.text = "Click an item, then click another slot to move it. Hotbar is at the bottom."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	box.add_child(hint)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()

func _on_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_slot_click(slot_idx)

func _handle_slot_click(slot_idx: int) -> void:
	var slot: Dictionary = slots_data[slot_idx] if slot_idx < slots_data.size() else {}
	var has_item: bool = str(slot.get("id", "")) != "" and int(slot.get("count", 0)) > 0

	if selected_slot < 0:
		if has_item:
			selected_slot = slot_idx
			_update_display()
	else:
		if selected_slot == slot_idx:
			selected_slot = -1
			_update_display()
		else:
			var from_idx := selected_slot
			var to_idx := slot_idx
			selected_slot = -1
			_request_move(from_idx, to_idx)
			_update_display()

func _request_move(from_idx: int, to_idx: int) -> void:
	var gathering = get_tree().root.get_node_or_null("Main/Gathering")
	if gathering == null:
		return
	if Network.mode == Network.MODE_SERVER:
		gathering.move_item_for(multiplayer.get_unique_id(), from_idx, to_idx)
	else:
		gathering._server_move_item.rpc_id(1, from_idx, to_idx)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if CraftingUI.instance != null and is_instance_valid(CraftingUI.instance) and CraftingUI.is_open:
		CraftingUI.instance.close()
	is_open = true
	visible = true
	selected_slot = -1
	if Network.local_player != null and Network.local_player.has_method("set_inventory_mode"):
		Network.local_player.set_inventory_mode(true)
	_update_display()

func close() -> void:
	is_open = false
	visible = false
	selected_slot = -1
	if Network.local_player != null and Network.local_player.has_method("set_inventory_mode"):
		Network.local_player.set_inventory_mode(false)
	if HotbarUI.instance != null and is_instance_valid(HotbarUI.instance):
		HotbarUI.instance._update_display()

func _update_display() -> void:
	for slot_idx in range(Inventory.TOTAL_SLOTS):
		if slot_idx >= slot_panels.size() or slot_panels[slot_idx] == null:
			continue
		var panel: Panel = slot_panels[slot_idx]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.14, 0.17, 0.85)
		sb.set_corner_radius_all(4)

		if slot_idx == selected_slot:
			sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(0.3, 0.3, 0.35, 0.7)
			sb.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", sb)

		var slot: Dictionary = slots_data[slot_idx] if slot_idx < slots_data.size() else {}
		var item_id: String = str(slot.get("id", ""))
		var count: int = int(slot.get("count", 0))

		if slot_idx < name_labels.size() and name_labels[slot_idx] != null:
			name_labels[slot_idx].text = ItemDB.get_item_name(item_id) if (item_id != "" and count > 0) else ""

		if slot_idx < count_labels.size() and count_labels[slot_idx] != null:
			count_labels[slot_idx].text = str(count) if (item_id != "" and count > 1) else ""

	if HotbarUI.instance != null and is_instance_valid(HotbarUI.instance):
		HotbarUI.instance._update_display()

func set_slots(new_slots: Array) -> void:
	slots_data = new_slots.duplicate(true)
	_update_display()
