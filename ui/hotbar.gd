class_name HotbarUI
extends CanvasLayer

# Static singleton reference
static var instance: HotbarUI = null
static var active_slot: int = 0

# Slot UI elements
var slot_panels: Array = []
var name_labels: Array = []
var count_labels: Array = []
var slots_data: Array = []

func _ready() -> void:
	instance = self
	layer = 10
	
	# Initial slot data (slot 0 starts with rock)
	slots_data.clear()
	for i in range(6):
		slots_data.append({"id": "", "count": 0})
	slots_data[0] = {"id": "rock", "count": 1}
	
	_build_ui()
	_update_display()
	_update_viewmodel()

# Builds the 6-slot hotbar UI at the bottom center
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var hbox := HBoxContainer.new()
	hbox.layout_mode = 1
	hbox.layout_direction = Control.LAYOUT_DIRECTION_LTR # Starts 1 from the left
	hbox.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hbox.offset_top = -80
	hbox.offset_bottom = -15
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hbox)

	for i in range(6):
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_slot_gui_input.bind(i))
		hbox.add_child(panel)
		slot_panels.append(panel)

		# Slot number label (1-6)
		var num_lbl := Label.new()
		num_lbl.text = str(i + 1)
		num_lbl.position = Vector2(5, 2)
		num_lbl.add_theme_font_size_override("font_size", 12)
		num_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num_lbl)

		# Item name label
		var name_lbl := Label.new()
		name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_lbl)
		name_labels.append(name_lbl)

		# Item count label
		var cnt_lbl := Label.new()
		cnt_lbl.position = Vector2(5, 40)
		cnt_lbl.size = Vector2(50, 18)
		cnt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt_lbl.add_theme_font_size_override("font_size", 12)
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cnt_lbl)
		count_labels.append(cnt_lbl)

func _process(_delta: float) -> void:
	# Ensure viewmodel updates once local player is spawned
	if Network.local_player != null and Network.local_player.viewmodel != null:
		if Network.local_player.viewmodel.tool_nodes.size() > 0:
			var current_held := -1
			for i in Network.local_player.viewmodel.tool_nodes.size():
				if Network.local_player.viewmodel.tool_nodes[i].visible:
					current_held = i
			var target_tool := _get_target_tool_id()
			if current_held != target_tool:
				_update_viewmodel()

func _unhandled_input(event: InputEvent) -> void:
	# Ignore hotbar keys when inventory is open
	if InventoryUI.is_open:
		return

	# Number keys 1 to 6
	if event is InputEventKey and event.is_pressed() and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_6:
			select_slot(key_event.keycode - KEY_1)
			return

	# Mouse wheel scroll
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot((active_slot - 1 + 6) % 6)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot((active_slot + 1) % 6)

# Slot click input
func _on_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if InventoryUI.is_open and InventoryUI.instance != null:
				InventoryUI.instance._handle_slot_click(slot_idx)
				_update_display()
			else:
				select_slot(slot_idx)

# Selects active hotbar slot
func select_slot(index: int) -> void:
	if index < 0 or index >= 6:
		return
	active_slot = index
	_update_display()
	_update_viewmodel()

# Updates slot borders, names, and counts
func _update_display() -> void:
	var total: int = mini(slot_panels.size(), 6)
	for i in range(total):
		var panel: Panel = slot_panels[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.14, 0.75)
		sb.set_corner_radius_all(4)

		# Highlight if selected by inventory move OR currently active slot
		if InventoryUI.is_open and InventoryUI.selected_slot == i:
			sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
			sb.set_border_width_all(2)
		elif i == active_slot:
			sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(0.3, 0.3, 0.35, 0.8)
			sb.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", sb)

		var slot: Dictionary = slots_data[i] if i < slots_data.size() else {}
		var item_id: String = str(slot.get("id", ""))
		var count: int = int(slot.get("count", 0))

		if i < name_labels.size():
			if item_id != "" and count > 0:
				name_labels[i].text = ItemDB.get_item_name(item_id)
			else:
				name_labels[i].text = ""

		if i < count_labels.size():
			if item_id != "" and count > 1:
				count_labels[i].text = str(count)
			else:
				count_labels[i].text = ""

# Returns corresponding viewmodel tool index
func _get_target_tool_id() -> int:
	if active_slot >= slots_data.size():
		return -1
	var item_id: String = str(slots_data[active_slot].get("id", ""))
	if item_id == "rock":
		return 0
	elif item_id == "axe":
		return 1
	elif item_id == "pickaxe":
		return 2
	return -1

# Syncs viewmodel hand mesh with selected tool
func _update_viewmodel() -> void:
	if Network.local_player == null or Network.local_player.viewmodel == null:
		return
	Network.local_player.viewmodel.set_tool(_get_target_tool_id())

# Called when server syncs hotbar slots
func set_slots(new_slots: Array) -> void:
	slots_data = new_slots.duplicate(true)
	_update_display()
	_update_viewmodel()
