extends Node3D
# Batch 3/5 - trees, rocks, cloth plants you can gather, plus resource respawn.
# The SERVER owns every tree, rock and plant. The same script runs on the server and on every client.
# It must be a child of the Main scene named "Gathering" (world.gd creates it).

const LowPoly = preload("res://world/lowpoly.gd")

# ---------- Numbers you can change ----------
const TREE_COUNT := 70
const ROCK_COUNT := 35
const PLANT_COUNT := 40
const TREE_WOOD := 300 # wood inside one tree
const ROCK_STONE := 200 # stone inside one rock
const CLOTH_PER_PLANT := 10 # instant pickup amount
const REACH := 2.8 # how far a swing reaches (meters)
const PLANT_REACH := 2.5 # how far E can reach a plant (meters)
const MIN_STRIKE_GAP := 0.3 # the server ignores swings faster than this (seconds)
const X_BONUS_MIN := 2.0
const X_BONUS_MAX := 2.1 # (a new random value on every X hit; use the same number in both for a fixed bonus)
const X_BOX_TREE := 0.15 # invisible square hit box around the painted X on a tree: half of its side (meters). The X itself is smaller, so you also hit it a bit outside the red lines
const X_BOX_ROCK := 0.18 # same, on a rock (the X is bigger there)
const FELL_BONUS_WOOD := 50 # extra wood when a tree falls
const TOOL_NAMES := ["Rock", "Axe", "Pickaxe"]
const WOOD_PER_HIT := [[5, 6], [10, 11], 0]
const STONE_PER_HIT := [[5, 7], 0, [10, 12]]

# Simplest balance picked for v1 (documented, adjust later if needed):
const RESPAWN_TIME := 300.0 # trees/rocks come back 5 minutes after depletion
const PLANT_RESPAWN_TIME := 120.0 # plants come back 2 minutes after being picked

const KIND_TREE := 0
const KIND_ROCK := 1
const KIND_PLANT := 2

# Data of every tree/rock/plant. Same on the server and the clients (same seed). Index = id.
var kinds: Array = []
var positions: Array = []
var scales: Array = []
var pools: Array = [] # wood or stone left inside (unused for plants)
var alive: Array = []
var x_on: Array = [] # is the X showing on this one
var x_pos: Array = [] # where the X is (world position, exactly on the surface)
var x_nrm: Array = [] # which way the X faces (points away from the tree/rock)
var tree_tm: TriangleMesh # exact shape of the trunk, used to put the X on the real surface
var foliage_tm: TriangleMesh # exact shape of the leaves (they hide the X too)
var rock_tms: Array = []
var tree_faces := PackedVector3Array() # the triangles of the shapes above (to know which side of each triangle is drawn)
var foliage_faces := PackedVector3Array()
var rock_faces: Array = []

# Visual building blocks, kept as instance vars so respawn can rebuild single items.
var _trunk_mesh: Mesh
var _foliage_mesh: Mesh
var _trunk_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _rock_meshes: Array = []
var _rock_mat: StandardMaterial3D
var _plant_mesh: Mesh
var _plant_mat: StandardMaterial3D

# Server only
var totals := {} # player id -> {"wood": n, "stone": n} (temporary until the inventory batch)
var ready_peers := {} # players whose game finished loading this node
var last_strike := {}
var respawn_at := {} # id -> time (seconds) when it should come back

# Client only
var bodies := {} # id -> the tree/rock/plant node in the world
var x_labels := {} # id -> the painted X (a flat red mark on the surface)
var x_material: StandardMaterial3D
var x_mesh_tree: QuadMesh
var x_mesh_rock: QuadMesh
var tool_id := 0 # 0 = rock, 1 = axe, 2 = pickaxe
var wood_total := 0
var stone_total := 0
var hud_label: Label
var msg_label: Label
var msg_time := 0.0


func _ready() -> void:
	_generate()
	_build_surface_shapes()
	if GameState.is_server:
		# Dedicated headless server only: no visuals needed.
		multiplayer.peer_disconnected.connect(_on_peer_left)
		return
	_build_visuals()
	multiplayer.peer_disconnected.connect(_on_peer_left)
	call_deferred("_request_sync")


func _process(delta: float) -> void:
	if msg_time > 0.0:
		msg_time -= delta
		if msg_time <= 0.0 and msg_label != null:
			msg_label.text = ""

	if Network.mode == Network.MODE_SERVER and not respawn_at.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		var done := []
		for id in respawn_at.keys():
			if now >= float(respawn_at[id]):
				done.append(id)
		for id in done:
			respawn_at.erase(id)
			_do_respawn(id)


