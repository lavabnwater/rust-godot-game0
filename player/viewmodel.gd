extends Node3D
# First-person hands and the item held. Every animation is procedural (code only, no files).

signal strike # emitted at the moment a swing lands

const LowPoly = preload("res://world/lowpoly.gd")

const SWING_TIME := 0.5 # seconds for one full swing
const RIGHT_REST := Vector3(0.25, -0.26, -0.52) # where the right hand rests
const LEFT_REST := Vector3(-0.25, -0.28, -0.5)
const RIGHT_BASE_ROT := Vector3(0.2, 0.13, 0.0)
const LEFT_BASE_ROT := Vector3(0.2, -0.13, 0.0)

var player # set by player.gd
var look_delta := Vector2.ZERO # mouse movement this frame, set by player.gd

var right_arm: Node3D
var left_arm: Node3D
var tool_nodes: Array = [] # 0 = rock, 1 = axe, 2 = pickaxe
var time := 0.0
var bob_phase := 0.0
var bob_amount := 0.0
var sprint_blend := 0.0 # 0 = normal pose, 1 = full sprint pose
var sway := Vector2.ZERO
var swing_t := -1.0 # < 0 means not swinging, otherwise 0..1 progress
var struck := false


func _ready() -> void:
	right_arm = _make_arm()
	left_arm = _make_arm()
	add_child(right_arm)
	add_child(left_arm)
	tool_nodes.append(_add_rock(right_arm))
	tool_nodes.append(_add_axe(right_arm))
	tool_nodes.append(_add_pickaxe(right_arm))
	set_tool(0)


# Shows only the chosen tool in the hand: 0 = rock, 1 = axe, 2 = pickaxe
func set_tool(id: int) -> void:
	for i in tool_nodes.size():
		tool_nodes[i].visible = (i == id)


func is_swinging() -> bool:
	return swing_t >= 0.0


func try_swing() -> bool:
	if is_swinging():
		return false
	swing_t = 0.0
	struck = false
	return true


func _process(delta: float) -> void:
	if player == null:
		return
	time += delta
	var speed: float = player.horizontal_speed()
	var on_floor: bool = player.is_on_floor()

	# --- smooth blends ---
	var sprint_target := 0.0
	if player.sprinting and speed > 1.0:
		sprint_target = 1.0
	sprint_blend = move_toward(sprint_blend, sprint_target, delta * 6.0)
	var bob_target := 0.0
	if on_floor and speed > 0.5:
		bob_target = clampf(speed / 5.0, 0.0, 1.6)
	bob_amount = move_toward(bob_amount, bob_target, delta * 6.0)
	bob_phase += delta * speed * 1.15

	# --- mouse sway: hands lag behind the camera ---
	var want_sway := (look_delta * 0.0006).limit_length(0.06)
	sway = sway.lerp(want_sway, clampf(delta * 10.0, 0.0, 1.0))
	look_delta = Vector2.ZERO

	# --- whole-viewmodel motion (idle breathing, walk bob, sprint pose, jump / landing) ---
	var breathe := sin(time * 1.6)
	var pos := Vector3(
		sin(bob_phase) * 0.012 * bob_amount,
		absf(cos(bob_phase)) * -0.016 * bob_amount + breathe * 0.004,
		0.0)
	var rot := Vector3(breathe * 0.004, 0.0, 0.0)
	pos += Vector3(0.0, -0.02, 0.0) * sprint_blend
	rot.x += -0.12 * sprint_blend # hands tilt down a little when sprinting
	if not on_floor:
		pos.y += clampf(-player.velocity.y * 0.006, -0.06, 0.06)
	pos.y -= player.land_offset * 0.8
	rot.x += sway.y
	rot.y += sway.x
	position = pos
	rotation = rot

	# --- per-arm motion ---
	var r_pos := RIGHT_REST
	var r_rot := RIGHT_BASE_ROT
	var l_pos := LEFT_REST
	var l_rot := LEFT_BASE_ROT
	var pump := sin(bob_phase) * 0.03 * bob_amount * (0.4 + 0.6 * sprint_blend)
	r_pos.z += pump # arms pump forward and back while running
	l_pos.z -= pump

	if swing_t >= 0.0:
		swing_t += delta / SWING_TIME
		var w := _swing_curve(swing_t) # +1 = wound up, -1 = fully struck
		if swing_t >= 0.45 and not struck:
			struck = true
			strike.emit()
		if swing_t >= 1.0:
			swing_t = -1.0
		if w > 0.0:
			r_pos += Vector3(0.02, 0.14, 0.08) * w
			r_rot += Vector3(0.9, 0.0, -0.3) * w
		else:
			var s := -w
			r_pos += Vector3(-0.08, -0.1, -0.14) * s
			r_rot += Vector3(-0.5, 0.1, 0.15) * s
		l_pos.y += 0.03 * absf(w)

	right_arm.position = r_pos
	right_arm.rotation = r_rot
	left_arm.position = l_pos
	left_arm.rotation = l_rot


