extends Node

# ============================================================
# SURVIVAL GAME - NETWORK MANAGER
# Godot 4.x
# ENet Multiplayer
# Server Tick: 20 Hz
# ============================================================

signal connected_to_host()
signal welcomed(spawn_pos: Vector3)
signal failed(text: String)

signal player_connected(id: int)
signal player_disconnected(id: int)

# ============================================================
# CONFIGURATION
# ============================================================

const TICK: float = 0.05
const CONNECT_TIMEOUT: float = 8.0

const MAX_SPEED: float = 10.0
const MAX_RISE_SPEED: float = 9.0

const DEFAULT_MAX_PLAYERS: int = 30

const MAX_PLAYER_NAME_LENGTH: int = 16
const MAX_POSITION: float = 100000.0

const MODE_NONE: int = 0
const MODE_SERVER: int = 1
const MODE_CLIENT: int = 2

const RemotePlayerScript = preload(
	"res://network/remote_player.gd"
)

const BeachSpawns = preload(
	"res://world/beach_spawns.gd"
)

# ============================================================
# VARIABLES
# ============================================================

var mode: int = MODE_NONE
var players: Dictionary = {}
var remote_nodes: Dictionary = {}
var local_player = null
var world_root: Node3D = null
var welcomed_ok: bool = false
var _accum: float = 0.0
var _connecting_since: float = -1.0
var server_port: int = 0
var max_players: int = DEFAULT_MAX_PLAYERS

# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:

	multiplayer.peer_connected.connect(
		_on_peer_connected
	)

	multiplayer.peer_disconnected.connect(
		_on_peer_disconnected
	)

	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)

	multiplayer.connection_failed.connect(
		_on_connection_failed
	)

	multiplayer.server_disconnected.connect(
		_on_server_disconnected
	)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func start_server(
	port: int,
	max_clients: int
) -> bool:

	leave()

	if port < 1 or port > 65535:
		push_error("Invalid server port.")
		return false

	max_clients = clampi(
		max_clients,
		1,
		256
	)

	var peer := ENetMultiplayerPeer.new()

	var err := peer.create_server(
		port,
		max_clients
	)

	if err != OK:
		push_error(
			"Server failed on port %d. Error: %d"
			% [port, err]
		)
		return false

	multiplayer.multiplayer_peer = peer

	mode = MODE_SERVER
	server_port = port
	max_players = max_clients
	_accum = 0.0

	print(
		"SERVER STARTED | Port: %d | Max players: %d"
		% [port, max_clients]
	)

	if DisplayServer.get_name() == "headless":
		print("Running in HEADLESS mode.")

	return true


# Starts a server AND registers this same process as player id 1 so the host can play too.
func host_and_play(
	port: int,
	max_clients: int,
	spawn_pos: Vector3
) -> bool:

	leave()

	if port < 1 or port > 65535:
		push_error("Invalid server port.")
		return false

	max_clients = clampi(
		max_clients,
		1,
		256
	)

	var peer := ENetMultiplayerPeer.new()

	var err := peer.create_server(
		port,
		max_clients
	)

	if err != OK:
		push_error(
			"Server failed on port %d. Error: %d"
			% [port, err]
		)
		return false

	multiplayer.multiplayer_peer = peer

	mode = MODE_SERVER
	server_port = port
	max_players = max_clients
	_accum = 0.0

	var my_id: int = multiplayer.get_unique_id()

	players[my_id] = {
		"name": GameState.player_name,
		"pos": spawn_pos,
		"yaw": 0.0,
		"pitch": 0.0,
		"flags": 0,
		"t": _now()
	}

	print(
		"HOST STARTED | Port: %d | Max players: %d"
		% [port, max_clients]
	)

	return true


func join_server(
	address: String,
	port: int
) -> bool:

	leave()

	if address.strip_edges().is_empty():
		failed.emit("Invalid server address.")
		return false

	if port < 1 or port > 65535:
		failed.emit("Invalid server port.")
		return false

	var peer := ENetMultiplayerPeer.new()

	var err := peer.create_client(
		address.strip_edges(),
		port
	)

	if err != OK:
		failed.emit(
			"Could not create network connection."
		)
		return false

	multiplayer.multiplayer_peer = peer

	mode = MODE_CLIENT
	welcomed_ok = false
	_connecting_since = _now()
	_accum = 0.0

	print(
		"Connecting to %s:%d"
		% [address, port]
	)

	return true


func send_hello() -> void:

	if mode != MODE_CLIENT:
		return

	if multiplayer.multiplayer_peer == null:
		return

	_server_hello.rpc_id(
		1,
		GameState.player_name,
		GameState.PROTOCOL_VERSION
	)


func leave() -> void:

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	for id in remote_nodes:
		var node = remote_nodes[id]
		if is_instance_valid(node):
			node.queue_free()

	remote_nodes.clear()
	players.clear()
	local_player = null
	world_root = null
	welcomed_ok = false
	mode = MODE_NONE
	_connecting_since = -1.0
	_accum = 0.0
	server_port = 0