# ---------------------------------------------------------------- shared: where trees, rocks and plants are
func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261024
	var total := TREE_COUNT + ROCK_COUNT + PLANT_COUNT
	var tries := 0
	while kinds.size() < total and tries < 8000:
		tries += 1
		var kind: int
		if kinds.size() < TREE_COUNT:
			kind = KIND_TREE
		elif kinds.size() < TREE_COUNT + ROCK_COUNT:
			kind = KIND_ROCK
		else:
			kind = KIND_PLANT
		var p := Vector3(rng.randf_range(-90.0, 90.0), 0.0, rng.randf_range(-90.0, 90.0))
		if absf(p.x) < 14.0 and p.z > -38.0 and p.z < 10.0:
			continue # keep the test course and the spawn area clear
		var too_close := false
		for q in positions:
			if p.distance_to(q) < 4.0:
				too_close = true
				break
		if too_close:
			continue
		var s := rng.randf_range(0.9, 1.4)
		if kind == KIND_ROCK:
			s = rng.randf_range(1.0, 1.6)
		elif kind == KIND_PLANT:
			s = rng.randf_range(0.8, 1.2)
		kinds.append(kind)
		positions.append(p)
		scales.append(s)
		if kind == KIND_TREE:
			pools.append(TREE_WOOD)
		elif kind == KIND_ROCK:
			pools.append(ROCK_STONE)
		else:
			pools.append(1)
		alive.append(true)
		x_on.append(false)
		x_pos.append(Vector3.ZERO)
		x_nrm.append(Vector3.RIGHT)


# Exact shapes of the trunk and the rocks (same on server and clients). The X is placed on these.
func _build_surface_shapes() -> void:
	tree_tm = LowPoly.tree_trunk().generate_triangle_mesh()
	foliage_tm = LowPoly.tree_foliage().generate_triangle_mesh()
	tree_faces = tree_tm.get_faces()
	foliage_faces = foliage_tm.get_faces()
	for seed_id in [11, 12, 13]:
		var rock_tm := LowPoly.rock(seed_id).generate_triangle_mesh()
		rock_tms.append(rock_tm)
		rock_faces.append(rock_tm.get_faces())


# ---------------------------------------------------------------- client: what you see
func _build_visuals() -> void:
	_trunk_mesh = LowPoly.tree_trunk()
	_foliage_mesh = LowPoly.tree_foliage()
	_trunk_mat = LowPoly.material(Color(0.42, 0.29, 0.18))
	_leaf_mat = LowPoly.material(Color(0.2, 0.46, 0.24))
	_rock_meshes = [LowPoly.rock(11), LowPoly.rock(12), LowPoly.rock(13)]
	_rock_mat = LowPoly.material(Color(0.5, 0.5, 0.52))
	_plant_mesh = SphereMesh.new()
	_plant_mesh.radius = 0.28
	_plant_mesh.height = 0.5
	_plant_mat = LowPoly.material(Color(0.3, 0.55, 0.22))
	x_material = StandardMaterial3D.new()
	x_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	x_material.albedo_texture = _make_x_texture()
	x_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	x_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	x_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	x_mesh_tree = QuadMesh.new()
	x_mesh_tree.size = Vector2(0.26, 0.26)
	x_mesh_rock = QuadMesh.new()
	x_mesh_rock.size = Vector2(0.4, 0.4)
	for i in kinds.size():
		_build_one(i)


# Builds (or rebuilds after a respawn) the visual node for a single tree/rock/plant.
func _build_one(i: int) -> void:
	if bodies.has(i):
		return
	var s: float = scales[i]

	if kinds[i] == KIND_PLANT:
		var plant := MeshInstance3D.new()
		plant.mesh = _plant_mesh
		plant.material_override = _plant_mat
		plant.position = Vector3(positions[i]) + Vector3(0.0, 0.2, 0.0)
		plant.scale = Vector3.ONE * s
		add_child(plant)
		bodies[i] = plant
		return

	var body := StaticBody3D.new()
	body.position = positions[i]
	var visual := Node3D.new() # scaled copy of the mesh (the body itself is not scaled)
	visual.scale = Vector3.ONE * s
	body.add_child(visual)
	var shape := CollisionShape3D.new()
	if kinds[i] == KIND_TREE:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3 * s
		cyl.height = 2.0 * s
		shape.shape = cyl
		shape.position = Vector3(0.0, s, 0.0)
		var trunk := MeshInstance3D.new()
		trunk.mesh = _trunk_mesh
		trunk.material_override = _trunk_mat
		visual.add_child(trunk)
		var leaves := MeshInstance3D.new()
		leaves.mesh = _foliage_mesh
		leaves.material_override = _leaf_mat
		visual.add_child(leaves)
	else:
		var sph := SphereShape3D.new()
		sph.radius = 0.8 * s
		shape.shape = sph
		shape.position = Vector3(0.0, 0.45 * s, 0.0)
		var rock := MeshInstance3D.new()
		rock.mesh = _rock_meshes[i % 3]
		rock.material_override = _rock_mat
		rock.rotation.y = float(i)
		visual.add_child(rock)
	body.add_child(shape)
	add_child(body)
	bodies[i] = body


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_label = Label.new()
	hud_label.position = Vector2(20.0, 20.0)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud_label)
	msg_label = Label.new()
	msg_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	msg_label.offset_top = -170.0
	msg_label.offset_bottom = -130.0
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 26)
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(msg_label)
	_refresh_hud()


