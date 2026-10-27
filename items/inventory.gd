extends Node

# Slot counts (6 hotbar + 24 main)
const HOTBAR_SLOTS := 6
const MAIN_SLOTS := 24
const TOTAL_SLOTS := 30

# Server storage: peer_id -> Array of slot dicts
static var data := {}

# Initializes slots and gives starting rock + candle
static func init_player(id: int) -> void:
	if data.has(id):
		return
	var slots: Array = []
	for i in range(TOTAL_SLOTS):
		slots.append({"id": "", "count": 0})
	slots[0] = {"id": ItemDB.ROCK, "count": 1}
	slots[1] = {"id": ItemDB.CANDLE, "count": 1}
	data[id] = slots

# Cleans up player data on disconnect
static func remove_player(id: int) -> void:
	data.erase(id)

# Adds items with stacking, returns leftover count
static func add_item(id: int, item_id: String, amount: int) -> int:
	if not data.has(id):
		init_player(id)
	var slots_arr: Array = data[id]
	var max_stack: int = ItemDB.get_max_stack(item_id)
	var rem_amount: int = amount
	
	for i in range(TOTAL_SLOTS):
		var slot: Dictionary = slots_arr[i]
		if slot["id"] == item_id and slot["count"] < max_stack:
			var can_take: int = max_stack - slot["count"]
			var take: int = mini(rem_amount, can_take)
			slot["count"] += take
			rem_amount -= take
			if rem_amount <= 0:
				return 0
				
	for i in range(TOTAL_SLOTS):
		var slot: Dictionary = slots_arr[i]
		if slot["id"] == "" or slot["count"] <= 0:
			var take: int = mini(rem_amount, max_stack)
			slot["id"] = item_id
			slot["count"] = take
			rem_amount -= take
			if rem_amount <= 0:
				return 0
				
	return rem_amount

# Removes items, returns true if fully satisfied
static func remove_item(id: int, item_id: String, amount: int) -> bool:
	if count_item(id, item_id) < amount:
		return false
	var rem_amount: int = amount
	var slots_arr: Array = data[id]
	for i in range(TOTAL_SLOTS - 1, -1, -1):
		var slot: Dictionary = slots_arr[i]
		if slot["id"] == item_id:
			if slot["count"] <= rem_amount:
				rem_amount -= slot["count"]
				slot["id"] = ""
				slot["count"] = 0
			else:
				slot["count"] -= rem_amount
				rem_amount = 0
			if rem_amount <= 0:
				break
	return true

# Moves, stacks, or swaps items between two slots with split amount support
static func move_slot(id: int, from_idx: int, to_idx: int, split_amount: int = -1) -> bool:
	if not data.has(id):
		init_player(id)
	if from_idx < 0 or from_idx >= TOTAL_SLOTS or to_idx < 0 or to_idx >= TOTAL_SLOTS:
		return false
	if from_idx == to_idx:
		return false

	var slots_arr: Array = data[id]
	var from_slot: Dictionary = slots_arr[from_idx]
	var to_slot: Dictionary = slots_arr[to_idx]

	if from_slot.get("id", "") == "" or int(from_slot.get("count", 0)) <= 0:
		return false

	var from_id: String = str(from_slot["id"])
	var from_count: int = int(from_slot["count"])
	var to_id: String = str(to_slot.get("id", ""))
	var to_count: int = int(to_slot.get("count", 0))

	var move_count: int = from_count
	if split_amount > 0 and split_amount < from_count:
		move_count = split_amount

	# 1. Target slot is empty
	if to_id == "" or to_count <= 0:
		slots_arr[to_idx] = {"id": from_id, "count": move_count}
		if move_count >= from_count:
			slots_arr[from_idx] = {"id": "", "count": 0}
		else:
			slots_arr[from_idx]["count"] = from_count - move_count
		return true

	# 2. Target has the same item: stack
	if from_id == to_id:
		var max_stack: int = ItemDB.get_max_stack(from_id)
		var space: int = max_stack - to_count
		if space > 0:
			var transfer: int = mini(move_count, space)
			slots_arr[to_idx]["count"] = to_count + transfer
			slots_arr[from_idx]["count"] = from_count - transfer
			if int(slots_arr[from_idx]["count"]) <= 0:
				slots_arr[from_idx] = {"id": "", "count": 0}
			return true
		return false

	# 3. Target has different item (swap)
	if move_count == from_count:
		var temp: Dictionary = from_slot.duplicate(true)
		slots_arr[from_idx] = to_slot.duplicate(true)
		slots_arr[to_idx] = temp
		return true

	return false

# Total amount of item in inventory
static func count_item(id: int, item_id: String) -> int:
	if not data.has(id):
		return 0
	var total: int = 0
	var slots_arr: Array = data[id]
	for i in range(TOTAL_SLOTS):
		if slots_arr[i]["id"] == item_id:
			total += int(slots_arr[i]["count"])
	return total

# Returns raw slot array
static func can_add(id: int, item_id: String, amount: int) -> bool:
	if not data.has(id):
		init_player(id)
	var slots_arr: Array = data[id]
	var max_stack: int = ItemDB.get_max_stack(item_id)
	var rem: int = amount
	
	for i in range(TOTAL_SLOTS):
		var slot: Dictionary = slots_arr[i]
		if slot["id"] == item_id and slot["count"] < max_stack:
			rem -= (max_stack - slot["count"])
			if rem <= 0:
				return true
	for i in range(TOTAL_SLOTS):
		var slot: Dictionary = slots_arr[i]
		if slot["id"] == "" or slot["count"] <= 0:
			rem -= max_stack
			if rem <= 0:
				return true
	return false
static func get_slots(id: int) -> Array:
	if not data.has(id):
		init_player(id)
	return data[id]
