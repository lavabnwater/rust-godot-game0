extends Node

# ============================================================
# SURVIVAL GAME - GLOBAL GAME STATE
# Autoload singleton: "GameState"
# Holds settings that must survive between scenes.
# ============================================================

# اسم اللعبة الثابت.
const GAME_NAME: String = "SURVIVE"

# رقم إصدار بروتوكول الشبكة. ارفعه كلما غيّرت شكل رسائل RPC.
const PROTOCOL_VERSION: int = 1

# المنفذ الافتراضي للسيرفر.
const DEFAULT_PORT: int = 7777

# أقصى عدد لاعبين افتراضي.
const DEFAULT_MAX_PLAYERS: int = 30

# أقصى طول مسموح لاسم اللاعب (موحّد مع network.gd).
const MAX_NAME_LENGTH: int = 16

# مسار ملف حفظ إعدادات اللاعب المحلي.
const SETTINGS_PATH: String = "user://player.cfg"

# true إذا كانت هذه النسخة يجب أن تعمل كسيرفر مخصص.
var is_server: bool = false

# المنفذ الذي سيُستخدم عند تشغيل سيرفر محلي.
var port: int = DEFAULT_PORT

# أقصى عدد لاعبين يقبلهم السيرفر المحلي.
var max_players: int = DEFAULT_MAX_PLAYERS

# اسم اللاعب المحلي كما سيظهر للآخرين.
var player_name: String = "Player"

# رسالة تُعرض في القائمة الرئيسية بعد خطأ أو قطع اتصال.
var message_for_menu: String = ""

# true يعني تخطّي شاشة البداية (Splash) بعد رجوع من خطأ.
var skip_splash: bool = false


# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:

	randomize()

	player_name = "Player%d" % randi_range(100, 999)

	_load_settings()

	_read_launch_arguments()


# ============================================================
# LOAD / SAVE LOCAL SETTINGS
# ============================================================

func _load_settings() -> void:

	var cfg := ConfigFile.new()

	if cfg.load(SETTINGS_PATH) == OK:

		var saved_name: String = str(
			cfg.get_value(
				"player",
				"name",
				player_name
			)
		)

		player_name = clean_name(saved_name)


func save_settings() -> void:

	var cfg := ConfigFile.new()

	cfg.set_value(
		"player",
		"name",
		player_name
	)

	var err := cfg.save(SETTINGS_PATH)

	if err != OK:

		push_warning(
			"Could not save settings. Error: %d"
			% err
		)


# ============================================================
# LAUNCH ARGUMENTS (dedicated server support)
# ============================================================

func _read_launch_arguments() -> void:

	var args: PackedStringArray = _all_args()

	is_server = (
		args.has("--server")
		or DisplayServer.get_name() == "headless"
		or OS.has_feature("dedicated_server")
	)

	port = clampi(
		_arg_value_as_int(
			"--port",
			DEFAULT_PORT
		),
		1,
		65535
	)

	max_players = clampi(
		_arg_value_as_int(
			"--max-players",
			DEFAULT_MAX_PLAYERS
		),
		1,
		256
	)


func is_dedicated_server() -> bool:

	return is_server


# ============================================================
# NAME CLEANING
# ============================================================

func clean_name(raw: String) -> String:

	var n: String = raw.strip_edges().left(
		MAX_NAME_LENGTH
	)

	if n.is_empty():

		n = "Player"

	return n


# ============================================================
# MENU MESSAGE HELPERS
# ============================================================

func set_menu_message(text: String) -> void:

	message_for_menu = text

	skip_splash = true


func consume_menu_message() -> String:

	var text: String = message_for_menu

	message_for_menu = ""

	return text


# ============================================================
# ARGUMENT PARSING
# ============================================================

func _all_args() -> PackedStringArray:

	var a := PackedStringArray()

	a.append_array(OS.get_cmdline_args())

	a.append_array(OS.get_cmdline_user_args())

	return a


# يقرأ --key=value أو --key value من سطر الأوامر.
func _arg_value(
	key: String,
	default_value: String
) -> String:

	var args: PackedStringArray = _all_args()

	for i in range(args.size()):

		if args[i].begins_with(key + "="):

			return args[i].substr(
				key.length() + 1
			)

		if args[i] == key and i + 1 < args.size():

			return args[i + 1]

	return default_value


# نسخة آمنة ترجع رقم صحيح مباشرة مع قيمة افتراضية.
func _arg_value_as_int(
	key: String,
	default_value: int
) -> int:

	var raw: String = _arg_value(
		key,
		str(default_value)
	)

	if raw.is_valid_int():

		return int(raw)

	return default_value