func _refresh_hud() -> void:
	if hud_label != null:
		hud_label.text = ""


func _show_message(text: String) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_time = 1.5


# The X is spray paint on the surface of the tree/rock: a flat red mark that anything solid hides.
func _show_x(id: int, pos: Vector3) -> void:
	x_on[id] = true
	x_pos[id] = pos
	var mark: MeshInstance3D = x_labels.get(id)
	if mark == null:
		mark = MeshInstance3D.new()
		mark.mesh = x_mesh_tree if kinds[id] == KIND_TREE else x_mesh_rock
		mark.material_override = x_material
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		x_labels[id] = mark
	var surf := _surface_at(id, pos)
	var n: Vector3 = surf[1]
	var axes := _x_axes(n)
	var b := Basis(axes[0], axes[1], n)
	mark.transform = Transform3D(b, Vector3(surf[0]) + n * (0.012 if kinds[id] == KIND_TREE else 0.02))


# Where the mesh of tree/rock i sits in the world (position, size, and the rock's turn).
func _node_xf(i: int) -> Transform3D:
	var spin := 0.0 if kinds[i] == KIND_TREE else float(i)
	return Transform3D(Basis(Vector3.UP, spin) * Basis.from_scale(Vector3.ONE * float(scales[i])), positions[i])


# Finds the real surface of the tree/rock next to the X position the server sent.
# Returns [position, normal] (normal points away from the tree/rock).
func _surface_at(id: int, pos: Vector3) -> Array:
	var c: Vector3 = positions[id]
	var s: float = scales[id]
	var is_tree: bool = kinds[id] == KIND_TREE
	var center := c + Vector3(0.0, 0.5 * s, 0.0)
	if is_tree:
		center = Vector3(c.x, pos.y, c.z)
	var out := pos - center
	if out.length() < 0.001:
		out = Vector3.RIGHT
	out = out.normalized()
	var xf := _node_xf(id)
	var inv := xf.affine_inverse()
	var tm: TriangleMesh = tree_tm if is_tree else rock_tms[id % 3]
	var hit := tm.intersect_ray(inv * (pos + out * 0.8), (inv.basis * -out).normalized())
	if hit.is_empty():
		return [pos, out]
	var world_pos: Vector3 = xf * Vector3(hit["position"])
	var world_normal: Vector3 = (xf.basis * Vector3(hit["normal"])).normalized()
	if world_normal.dot(out) < 0.0:
		world_normal = -world_normal
	return [world_pos, world_normal]


