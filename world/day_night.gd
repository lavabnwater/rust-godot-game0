extends Node
# دورة ليل/نهار بسيطة: تتحكم بدوران الشمس وقوة ضوئها بمرور الوقت.

const DAY_LENGTH := 30.0 * 60.0 # 30 دقيقة نهار
const NIGHT_LENGTH := 10.0 * 60.0 # 10 دقائق ليل
const TOTAL_LENGTH := DAY_LENGTH + NIGHT_LENGTH

const DAY_ENERGY := 0.7
const NIGHT_ENERGY := 0.05

var _sun: DirectionalLight3D = null
var _t := 0.0


func setup(sun_light: DirectionalLight3D) -> void:
	_sun = sun_light
	_t = 0.0


func _process(delta: float) -> void:
	if _sun == null or not is_instance_valid(_sun):
		return
	_t = fmod(_t + delta, TOTAL_LENGTH)
	var phase := _t / TOTAL_LENGTH # 0..1 خلال اليوم كامل
	var angle := phase * 360.0
	_sun.rotation_degrees.x = -50.0 + sin(phase * TAU) * 40.0
	var day_frac := _t / TOTAL_LENGTH
	var is_day := _t < DAY_LENGTH
	var energy := DAY_ENERGY if is_day else NIGHT_ENERGY
	_sun.light_energy = lerp(_sun.light_energy, energy, delta * 0.5)
	_sun.rotation_degrees.y = -35.0 + angle
