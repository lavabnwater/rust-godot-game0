extends CanvasLayer
class_name MapUI

# ============================================================
# SURVIVAL GAME - MAP SCREEN (key: G)
# ============================================================

const MAP_SIZE: float = 400.0
const WORLD_SIZE: float = 370.0

var panel: Panel
var dot: ColorRect
var is_open: bool = false


func _ready() -> void:
	layer = 20
	visible = false

	panel = Panel.new()
	panel.size = Vector2(MAP_SIZE, MAP_SIZE)
	panel.position = Vector2(
		(1280.0 - MAP_SIZE) / 2.0,
		(720.0 - MAP_SIZE) / 2.0
	)
	add_child(panel)

	var label := Label.new()
	label.text = "MAP"
	label.position = Vector2(10.0, 10.0)
	panel.add_child(label)

	dot = ColorRect.new()
	dot.size = Vector2(8.0, 8.0)
	dot.color = Color(1.0, 0.2, 0.2)
	panel.add_child(dot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	is_open = not is_open
	visible = is_open


func _process(_delta: float) -> void:
	if not visible:
		return
	if Network.local_player == null:
		return
	if not is_instance_valid(Network.local_player):
		return

	var pos: Vector3 = Network.local_player.global_position
	var nx: float = clampf((pos.x + WORLD_SIZE / 2.0) / WORLD_SIZE, 0.0, 1.0)
	var nz: float = clampf((pos.z + WORLD_SIZE / 2.0) / WORLD_SIZE, 0.0, 1.0)

	dot.position = Vector2(
		nx * (MAP_SIZE - 8.0),
		nz * (MAP_SIZE - 8.0)
	)