func _on_peer_connected(id: int) -> void:

	if mode != MODE_SERVER:
		return

	print("Peer connected: %d" % id)
	player_connected.emit(id)


func _on_connected_to_server() -> void:

	if mode != MODE_CLIENT:
		return

	_connecting_since = -1.0
	print("Connected to server.")
	connected_to_host.emit()


func _on_connection_failed() -> void:

	if mode != MODE_CLIENT:
		return

	leave()
	failed.emit("Could not connect to the server.")


func _on_server_disconnected() -> void:

	if mode != MODE_CLIENT:
		return

	leave()
	failed.emit("Connection to the server was lost.")


func _on_peer_disconnected(id: int) -> void:

	if mode != MODE_SERVER:
		return

	if players.has(id):

		var pname: String = str(players[id]["name"])

		print("Player left: %s (%d)" % [pname, id])

		players.erase(id)

		_client_player_left.rpc(id)

		if remote_nodes.has(id):
			var node = remote_nodes[id]
			if is_instance_valid(node):
				node.queue_free()
			remote_nodes.erase(id)

	player_disconnected.emit(id)


func _process(delta: float) -> void:

	if _connecting_since >= 0.0:

		if _now() - _connecting_since > CONNECT_TIMEOUT:
			leave()
			failed.emit("Connection timed out.")
			return

	if mode == MODE_NONE:
		return

	_accum += delta

	if _accum < TICK:
		return

	_accum = fmod(_accum, TICK)

	if mode == MODE_SERVER:
		_server_update_self()
		_server_broadcast()
	elif mode == MODE_CLIENT:
		if welcomed_ok:
			_client_send_state()


# Updates the host's own player entry directly (no RPC needed, it's the same process).
func _server_update_self() -> void:

	if local_player == null:
		return

	if not is_instance_valid(local_player):
		return

	var id: int = multiplayer.get_unique_id()

	if not players.has(id):
		return

	var pos: Vector3 = local_player.global_position

	if not _valid_position(pos):
		return

	var flags: int = 0

	if local_player.crouching:
		flags |= 1

	if local_player.sprinting:
		flags |= 2

	var p: Dictionary = players[id]
	p["pos"] = pos
	p["yaw"] = local_player.rotation.y
	p["pitch"] = local_player.head.rotation.x
	p["flags"] = flags
	p["t"] = _now()


func _client_send_state() -> void:

	if local_player == null:
		return

	if not is_instance_valid(local_player):
		return

	var flags: int = 0

	if local_player.crouching:
		flags |= 1

	if local_player.sprinting:
		flags |= 2

	var pos: Vector3 = local_player.global_position

	if not _valid_position(pos):
		return

	_server_state.rpc_id(
		1,
		pos,
		local_player.rotation.y,
		local_player.head.rotation.x,
		flags
	)


func _server_broadcast() -> void:

	if players.is_empty():
		return

	var ids := PackedInt32Array()
	var data := PackedFloat32Array()

	for id in players:

		var p: Dictionary = players[id]
		var pos: Vector3 = p["pos"]

		ids.append(id)

		data.append_array(
			PackedFloat32Array([
				pos.x,
				pos.y,
				pos.z,
				float(p["yaw"]),
				float(p["pitch"]),
				float(p["flags"])
			])
		)

	_client_snapshot.rpc(ids, data)

	# The host doesn't receive its own RPC, so update its own view directly.
	_apply_snapshot_local(ids, data)


func _apply_snapshot_local(
	ids: PackedInt32Array,
	data: PackedFloat32Array
) -> void:

	if mode != MODE_SERVER:
		return

	if data.size() != ids.size() * 6:
		return

	var my_id: int = multiplayer.get_unique_id()

	var now: float = _now()

	for i in range(ids.size()):

		var id: int = ids[i]

		if id == my_id:
			continue

		if not remote_nodes.has(id):
			continue

		var node = remote_nodes[id]

		if not is_instance_valid(node):
			continue

		var o: int = i * 6

		var pos := Vector3(data[o], data[o + 1], data[o + 2])

		if not _valid_position(pos):
			continue

		node.push_state(
			now,
			pos,
			data[o + 3],
			data[o + 4],
			int(data[o + 5])
		)


func _valid_position(pos: Vector3) -> bool:

	if not pos.is_finite():
		return false

	if absf(pos.x) > MAX_POSITION:
		return false

	if absf(pos.y) > MAX_POSITION:
		return false

	if absf(pos.z) > MAX_POSITION:
		return false

	return true


func add_remote_player(
	id: int,
	pname: String,
	pos: Vector3
) -> void:

	if remote_nodes.has(id):
		return

	if world_root == null:
		return

	if not is_instance_valid(world_root):
		return

	if not _valid_position(pos):
		return

	var node = RemotePlayerScript.new()

	world_root.add_child(node)

	node.setup(id, pname, pos)

	remote_nodes[id] = node


