extends Node3D

# ============================================================
# SURVIVAL GAME - REMOTE PLAYER (other players on the client)
# Low-poly body + name tag + smooth interpolated movement.
# ============================================================

const LowPoly = preload("res://world/lowpoly.gd")

# نؤخر العرض 0.1 ثانية لتكون الحركة ناعمة بدل القفز بين الحزم.
const INTERP_DELAY: float = 0.1

# أقصى عدد حزم نحتفظ بها في الذاكرة لكل لاعب بعيد.
const BUFFER_MAX: int = 20

# أقصى مسافة قفزة نعتبرها طبيعية، وإلا ننقل اللاعب فوراً بدون تنعيم.
const TELEPORT_DISTANCE: float = 6.0

# معرف اللاعب صاحب هذا الجسم.
var peer_id: int = 0

# اسم اللاعب (محفوظ لاستخدامه لاحقاً في الفرق والدردشة).
var player_name: String = ""

# كل عنصر: [time, position, yaw, pitch, flags]
var buffer: Array = []

# مقدار انحناء الجسم الحالي (0 = واقف، 1 = منحني بالكامل).
var crouch_amount: float = 0.0

var torso: MeshInstance3D
var head_node: Node3D
var label: Label3D


# ============================================================
# TIME HELPER
# ============================================================

func _now() -> float:

	return Time.get_ticks_msec() / 1000.0


# ============================================================
# SETUP
# ============================================================

func setup(
	id: int,
	pname: String,
	pos: Vector3
) -> void:

	peer_id = id

	player_name = pname

	name = "RemotePlayer_%d" % id

	position = pos

	buffer.append([
		_now(),
		pos,
		0.0,
		0.0,
		0
	])

	_build_body(pname)


# ============================================================
# BUILD VISUAL BODY (low-poly, no textures)
# ============================================================

func _build_body(pname: String) -> void:

	# لون مختلف لكل لاعب حسب معرفه.
	var mat := LowPoly.material(
		Color.from_hsv(
			fposmod(peer_id * 0.618034, 1.0),
			0.55,
			0.85
		)
	)

	torso = MeshInstance3D.new()

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.36
	capsule.height = 1.5
	capsule.radial_segments = 8
	capsule.rings = 3

	torso.mesh = capsule
	torso.material_override = mat
	torso.position.y = 0.75

	add_child(torso)

	head_node = Node3D.new()
	head_node.position.y = 1.62

	add_child(head_node)

	var head_mesh := MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	sphere.radial_segments = 8
	sphere.rings = 4

	head_mesh.mesh = sphere
	head_mesh.material_override = mat

	head_node.add_child(head_mesh)

	# صندوق بسيط يوضح اتجاه النظر (الوجه).
	var visor := MeshInstance3D.new()

	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.08, 0.1)

	visor.mesh = box
	visor.material_override = LowPoly.material(
		Color(0.1, 0.1, 0.12)
	)
	visor.position = Vector3(0.0, 0.03, -0.17)

	head_node.add_child(visor)

	label = Label3D.new()
	label.text = pname
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.1

	add_child(label)


# ============================================================
# RECEIVE NETWORK STATE
# ============================================================

func push_state(
	t: float,
	pos: Vector3,
	yaw: float,
	pitch: float,
	flags: int
) -> void:

	buffer.append([
		t,
		pos,
		yaw,
		pitch,
		flags
	])

	if buffer.size() > BUFFER_MAX:

		buffer.pop_front()


# ============================================================
# INTERPOLATION + VISUAL UPDATE
# ============================================================

func _process(delta: float) -> void:

	if buffer.is_empty():
		return

	var rt: float = _now() - INTERP_DELAY

	var n: int = buffer.size()

	var a: Array = buffer[0]
	var b: Array = buffer[0]

	for i in range(n - 1, -1, -1):

		if buffer[i][0] <= rt:

			a = buffer[i]
			b = buffer[mini(i + 1, n - 1)]

			break

	var w: float = 0.0

	if b[0] > a[0]:

		w = clampf(
			(rt - a[0]) / (b[0] - a[0]),
			0.0,
			1.0
		)

	var pa: Vector3 = a[1]
	var pb: Vector3 = b[1]

	if pa.distance_to(pb) > TELEPORT_DISTANCE:

		# قفزة كبيرة (تصحيح موقع أو إعادة ظهور): بدون تنعيم.
		w = 1.0

	position = pa.lerp(pb, w)

	rotation.y = lerp_angle(a[2], b[2], w)

	# نستخدم آخر حالة معروفة فعلياً (وليست المؤخّرة) لجعل
	# الانحناء والجري يبدوان أسرع استجابة من الموقع نفسه.
	var latest: Array = buffer[n - 1]
	var latest_flags: int = int(latest[4])

	var crouched: bool = (latest_flags & 1) != 0

	crouch_amount = move_toward(
		crouch_amount,
		1.0 if crouched else 0.0,
		delta * 8.0
	)

	var s: float = lerpf(1.0, 0.55, crouch_amount)

	torso.scale.y = s
	torso.position.y = 0.75 * s

	head_node.position.y = lerpf(1.62, 0.9, crouch_amount)
	head_node.rotation.x = lerpf(a[3], b[3], w)

	label.position.y = head_node.position.y + 0.5