# +1 = wound up, -1 = struck. Wind-up, fast strike, slower recovery.
func _swing_curve(t: float) -> float:
	if t < 0.30:
		return smoothstep(0.0, 0.30, t)
	if t < 0.45:
		return 1.0 - 2.0 * smoothstep(0.30, 0.45, t)
	return -1.0 * (1.0 - smoothstep(0.45, 1.0, t))


func _make_arm() -> Node3D:
	var arm := Node3D.new()
	var skin := LowPoly.material(Color(0.72, 0.52, 0.4))
	var sleeve := LowPoly.material(Color(0.2, 0.27, 0.42))
	arm.add_child(_box(Vector3(0.085, 0.085, 0.11), Vector3.ZERO, skin)) # fist
	arm.add_child(_box(Vector3(0.065, 0.065, 0.22), Vector3(0.0, 0.0, 0.16), skin)) # forearm
	arm.add_child(_box(Vector3(0.085, 0.085, 0.4), Vector3(0.0, 0.0, 0.46), sleeve)) # sleeve
	return arm


func _add_rock(arm: Node3D) -> Node3D:
	var rock := MeshInstance3D.new()
	rock.mesh = LowPoly.rock(7)
	rock.material_override = LowPoly.material(Color(0.5, 0.5, 0.52))
	rock.scale = Vector3.ONE * 0.085
	rock.position = Vector3(0.0, 0.04, -0.08)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(rock)
	return rock


# Axe: a long wooden handle held upright, with a flat steel blade at the top pointing forward.
func _add_axe(arm: Node3D) -> Node3D:
	var holder := Node3D.new()
	var wood := LowPoly.material(Color(0.45, 0.3, 0.18))
	var steel := LowPoly.material(Color(0.62, 0.64, 0.68))
	holder.add_child(_box(Vector3(0.035, 0.5, 0.035), Vector3(0.0, 0.2, -0.03), wood)) # handle
	holder.add_child(_box(Vector3(0.03, 0.13, 0.2), Vector3(0.0, 0.4, -0.12), steel)) # blade
	holder.visible = false
	arm.add_child(holder)
	return holder


# Pickaxe: same handle, with a long steel head across the top.
func _add_pickaxe(arm: Node3D) -> Node3D:
	var holder := Node3D.new()
	var wood := LowPoly.material(Color(0.45, 0.3, 0.18))
	var steel := LowPoly.material(Color(0.62, 0.64, 0.68))
	holder.add_child(_box(Vector3(0.035, 0.5, 0.035), Vector3(0.0, 0.2, -0.03), wood)) # handle
	holder.add_child(_box(Vector3(0.035, 0.05, 0.4), Vector3(0.0, 0.44, -0.03), steel)) # head
	holder.visible = false
	arm.add_child(holder)
	return holder


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