@rpc("any_peer", "call_remote", "reliable")
func _server_hello(
	player_name: String,
	version: int
) -> void:

	if mode != MODE_SERVER:
		return

	var id: int = multiplayer.get_remote_sender_id()

	if id <= 1:
		return

	if players.has(id):
		return

	if version != GameState.PROTOCOL_VERSION:

		_client_rejected.rpc_id(
			id,
			"Game version does not match the server."
		)

		multiplayer.multiplayer_peer.disconnect_peer(id, false)

		return

	if players.size() >= max_players:
		_client_rejected.rpc_id(id, "Server is full.")
		return

	var clean: String = GameState.clean_name(player_name)

	clean = clean.substr(0, MAX_PLAYER_NAME_LENGTH)

	if clean.is_empty():
		clean = "Survivor"

	var spawn: Vector3 = BeachSpawns.get_random_point()

	var others: Dictionary = {}

	for pid in players:
		others[pid] = {
			"name": players[pid]["name"],
			"pos": players[pid]["pos"]
		}

	players[id] = {
		"name": clean,
		"pos": spawn,
		"yaw": 0.0,
		"pitch": 0.0,
		"flags": 0,
		"t": _now()
	}

	_client_welcome.rpc_id(id, spawn, others)

	var my_id: int = multiplayer.get_unique_id()

	for pid in players:
		if pid != id:
			if pid == my_id:
				add_remote_player(id, clean, spawn)
			else:
				_client_player_joined.rpc_id(pid, id, clean, spawn)

	print("Player joined: %s (%d)" % [clean, id])


@rpc("any_peer", "call_remote", "unreliable")
func _server_state(
	pos: Vector3,
	yaw: float,
	pitch: float,
	flags: int
) -> void:

	if mode != MODE_SERVER:
		return

	var id: int = multiplayer.get_remote_sender_id()

	if not players.has(id):
		return

	var p: Dictionary = players[id]

	var now: float = _now()

	var dt: float = clampf(now - float(p["t"]), 0.02, 0.25)

	var old: Vector3 = p["pos"]

	var valid: bool = _valid_position(pos)

	if not is_finite(yaw):
		valid = false

	if not is_finite(pitch):
		valid = false

	if valid and old.y > -25.0:

		var horizontal: float = Vector2(
			pos.x - old.x,
			pos.z - old.z
		).length()

		var rise: float = pos.y - old.y

		if horizontal > MAX_SPEED * dt + 0.5:
			valid = false

		if rise > MAX_RISE_SPEED * dt + 0.5:
			valid = false

	if not valid:
		_client_correct.rpc_id(id, old)
		return

	p["pos"] = pos
	p["yaw"] = yaw
	p["pitch"] = clampf(pitch, -1.6, 1.6)
	p["flags"] = flags & 3
	p["t"] = now


@rpc("authority", "call_remote", "reliable")
func _client_welcome(
	spawn_pos: Vector3,
	others: Dictionary
) -> void:

	if mode != MODE_CLIENT:
		return

	if not _valid_position(spawn_pos):
		return

	welcomed_ok = true

	for id in others:
		var p: Dictionary = others[id]
		add_remote_player(int(id), str(p["name"]), p["pos"])

	welcomed.emit(spawn_pos)


@rpc("authority", "call_remote", "reliable")
func _client_rejected(text: String) -> void:

	if mode != MODE_CLIENT:
		return

	leave()
	failed.emit(text)


@rpc("authority", "call_remote", "reliable")
func _client_player_joined(
	id: int,
	pname: String,
	pos: Vector3
) -> void:

	if mode != MODE_CLIENT:
		return

	add_remote_player(id, pname, pos)


@rpc("authority", "call_remote", "reliable")
func _client_player_left(id: int) -> void:

	if mode != MODE_CLIENT:
		return

	if remote_nodes.has(id):
		var node = remote_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
		remote_nodes.erase(id)


@rpc("authority", "call_remote", "reliable")
func _client_correct(pos: Vector3) -> void:

	if mode != MODE_CLIENT:
		return

	if not _valid_position(pos):
		return

	if local_player == null:
		return

	if not is_instance_valid(local_player):
		return

	local_player.network_teleport(pos)


@rpc("authority", "call_remote", "unreliable")
func _client_snapshot(
	ids: PackedInt32Array,
	data: PackedFloat32Array
) -> void:

	if mode != MODE_CLIENT:
		return

	if data.size() != ids.size() * 6:
		return

	var my_id: int = multiplayer.get_unique_id()

	var now: float = _now()

	for i in range(ids.size()):

		var id: int = ids[i]

		if id == my_id:
			continue

		if not remote_nodes.has(id):
			continue

		var node = remote_nodes[id]

		if not is_instance_valid(node):
			continue

		var o: int = i * 6

		var pos := Vector3(data[o], data[o + 1], data[o + 2])

		if not _valid_position(pos):
			continue

		node.push_state(
			now,
			pos,
			data[o + 3],
			data[o + 4],
			int(data[o + 5])
		)
