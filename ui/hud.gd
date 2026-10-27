extends CanvasLayer

func _ready() -> void:
	layer = 5
	var crosshair = preload("res://ui/crosshair.gd").new()
	add_child(crosshair)
	call_deferred("_make_windows")


# Makes sure the crafting window exists (once).
# Hotbar and Inventory are already created by world.gd when the player spawns.
func _make_windows() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if not is_instance_valid(CraftingUI.instance):
		parent.add_child(CraftingUI.new())
		print("HUD created the crafting window")
