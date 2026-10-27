extends CanvasLayer
# كل شاشات البداية (تُبنى بالكود): splash, main, servers, settings, loading

signal join_requested(address: String, port: int)
signal host_requested()

var screens := {} # اسم الشاشة -> CenterContainer
var message_label: Label
var name_edit: LineEdit
var list_box: VBoxContainer
var direct_edit: LineEdit
var servers_status: Label
var loading_label: Label


func _ready() -> void:
	layer = 10
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_splash()
	_build_main()
	_build_servers()
	_build_settings()
	_build_loading()
	message_label.text = GameState.message_for_menu
	GameState.message_for_menu = ""
	if GameState.skip_splash:
		_show("main")
	else:
		await _play_splash()
		_show("main")


func show_loading(text: String) -> void:
	loading_label.text = text
	_show("loading")


# ---------------------------------------------------------------- أدوات بناء
func _make_screen(id: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	add_child(center)
	screens[id] = center
	return box


func _label(parent: Control, text: String, size: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show(id: String) -> void:
	for k in screens:
		screens[k].visible = (k == id)
	if id == "servers":
		_refresh_servers()


# ---------------------------------------------------------------- الشاشات
func _build_splash() -> void:
	var box := _make_screen("splash")
	_label(box, GameState.GAME_NAME, 84)
	_label(box, "Game started", 20, Color(0.7, 0.8, 0.7))


func _play_splash() -> void:
	_show("splash")
	var s: Control = screens["splash"]
	s.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(s, "modulate:a", 1.0, 0.6)
	t.tween_interval(1.2)
	t.tween_property(s, "modulate:a", 0.0, 0.5)
	await t.finished


func _build_main() -> void:
	var box := _make_screen("main")
	_label(box, GameState.GAME_NAME, 64)
	message_label = _label(box, "", 18, Color(1.0, 0.55, 0.45))
	_label(box, "Your name", 16, Color(0.7, 0.7, 0.7))
	name_edit = LineEdit.new()
	name_edit.text = GameState.player_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(0, 40)
	name_edit.add_theme_font_size_override("font_size", 20)
	box.add_child(name_edit)
	_button(box, "Play", _show.bind("servers"))
	_button(box, "Host (start server here)", _on_host_pressed)
	_button(box, "Settings", _show.bind("settings"))


func _on_host_pressed() -> void:
	GameState.player_name = GameState.clean_name(name_edit.text)
	GameState.save_settings()
	show_loading("Starting server...")
	host_requested.emit()


func _build_servers() -> void:
	var box := _make_screen("servers")
	_label(box, "Servers", 48)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	box.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)
	servers_status = _label(box, "", 16, Color(1.0, 0.8, 0.5))
	_label(box, "Direct connect (IP:port)", 16, Color(0.7, 0.7, 0.7))
	var row := HBoxContainer.new()
	box.add_child(row)
	direct_edit = LineEdit.new()
	direct_edit.text = "127.0.0.1:%d" % GameState.DEFAULT_PORT
	direct_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direct_edit.custom_minimum_size = Vector2(0, 40)
	direct_edit.add_theme_font_size_override("font_size", 20)
	direct_edit.text_submitted.connect(_on_direct_submitted)
	row.add_child(direct_edit)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.custom_minimum_size = Vector2(90, 40)
	join_btn.pressed.connect(_join_direct)
	row.add_child(join_btn)
	_button(box, "Back", _show.bind("main"))


func _build_settings() -> void:
	var box := _make_screen("settings")
	_label(box, "Settings", 48)
	_label(box, "Settings will be added in a later batch.", 18, Color(0.7, 0.7, 0.7))
	_button(box, "Back", _show.bind("main"))


func _build_loading() -> void:
	var box := _make_screen("loading")
	loading_label = _label(box, "Loading...", 30)


# ---------------------------------------------------------------- قائمة السيرفرات
func _load_servers() -> Array:
	var path := "user://servers.json" # نسخة المستخدم لها الأولوية
	if not FileAccess.file_exists(path):
		path = "res://servers.json"
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		data = data.get("servers", [])
	if typeof(data) != TYPE_ARRAY:
		return []
	return data


func _refresh_servers() -> void:
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	servers_status.text = ""
	var count := 0
	for s in _load_servers():
		if typeof(s) != TYPE_DICTIONARY or not s.has("address"):
			continue
		var address := str(s["address"])
		var port := int(s.get("port", GameState.DEFAULT_PORT))
		var title := str(s.get("name", address))
		_button(list_box, "%s   (%s:%d)" % [title, address, port], _join.bind(address, port))
		count += 1
	if count == 0:
		servers_status.text = "No servers found in servers.json. Use Direct connect below."


func _on_direct_submitted(_text: String) -> void:
	_join_direct()


func _join_direct() -> void:
	var t := direct_edit.text.strip_edges()
	if t.is_empty():
		return
	var address := t
	var port: int = GameState.DEFAULT_PORT
	var idx := t.rfind(":")
	if idx > 0:
		address = t.substr(0, idx)
		var p := t.substr(idx + 1)
		if not p.is_valid_int() or int(p) < 1 or int(p) > 65535:
			servers_status.text = "Invalid port."
			return
		port = int(p)
	_join(address, port)


func _join(address: String, port: int) -> void:
	GameState.player_name = GameState.clean_name(name_edit.text)
	GameState.save_settings()
	show_loading("Connecting to %s:%d ..." % [address, port])
	join_requested.emit(address, port)
