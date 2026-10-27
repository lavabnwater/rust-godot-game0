extends RefCounted
# Input actions. Keys use physical positions, so they work with any keyboard language.
# The Settings batch will rebind these actions later.


static func register() -> void:
	_add("move_forward", [_key(KEY_W), _key(KEY_UP)])
	_add("move_back", [_key(KEY_S), _key(KEY_DOWN)])
	_add("move_left", [_key(KEY_A), _key(KEY_LEFT)])
	_add("move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_add("sprint", [_key(KEY_SHIFT)])
	_add("crouch", [_key(KEY_CTRL)])
	_add("jump", [_key(KEY_SPACE)])
	_add("attack", [_mouse(MOUSE_BUTTON_LEFT)])
	_add("inventory", [_key(KEY_TAB)])
	_add("crafting", [_key(KEY_Q)])
	_add("interact", [_key(KEY_E)])
	_add("map", [_key(KEY_G)])

static func _add(action: String, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for e in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e