# Draws the spray-painted X (two rough red strokes with a few speckles) once.
func _make_x_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var a1 := Vector2(0.17, 0.17)
	var a2 := Vector2(0.83, 0.83)
	var b1 := Vector2(0.83, 0.17)
	var b2 := Vector2(0.17, 0.83)
	for py in n:
		for px in n:
			var p := Vector2(float(px) + 0.5, float(py) + 0.5) / float(n)
			var d := minf(_seg_dist(p, a1, a2), _seg_dist(p, b1, b2)) + (rng.randf() - 0.5) * 0.02
			var alpha := (1.0 - smoothstep(0.04, 0.095, d)) * (0.85 + rng.randf() * 0.15)
			if d > 0.095 and d < 0.17 and rng.randf() < 0.06 * (1.0 - (d - 0.095) / 0.075):
				alpha = rng.randf_range(0.3, 0.7) # speckles around the strokes
			img.set_pixel(px, py, Color(0.88, 0.08, 0.06, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.dot(ab), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _hide_x(id: int) -> void:
	x_on[id] = false
	if x_labels.has(id):
		x_labels[id].queue_free()
		x_labels.erase(id)


func _remove_now(id: int) -> void:
	alive[id] = false
	_hide_x(id)
	if bodies.has(id):
		bodies[id].queue_free()
		bodies.erase(id)


# Called by world.gd right after the local player is created (both for the host and for real clients).
func setup_local_player() -> void:
	var lp = Network.local_player
	if lp == null or not is_instance_valid(lp):
		return
	if not lp.viewmodel.strike.is_connected(_on_local_strike):
		lp.viewmodel.strike.connect(_on_local_strike)
	lp.viewmodel.set_tool(tool_id)
	if hud_label == null:
		_make_hud()


func _request_sync() -> void:
	if Network.mode == Network.MODE_CLIENT:
		_server_request_sync.rpc_id(1)


func _on_local_strike() -> void:
	var id: int = multiplayer.get_unique_id()
	if Network.mode == Network.MODE_SERVER:
		do_strike(id, _tool_of_slot(id, HotbarUI.active_slot))
	else:
		_server_strike.rpc_id(1, HotbarUI.active_slot)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	if Network.mode == Network.MODE_CLIENT:
		_server_interact.rpc_id(1)
		get_viewport().set_input_as_handled()
	elif Network.mode == Network.MODE_SERVER and Network.local_player != null:
		_do_interact(multiplayer.get_unique_id())
		get_viewport().set_input_as_handled()


func _on_peer_left(id: int) -> void:
	ready_peers.erase(id)
	totals.erase(id)
	last_strike.erase(id)
	Inventory.remove_player(id)


func _is_peer(id: int) -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.get_peers().has(id)


# Sends a visual effect to every real remote client that is ready, and also applies it
# directly when this process is the host (it never receives its own RPC calls).
func _broadcast_node_hit(id: int, pos: Vector3) -> void:
	for pid in ready_peers:
		if _is_peer(pid):
			_client_node_hit.rpc_id(pid, id, pos)
	if Network.mode == Network.MODE_SERVER and not GameState.is_server:
		_client_node_hit(id, pos)


func _broadcast_break(id: int, fall_dir: Vector3) -> void:
	for pid in ready_peers:
		if _is_peer(pid):
			_client_break.rpc_id(pid, id, fall_dir)
	if Network.mode == Network.MODE_SERVER and not GameState.is_server:
		_client_break(id, fall_dir)


func _broadcast_plant_picked(id: int) -> void:
	for pid in ready_peers:
		if _is_peer(pid):
			_client_plant_picked.rpc_id(pid, id)
	if Network.mode == Network.MODE_SERVER and not GameState.is_server:
		_client_plant_picked(id)


func _broadcast_respawn(id: int) -> void:
	for pid in ready_peers:
		if _is_peer(pid):
			_client_respawn.rpc_id(pid, id)
	if Network.mode == Network.MODE_SERVER and not GameState.is_server:
		_client_respawn(id)


# Sends the updated totals/HUD message to the player who performed the action
# (directly if it's the host itself, by RPC if it's a real remote player).
func _send_gain_update(id: int, msg: String) -> void:
	var total_wood: int = Inventory.count_item(id, ItemDB.WOOD)
	var total_stone: int = Inventory.count_item(id, ItemDB.STONE)
	totals[id] = {"wood": total_wood, "stone": total_stone}
	_send_slots_and_gain(id, total_wood, total_stone, msg)


func _send_slots_and_gain(id: int, total_wood: int, total_stone: int, msg: String) -> void:
	if id == multiplayer.get_unique_id() and Network.mode == Network.MODE_SERVER:
		_client_gain(total_wood, total_stone, msg)
		_client_sync_hotbar(Inventory.get_slots(id))
	elif _is_peer(id):
		_client_gain.rpc_id(id, total_wood, total_stone, msg)
		_client_sync_hotbar.rpc_id(id, Inventory.get_slots(id))


func _send_slots(id: int, slots: Array) -> void:
	if id == multiplayer.get_unique_id() and Network.mode == Network.MODE_SERVER:
		_client_sync_hotbar(slots)
	elif _is_peer(id):
		_client_sync_hotbar.rpc_id(id, slots)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_sync() -> void:
	if Network.mode != Network.MODE_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	ready_peers[id] = true
	var broken := PackedInt32Array()
	var xs := PackedFloat32Array() # 4 numbers per X: id, x, y, z
	for i in kinds.size():
		if not alive[i]:
			broken.append(i)
		elif x_on[i]:
			var p: Vector3 = x_pos[i]
			xs.append_array(PackedFloat32Array([float(i), p.x, p.y, p.z]))
	_client_sync.rpc_id(id, broken, xs)


@rpc("any_peer", "call_remote", "reliable")
func _server_strike(tool_index: int) -> void:
	if Network.mode != Network.MODE_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	do_strike(id, _tool_of_slot(id, tool_index))


# One swing of one player. The server uses where that player is and looks (from Network.players).
func do_strike(id: int, tool_index: int) -> void:
	if not Network.players.has(id) or tool_index < 0 or tool_index > 2:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_strike.get(id, -10.0)) < MIN_STRIKE_GAP:
		return
	last_strike[id] = now
	Inventory.init_player(id)

	var pl: Dictionary = Network.players[id]
	var feet: Vector3 = pl["pos"]
	var eye_height := 1.6
	if (int(pl["flags"]) & 1) != 0:
		eye_height = 1.0 # crouching
	var eye := feet + Vector3(0.0, eye_height, 0.0)
	var dir: Vector3 = Basis(Vector3.UP, float(pl["yaw"])) * (Basis(Vector3.RIGHT, float(pl["pitch"])) * Vector3.FORWARD)

	# What is in front of the player?
	var best := -1
	var best_t := REACH
	for i in kinds.size():
		if not alive[i] or kinds[i] == KIND_PLANT:
			continue
		var t := _ray_hit_node(i, eye, dir)
		if t >= 0.0 and t < best_t:
			best = i
			best_t = t
	if best < 0:
		return
	var hit_point := eye + dir * best_t

	var is_tree: bool = kinds[best] == KIND_TREE
	var per_hit: int = _roll(WOOD_PER_HIT[tool_index]) if is_tree else _roll(STONE_PER_HIT[tool_index])
	if per_hit <= 0:
		_send_gain_update(id, "Wrong tool: nothing")
		return

	# Did the swing land on the X?
	var x_hit := false
	if x_on[best]:
		var aim := _x_aim_point(best, eye, dir) # where your swing lands on the painted X
		x_hit = aim.size() == 1 and _x_visible(best, eye, aim[0]) # check visibility
	var amount: int = per_hit
	if x_hit:
		amount = roundi(per_hit * randf_range(X_BONUS_MIN, X_BONUS_MAX))
	amount = mini(amount, int(pools[best]))
	pools[best] = int(pools[best]) - amount
	var item := "wood" if is_tree else "stone"
	var item_id: String = ItemDB.WOOD if is_tree else ItemDB.STONE
	Inventory.add_item(id, item_id, amount)
	var msg := "+%d %s" % [amount, item]
	if x_hit:
		msg = "X hit!  " + msg
	# The X: it appears after the first hit and moves after you hit it
	if x_hit or not x_on[best]:
		x_on[best] = true
		_place_x(best, hit_point, x_hit)

	if int(pools[best]) <= 0:
		alive[best] = false
		x_on[best] = false
		respawn_at[best] = Time.get_ticks_msec() / 1000.0 + RESPAWN_TIME
		var fall_dir: Vector3 = Vector3(positions[best]) - feet
		fall_dir.y = 0.0
		if fall_dir.length() < 0.01:
			fall_dir = Vector3.FORWARD
		fall_dir = fall_dir.normalized()
		if is_tree:
			Inventory.add_item(id, ItemDB.WOOD, FELL_BONUS_WOOD)
			msg += "   Tree fell!  +%d wood" % FELL_BONUS_WOOD
		_broadcast_break(best, fall_dir)
	else:
		_broadcast_node_hit(best, Vector3(x_pos[best]))

	_send_gain_update(id, msg)


# Instant pickup of the nearest cloth plant within reach (server-authoritative, no aiming needed).
func _do_interact(id: int) -> void:
	if not Network.players.has(id):
		return
	Inventory.init_player(id)

	var pl: Dictionary = Network.players[id]
	var feet: Vector3 = pl["pos"]

	var best := -1
	var best_d := PLANT_REACH
	for i in kinds.size():
		if kinds[i] != KIND_PLANT or not alive[i]:
			continue
		var d: float = Vector3(positions[i]).distance_to(feet)
		if d < best_d:
			best = i
			best_d = d
	if best < 0:
		return

	alive[best] = false
	respawn_at[best] = Time.get_ticks_msec() / 1000.0 + PLANT_RESPAWN_TIME
	Inventory.add_item(id, ItemDB.CLOTH, CLOTH_PER_PLANT)

	_broadcast_plant_picked(best)
	_send_gain_update(id, "+%d Cloth" % CLOTH_PER_PLANT)


@rpc("any_peer", "call_remote", "reliable")
func _server_interact() -> void:
	if Network.mode != Network.MODE_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	_do_interact(id)


# Brings a depleted tree/rock/plant back after its respawn timer runs out.
func _do_respawn(id: int) -> void:
	alive[id] = true
	x_on[id] = false
	if kinds[id] == KIND_TREE:
		pools[id] = TREE_WOOD
	elif kinds[id] == KIND_ROCK:
		pools[id] = ROCK_STONE
	_broadcast_respawn(id)


# A spot for the X on the surface of the tree/rock, at a height that is easy to reach.
# moved = true means the X was just hit: it jumps to a clearly different place
# (the next flat side of the trunk, or somewhere else around the rock, and another height).
func _pick_x(i: int, hit_point: Vector3, moved: bool) -> Vector3:
	var c: Vector3 = positions[i]
	var s: float = scales[i]
	var side := 1.0 if randf() < 0.5 else -1.0
	if kinds[i] == KIND_TREE:
		# the 6 flat sides of the trunk face the angles 30, 90, 150 ... degrees
		var face := roundf((atan2(hit_point.z - c.z, hit_point.x - c.x) - PI / 6.0) / (PI / 3.0))
		if moved:
			face += side
		var angle := face * (PI / 3.0) + PI / 6.0
		var t_dy := randf_range(-0.3, 0.3)
		if moved:
			t_dy = randf_range(0.15, 0.4) * (1.0 if randf() < 0.5 else -1.0)
		var t_y := clampf(hit_point.y + t_dy, 0.45, 0.8 * s) # low on the trunk, well below the leaves
		var t_radius := (0.28 * s - 0.0444 * t_y) * 0.866 + 0.012 # the trunk surface at this height
		return Vector3(c.x + cos(angle) * t_radius, t_y, c.z + sin(angle) * t_radius)
	var center := c + Vector3(0.0, 0.5 * s, 0.0)
	var out := hit_point - center
	out.y = 0.0
	if out.length() < 0.01:
		out = Vector3.RIGHT
	var shift := randf_range(0.0, 0.4)
	if moved:
		shift = randf_range(0.45, 0.9)
	out = out.rotated(Vector3.UP, side * shift).normalized()
	var r_dy := randf_range(-0.25, 0.25)
	if moved:
		r_dy = randf_range(0.12, 0.3) * (1.0 if randf() < 0.5 else -1.0)
	var r_y := clampf(hit_point.y + r_dy, 0.3, minf(1.2, 0.8 * s))
	var r_radius := _rock_radius(r_y / s) * s * 0.97
	return Vector3(c.x + out.x * r_radius, r_y, c.z + out.z * r_radius)


# How wide the rock shape is at a height (0 = ground, 1 = top), as a fraction of its scale.
func _rock_radius(h: float) -> float:
	if h < 0.45:
		return 0.75 + 0.25 * (h / 0.45)
	if h < 0.85:
		return 1.0 - 0.45 * (h - 0.45) / 0.4
	return 0.55


# Puts the X of tree/rock i on its real surface (so the painted X and the hit box are the same thing).
func _place_x(i: int, hit_point: Vector3, moved: bool) -> void:
	var surf := _surface_at(i, _pick_x(i, hit_point, moved))
	x_pos[i] = surf[0]
	x_nrm[i] = surf[1]


# First FRONT face of a mesh along a ray: returns [world_point] or [] when nothing is hit.
# Back faces are not drawn in the game (you see through them), so they must never block anything.
func _front_hit(tm: TriangleMesh, faces: PackedVector3Array, xf: Transform3D, eye: Vector3, d: Vector3) -> Array:
	var inv := xf.affine_inverse()
	var lo: Vector3 = inv * eye
	var ld: Vector3 = (inv.basis * d).normalized()
	for step in 8:
		var hit: Dictionary = tm.intersect_ray(lo, ld)
		if hit.is_empty():
			return []
		var p: Vector3 = hit["position"]
		var f: int = int(hit["face_index"]) * 3
		if Plane(faces[f], faces[f + 1], faces[f + 2]).normal.dot(ld) < 0.0:
			return [xf * p] # this triangle faces the viewer
		lo = p + ld * 0.001 # that was a back face: look further
	return []


# The two directions lying flat on the surface where the X is painted: [sideways, upwards]. The painted X and its hit box both use them.
func _x_axes(n: Vector3) -> Array:
	var side := Vector3.UP.cross(n)
	if side.length() < 0.3:
		side = Vector3.RIGHT.cross(n) # the surface faces straight up or down
	side = side.normalized()
	return [side, n.cross(side).normalized()]


# Where a swing (from "eye", looking along "dir") lands on the painted X of tree/rock i.
# Returns [point], or [] if the swing misses the X. The swing is tested against the REAL surface of the
# tree/rock, and it counts only if it lands inside an invisible square around the X (a bit bigger than the red lines).
func _x_aim_point(i: int, eye: Vector3, dir: Vector3) -> Array:
	var xp: Vector3 = x_pos[i]
	var n: Vector3 = x_nrm[i]
	if dir.dot(n) > -0.1:
		return [] # looking along the surface or from behind it
	var hit := _front_hit(tree_tm, tree_faces, _node_xf(i), eye, dir)
	if kinds[i] != KIND_TREE:
		hit = _front_hit(rock_tms[i % 3], rock_faces[i % 3], _node_xf(i), eye, dir)
	if hit.is_empty():
		return []
	var q: Vector3 = hit[0]
	var box := X_BOX_TREE if kinds[i] == KIND_TREE else X_BOX_ROCK
	var axes := _x_axes(n)
	var off := q - xp
	if absf(off.dot(axes[0])) > box or absf(off.dot(axes[1])) > box or absf(off.dot(n)) > 0.3:
		return [] # outside the square around the X
	if eye.distance_to(q) > REACH + 0.2:
		return []
	return [q]


# True if nothing solid is between the player's eyes and the point of the X he is aiming at.
func _x_visible(i: int, eye: Vector3, target: Vector3) -> bool:
	var to_x := target - eye
	var dist := to_x.length()
	if dist < 0.01:
		return true
	var d := to_x / dist
	for j in kinds.size():
		if not alive[j] or kinds[j] == KIND_PLANT or Vector3(positions[j]).distance_to(eye) > 14.0:
			continue
		var xf := _node_xf(j)
		var shapes: Array = [] # each one: [mesh, its triangles]
		if kinds[j] == KIND_TREE:
			shapes.append([foliage_tm, foliage_faces]) # the leaves of every tree hide things behind them
			if j != i:
				shapes.append([tree_tm, tree_faces])
		elif j != i:
			shapes.append([rock_tms[j % 3], rock_faces[j % 3]])
		for sh in shapes:
			var hit := _front_hit(sh[0], sh[1], xf, eye, d)
			if not hit.is_empty() and eye.distance_to(hit[0]) < dist - 0.03:
				return false # another tree, rock or leaves are in the way
	var query := PhysicsRayQueryParameters3D.create(eye, target - d * 0.03)
	for b in bodies.values():
		if b is CollisionObject3D:
			query.exclude.append(b.get_rid()) # trees/rocks are already checked above, don't let their own collider block the X
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false # a wall (or anything solid) is in the way
	return true


func _ray_hit_node(i: int, origin: Vector3, dir: Vector3) -> float:
	var c: Vector3 = positions[i]
	var s: float = scales[i]
	if kinds[i] == KIND_TREE:
		return _ray_cylinder(origin, dir, c, 0.35 * s, 0.0, 2.2 * s)
	return _ray_sphere(origin, dir, c + Vector3(0.0, 0.5 * s, 0.0), 0.95 * s)


# Distance along the ray to a sphere, or -1 if it misses.
func _ray_sphere(o: Vector3, d: Vector3, center: Vector3, r: float) -> float:
	var oc := o - center
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	if cc < 0.0:
		return 0.0 # the ray starts inside
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0.0:
		return -1.0
	return t


# Distance along the ray to an upright cylinder (a trunk), or -1 if it misses.
func _ray_cylinder(o: Vector3, d: Vector3, base: Vector3, r: float, y0: float, y1: float) -> float:
	var ox := o.x - base.x
	var oz := o.z - base.z
	var a := d.x * d.x + d.z * d.z
	if a < 0.000001:
		return -1.0
	var b := ox * d.x + oz * d.z
	var cc := ox * ox + oz * oz - r * r
	var disc := b * b - a * cc
	if disc < 0.0:
		return -1.0
	var t := (-b - sqrt(disc)) / a
	if t < 0.0:
		return -1.0
	var y := o.y + d.y * t - base.y
	if y < y0 or y > y1:
		return -1.0
	return t


# ---------------------------------------------------------------- server -> client messages
@rpc("authority", "call_remote", "reliable")
func _client_sync(broken: PackedInt32Array, xs: PackedFloat32Array) -> void:
	for bid in broken:
		if bid >= 0 and bid < kinds.size():
			_remove_now(bid)
	var o := 0
	while o + 3 < xs.size():
		var id := int(xs[o])
		if id >= 0 and id < kinds.size() and alive[id]:
			_show_x(id, Vector3(xs[o + 1], xs[o + 2], xs[o + 3]))
		o += 4


@rpc("authority", "call_remote", "reliable")
func _client_node_hit(id: int, new_x_pos: Vector3) -> void:
	if id < 0 or id >= kinds.size() or not alive[id]:
		return
	_show_x(id, new_x_pos)
	if bodies.has(id):
		var visual: Node3D = bodies[id].get_child(0)
		var base := Vector3.ONE * float(scales[id])
		var tw := create_tween()
		tw.tween_property(visual, "scale", base * 1.06, 0.05)
		tw.tween_property(visual, "scale", base, 0.1)


@rpc("authority", "call_remote", "reliable")
func _client_break(id: int, fall_dir: Vector3) -> void:
	if id < 0 or id >= kinds.size() or not alive[id]:
		return
	alive[id] = false
	_hide_x(id)
	if not bodies.has(id):
		return
	var body: StaticBody3D = bodies[id]
	bodies.erase(id)
	body.collision_layer = 0 # walk through it from now on
	var tw := create_tween()
	if kinds[id] == KIND_TREE:
		var axis := Vector3.UP.cross(fall_dir)
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		axis = axis.normalized()
		tw.tween_method(func(a: float) -> void: body.basis = Basis(axis, a), 0.0, PI * 0.5, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(3.0)
	else:
		tw.tween_property(body.get_child(0), "scale", Vector3.ONE * 0.01, 0.25)
	tw.tween_callback(body.queue_free)


@rpc("authority", "call_remote", "reliable")
func _client_plant_picked(id: int) -> void:
	if id < 0 or id >= kinds.size():
		return
	alive[id] = false
	if bodies.has(id):
		bodies[id].queue_free()
		bodies.erase(id)


@rpc("authority", "call_remote", "reliable")
func _client_respawn(id: int) -> void:
	if id < 0 or id >= kinds.size():
		return
	alive[id] = true
	x_on[id] = false
	_build_one(id)


@rpc("authority", "call_remote", "reliable")
func _client_gain(total_wood: int, total_stone: int, msg: String) -> void:
	wood_total = total_wood
	stone_total = total_stone
	_refresh_hud()
	if msg != "":
		_show_message(msg)


# Turns 20 or [18, 24] into a number. A list means "random between the two".
func _roll(v) -> int:
	if v is Array:
		return randi_range(int(v[0]), int(v[1]))
	return int(v)


@rpc("authority", "call_remote", "reliable")
func _client_sync_hotbar(slots: Array) -> void:
	if HotbarUI.instance != null and is_instance_valid(HotbarUI.instance):
		HotbarUI.instance.set_slots(slots)
	if InventoryUI.instance != null and is_instance_valid(InventoryUI.instance):
		InventoryUI.instance.set_slots(slots)


func _do_move_item(id: int, from_idx: int, to_idx: int) -> void:
	if Inventory.move_slot(id, from_idx, to_idx):
		_send_slots(id, Inventory.get_slots(id))


# Direct call used when this process is the host (no RPC needed for itself).
func move_item_for(id: int, from_idx: int, to_idx: int) -> void:
	_do_move_item(id, from_idx, to_idx)


@rpc("any_peer", "call_remote", "reliable")
func _server_move_item(from_idx: int, to_idx: int) -> void:
	if Network.mode != Network.MODE_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	_do_move_item(id, from_idx, to_idx)


func _do_craft_item(id: int, item_id: String) -> void:
	var recipes := {
		"axe": {"wood": 200, "stone": 100},
		"pickaxe": {"wood": 200, "stone": 100},
		"hammer": {"wood": 100},
		"wood_spear": {"wood": 200},
		"stone_arrow": {"wood": 1, "stone": 1},
		"campfire": {"wood": 100},
		"building_plan": {"wood": 50},
	}
	if not recipes.has(item_id):
		return
	var cost: Dictionary = recipes[item_id]

	for c_id in cost:
		if Inventory.count_item(id, c_id) < cost[c_id]:
			return

	var craft_amount := 2 if item_id == "stone_arrow" else 1
	if not Inventory.can_add(id, item_id, craft_amount):
		return

	for c_id in cost:
		Inventory.remove_item(id, c_id, cost[c_id])

	Inventory.add_item(id, item_id, craft_amount)
	_send_slots(id, Inventory.get_slots(id))


# Direct call used when this process is the host (no RPC needed for itself).
func craft_item_for(id: int, item_id: String) -> void:
	_do_craft_item(id, item_id)


@rpc("any_peer", "call_remote", "reliable")
func _server_craft_item(item_id: String) -> void:
	if Network.mode != Network.MODE_SERVER:
		return
	var id := multiplayer.get_remote_sender_id()
	_do_craft_item(id, item_id)


func _tool_of_slot(id: int, slot_index: int) -> int:
	Inventory.init_player(id)
	var slots: Array = Inventory.get_slots(id)
	if slot_index < 0 or slot_index >= 6 or slot_index >= slots.size():
		return -1
	var item_id := str(slots[slot_index].get("id", ""))
	if item_id == "rock":
		return 0
	if item_id == "axe":
		return 1
	if item_id == "pickaxe":
		return 2
	return -1
