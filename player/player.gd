extends CharacterBody3D

const ControlsScript = preload("res://player/controls.gd")
const ViewmodelScript = preload("res://player/viewmodel.gd")

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5 # must stay under Network.MAX_SPEED
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 6.3 # about 1 meter high, must stay under Network.MAX_RISE_SPEED
const GRAVITY := 20.0
const GROUND_ACCEL := 45.0
const AIR_ACCEL := 8.0
const MOUSE_SENS := 0.0025
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_STAND := 1.6
const EYE_CROUCH := 1.0
const FOV_NORMAL := 75.0
const FOV_SPRINT := 80.0

# Temporary safety net until the beach spawn system (Batch 4) exists.
const WORLD_FALL_LIMIT := -30.0
const FALL_SAFE_POSITION := Vector3(0.0, 1.0, 0.0)

# Emitted when the player falls out of the world. world.gd will later
# catch this and send the player to a random beach spawn (Batch 4).
signal fell_out_of_world()

var can_sprint := true # set to false by the thirst system when thirst reaches 0 (Batch 7)
var active := true # false while the mouse is released (Esc)
var crouching := false # read directly by network.gd to send the crouch flag
var sprinting := false # read directly by network.gd to send the sprint flag
var land_offset := 0.0 # camera dip after landing (meters)
var kick := 0.0 # camera pitch punch (radians), used when attacking
var crouch_amount := 0.0 # 0 = standing, 1 = crouched (smooth, for the camera)
var bob_phase := 0.0
var bob_amount := 0.0
var attack_blocked := false

var head: Node3D # read directly by network.gd to send the look pitch
var bob: Node3D
var camera: Camera3D
var viewmodel
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var stand_check: CylinderShape3D # checks the space above a crouched player


func _ready() -> void:
	ControlsScript.register()
	floor_snap_length = 0.3

	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = STAND_HEIGHT
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0.0, STAND_HEIGHT / 2.0, 0.0)
	add_child(shape)

	stand_check = CylinderShape3D.new()
	stand_check.radius = 0.38
	stand_check.height = STAND_HEIGHT - CROUCH_HEIGHT - 0.04

	head = Node3D.new()
	head.position = Vector3(0.0, EYE_STAND, 0.0)
	add_child(head)
	bob = Node3D.new()
	head.add_child(bob)
	camera = Camera3D.new()
	camera.fov = FOV_NORMAL
	camera.near = 0.05
	camera.far = 400.0
	bob.add_child(camera)
	camera.make_current()

	viewmodel = ViewmodelScript.new()
	viewmodel.player = self
	camera.add_child(viewmodel)
	viewmodel.strike.connect(_on_strike)

	_set_active(true)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _set_active(value: bool) -> void:
	active = value
	if value and not InventoryUI.is_open and not CraftingUI.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_strike() -> void:
	kick = 0.03


func _unhandled_input(event: InputEvent) -> void:
	# If inventory or crafting is open, don't rotate camera with mouse
	if InventoryUI.is_open or CraftingUI.is_open:
		return

	if event is InputEventMouseMotion and active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.5, 1.5)
		viewmodel.look_delta += event.relative
	elif event is InputEventMouseButton and event.pressed and not active:
		_set_active(true) # click to grab the mouse again
		attack_blocked = true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and active:
		_set_active(false)


func _physics_process(delta: float) -> void:
	var prev_vy := velocity.y
	var was_on_floor := is_on_floor()

	# Crouch (hold Ctrl). You can't stand up while something is above you.
	if (active or InventoryUI.is_open or CraftingUI.is_open) and Input.is_action_pressed("crouch"):
		crouching = true
	elif crouching and _can_stand():
		crouching = false
	var h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if not is_equal_approx(capsule.height, h):
		capsule.height = h
		shape.position.y = h / 2.0

	# Gravity and jump
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif (active or InventoryUI.is_open or CraftingUI.is_open) and not crouching and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	# Walk / sprint / crouch-walk
	var input := Vector2.ZERO
	if active or InventoryUI.is_open or CraftingUI.is_open:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprinting = (active or InventoryUI.is_open or CraftingUI.is_open) and can_sprint and not crouching and Input.is_action_pressed("sprint") and input.y < -0.1
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	var dir := transform.basis * Vector3(input.x, 0.0, input.y)
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	move_and_slide()

	# Landing dip
	if is_on_floor() and not was_on_floor and prev_vy < -4.0:
		land_offset = clampf(-prev_vy * 0.012, 0.0, 0.18)

	# Safety net: fell out of the world. Temporary position until
	# the beach respawn system (Batch 4) takes over via the signal below.
	if global_position.y < WORLD_FALL_LIMIT:
		global_position = FALL_SAFE_POSITION
		velocity = Vector3.ZERO
		fell_out_of_world.emit()


func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = stand_check
	var center_y := CROUCH_HEIGHT + 0.02 + stand_check.height / 2.0
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, center_y, 0.0))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _process(delta: float) -> void:
	# Camera height (smooth crouch)
	crouch_amount = move_toward(crouch_amount, 1.0 if crouching else 0.0, delta * 8.0)
	head.position.y = lerpf(EYE_STAND, EYE_CROUCH, crouch_amount)

	# Head bob
	var speed := horizontal_speed()
	var bob_target := 0.0
	if is_on_floor() and speed > 0.5:
		bob_target = clampf(speed / WALK_SPEED, 0.0, 1.6)
	bob_amount = move_toward(bob_amount, bob_target, delta * 6.0)
	bob_phase += delta * speed * 1.15
	land_offset = lerpf(land_offset, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	bob.position = Vector3(
		sin(bob_phase) * 0.02 * bob_amount,
		sin(bob_phase * 2.0) * 0.025 * bob_amount - land_offset,
		0.0)

	# Strike punch and sprint FOV
	kick = lerpf(kick, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	camera.rotation.x = -kick
	var fov_target := FOV_SPRINT if sprinting else FOV_NORMAL
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 8.0, 0.0, 1.0))

	# Attack (hold to keep swinging)
	if InventoryUI.is_open or CraftingUI.is_open:
		return
	if not Input.is_action_pressed("attack"):
		attack_blocked = false
	elif active and not attack_blocked:
		viewmodel.try_swing()

# The server calls this when it moves the player back (speed correction)
func network_teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO

# Enables WASD movement while freeing mouse for inventory
func set_inventory_mode(open_inv: bool) -> void:
	if open_inv:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		attack_blocked = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		attack_blocked = false
