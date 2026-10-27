extends Node3D
# عالم الاختبار + نقطة الدخول: سيرفر (--server) أو عميل (قوائم ثم لعب)

const GROUND_SIZE := 400.0
const BOUND := 185.0

const LowPoly = preload("res://world/lowpoly.gd")
const PlayerScript = preload("res://player/player.gd")
const HudScript = preload("res://ui/hud.gd")
const GatheringScript = preload("res://world/gathering.gd")
const MenusScript = preload("res://ui/menus.gd")
const DayNightScript = preload("res://world/day_night.gd")
const BeachSpawns = preload("res://world/beach_spawns.gd")

var player
var menus
var world_built := false
var status_label: Label
var _sun: DirectionalLight3D = null
var _pending_spawn: Vector3 = Vector3.ZERO
var _death_screen: CanvasLayer = null


func _ready() -> void:
	Network.connected_to_host.connect(_on_connected_to_host)
	Network.welcomed.connect(_on_welcomed)
	Network.failed.connect(_on_net_failed)
	if GameState.is_server:
		_start_server_mode()
	else:
		menus = CanvasLayer.new()
		menus.set_script(MenusScript)
		add_child(menus)
		menus.join_requested.connect(_on_join_requested)
		menus.host_requested.connect(_on_host_requested)


func _process(_delta: float) -> void:
	if status_label != null:
		status_label.text = "SERVER RUNNING\nPort: %d\nPlayers: %d / %d" % [GameState.port, Network.players.size(), GameState.max_players]


func _build_world() -> void:
	if world_built:
		return
	world_built = true
	_make_environment()
	_make_ground()
	_make_test_course()

	var gathering = GatheringScript.new()
	gathering.name = "Gathering"
	add_child(gathering)

	var day_night = DayNightScript.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(_sun)

	Network.world_root = self


func _start_server_mode() -> void:
	Engine.max_fps = 60
	_build_world()
	if not Network.start_server(GameState.port, GameState.max_players):
		get_tree().quit(1)
		return
	print("SERVER RUNNING on port %d (max %d players)" % [GameState.port, GameState.max_players])
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		status_label = Label.new()
		status_label.position = Vector2(24.0, 24.0)
		status_label.add_theme_font_size_override("font_size", 28)
		layer.add_child(status_label)
		add_child(layer)


func _on_join_requested(address: String, port: int) -> void:
	await get_tree().process_frame
	if not Network.join_server(address, port):
		_on_net_failed("Could not start the connection. Check the address.")


# Starts a real server in this process AND spawns a controllable player for it (host + play).
func _on_host_requested() -> void:
	await get_tree().process_frame
	_build_world()
	var spawn: Vector3 = BeachSpawns.get_random_point()
	if not Network.host_and_play(GameState.port, GameState.max_players, spawn):
		GameState.message_for_menu = "Could not start the server. Try a different port."
		GameState.skip_splash = true
		get_tree().reload_current_scene()
		return
	_pending_spawn = spawn
	if menus != null:
		menus.queue_free()
		menus = null
	_show_death_screen()


func _on_connected_to_host() -> void:
	if menus == null:
		return
	menus.show_loading("Loading world...")
	await get_tree().process_frame
	await get_tree().process_frame
	_build_world()
	menus.show_loading("Joining...")
	Network.send_hello()


func _on_welcomed(spawn_pos: Vector3) -> void:
	_pending_spawn = spawn_pos

	if menus != null:
		menus.queue_free()
		menus = null

	_show_death_screen()


func _show_death_screen() -> void:
	_death_screen = CanvasLayer.new()
	_death_screen.layer = 30
	add_child(_death_screen)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.add_child(bg)

	var label := Label.new()
	label.text = "You died from the sea."
	label.add_theme_font_size_override("font_size", 36)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-160.0, -60.0)
	_death_screen.add_child(label)

	var button := Button.new()
	button.text = "Respawn"
	button.size = Vector2(160.0, 48.0)
	button.set_anchors_preset(Control.PRESET_CENTER)
	button.position = Vector2(-80.0, 20.0)
	button.pressed.connect(_on_respawn_pressed)
	_death_screen.add_child(button)


func _on_respawn_pressed() -> void:
	if _death_screen != null:
		_death_screen.queue_free()
		_death_screen = null
	_spawn_player(_pending_spawn)


func _spawn_player(spawn_pos: Vector3) -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.position = spawn_pos
	add_child(player)
	Network.local_player = player

	var hud := CanvasLayer.new()
	hud.set_script(HudScript)
	add_child(hud)

	var hotbar = preload("res://ui/hotbar.gd").new()
	add_child(hotbar)
	var inv_ui = preload("res://ui/inventory_ui.gd").new()
	add_child(inv_ui)
	var map_ui = preload("res://ui/map_ui.gd").new()
	add_child(map_ui)


func _on_net_failed(text: String) -> void:
	Network.leave()
	GameState.message_for_menu = text
	GameState.skip_splash = true
	get_tree().reload_current_scene()


func _make_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.62, 0.72, 0.82)
	sky_mat.ground_horizon_color = Color(0.62, 0.72, 0.82)
	sky_mat.ground_bottom_color = Color(0.5, 0.6, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.8)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.72, 0.82)
	env.fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	_sun = sun


func _make_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)

	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	mesh_inst.mesh = plane
	mesh_inst.material_override = LowPoly.material(Color(0.4, 0.5, 0.3))
	body.add_child(mesh_inst)
	add_child(body)

	var walls := [
		[Vector3(0.0, 10.0, BOUND), Vector3(GROUND_SIZE, 20.0, 2.0)],
		[Vector3(0.0, 10.0, -BOUND), Vector3(GROUND_SIZE, 20.0, 2.0)],
		[Vector3(BOUND, 10.0, 0.0), Vector3(2.0, 20.0, GROUND_SIZE)],
		[Vector3(-BOUND, 10.0, 0.0), Vector3(2.0, 20.0, GROUND_SIZE)],
	]
	for w in walls:
		var wall := StaticBody3D.new()
		var wshape := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = w[1]
		wshape.shape = wbox
		wall.position = w[0]
		wall.add_child(wshape)
		add_child(wall)


func _box(pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	inst.mesh = mesh
	inst.material_override = LowPoly.material(color)
	body.add_child(inst)
	add_child(body)


func _make_test_course() -> void:
	_box(Vector3(-4.0, 0.25, -8.0), Vector3(2.0, 0.5, 2.0), Color(0.75, 0.55, 0.3))
	_box(Vector3(-4.0, 0.45, -12.0), Vector3(2.0, 0.9, 2.0), Color(0.75, 0.4, 0.3))
	_box(Vector3(6.0, 0.9, -10.0), Vector3(3.0, 0.2, 6.0), Color(0.55, 0.55, 0.6), Vector3(20.0, 0.0, 0.0))
	_box(Vector3(-1.1, 1.2, -18.0), Vector3(0.4, 2.4, 0.4), Color(0.45, 0.3, 0.2))
	_box(Vector3(1.1, 1.2, -18.0), Vector3(0.4, 2.4, 0.4), Color(0.45, 0.3, 0.2))
	_box(Vector3(0.0, 1.45, -18.0), Vector3(2.8, 0.3, 0.4), Color(0.6, 0.4, 0.25))
	_box(Vector3(0.0, 1.5, -30.0), Vector3(10.0, 3.0, 0.5), Color(0.6, 0.6, 0.62))


func _scatter_rocks() -> void:
	pass
