class_name CraftingUI
extends CanvasLayer

static var instance: CraftingUI = null
static var is_open: bool = false

var window_panel: Panel = null
var recipes_container: VBoxContainer = null

const RECIPES := {
	"axe": {"name": "Axe", "cost": {"wood": 200, "stone": 100}},
	"pickaxe": {"name": "Pickaxe", "cost": {"wood": 200, "stone": 100}},
	"hammer": {"name": "Hammer", "cost": {"wood": 100}},
	"wood_spear": {"name": "Wood Spear", "cost": {"wood": 200}},
	"stone_arrow": {"name": "Stone Arrow (x2)", "cost": {"wood": 1, "stone": 1}},
	"campfire": {"name": "Campfire", "cost": {"wood": 100}},
	"building_plan": {"name": "Building Plan", "cost": {"wood": 50}},
}

func _ready() -> void:
	instance = self
	layer = 15
	visible = false
	is_open = false
	_build_ui()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	window_panel = Panel.new()
	window_panel.custom_minimum_size = Vector2(380, 400)
	window_panel.set_anchors_preset(Control.PRESET_CENTER)
	window_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	window_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var win_sb := StyleBoxFlat.new()
	win_sb.bg_color = Color(0.08, 0.08, 0.1, 0.94)
	win_sb.border_color = Color(0.25, 0.25, 0.3, 0.9)
	win_sb.set_border_width_all(2)
	win_sb.set_corner_radius_all(6)
	window_panel.add_theme_stylebox_override("panel", win_sb)
	root.add_child(window_panel)

	var title := Label.new()
	title.text = "CRAFTING"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	window_panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 15
	scroll.offset_right = -15
	scroll.offset_top = 45
	scroll.offset_bottom = -15
	window_panel.add_child(scroll)

	recipes_container = VBoxContainer.new()
	recipes_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipes_container.add_theme_constant_override("separation", 8)
	scroll.add_child(recipes_container)

	_populate_recipes()

func _populate_recipes() -> void:
	for child in recipes_container.get_children():
		child.queue_free()

	for item_id in RECIPES:
		var rec: Dictionary = RECIPES[item_id]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(330, 40)
		recipes_container.add_child(row)

		var lbl := Label.new()
		var cost_str := ""
		for c_id in rec["cost"]:
			cost_str += "%d %s  " % [rec["cost"][c_id], c_id]
		lbl.text = "%s\nCost: %s" % [rec["name"], cost_str]
		lbl.custom_minimum_size = Vector2(230, 40)
		lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(lbl)

		var btn := Button.new()
		btn.text = "Craft"
		btn.custom_minimum_size = Vector2(80, 32)
		btn.pressed.connect(_on_craft_pressed.bind(item_id))
		row.add_child(btn)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("crafting") and not event.is_echo():
		if InventoryUI.instance != null and InventoryUI.is_open:
			InventoryUI.instance.close()
		toggle()
		get_viewport().set_input_as_handled()

func _on_craft_pressed(item_id: String) -> void:
	var gathering = get_tree().root.get_node_or_null("Main/Gathering")
	if gathering == null:
		return
	if Network.mode == Network.MODE_SERVER:
		gathering.craft_item_for(multiplayer.get_unique_id(), item_id)
	else:
		gathering._server_craft_item.rpc_id(1, item_id)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	visible = true
	if Network.local_player != null and Network.local_player.has_method("set_inventory_mode"):
		Network.local_player.set_inventory_mode(true)

func close() -> void:
	is_open = false
	visible = false
	if Network.local_player != null and Network.local_player.has_method("set_inventory_mode"):
		Network.local_player.set_inventory_mode(false)
