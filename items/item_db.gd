extends Node

# Item IDs
const WOOD := "wood"
const STONE := "stone"
const ROCK := "rock"
const AXE := "axe"
const PICKAXE := "pickaxe"
const HAMMER := "hammer"
const WOOD_SPEAR := "wood_spear"
const STONE_ARROW := "stone_arrow"
const CAMPFIRE := "campfire"
const BUILDING_PLAN := "building_plan"
const CANDLE := "candle"
const CLOTH := "cloth"

# Item database: display names and stack limits
const ITEMS := {
	WOOD: {"name": "Wood", "max_stack": 1000},
	STONE: {"name": "Stone", "max_stack": 1000},
	ROCK: {"name": "Rock", "max_stack": 1},
	AXE: {"name": "Axe", "max_stack": 1},
	PICKAXE: {"name": "Pickaxe", "max_stack": 1},
	HAMMER: {"name": "Hammer", "max_stack": 1},
	WOOD_SPEAR: {"name": "Wood Spear", "max_stack": 1},
	STONE_ARROW: {"name": "Stone Arrow", "max_stack": 1000},
	CAMPFIRE: {"name": "Campfire", "max_stack": 1},
	BUILDING_PLAN: {"name": "Building Plan", "max_stack": 1},
	CANDLE: {"name": "Candle", "max_stack": 1},
	CLOTH: {"name": "Cloth", "max_stack": 1000},
}

# Returns max stack size for an item
static func get_max_stack(item_id: String) -> int:
	if ITEMS.has(item_id):
		return int(ITEMS[item_id].get("max_stack", 1000))
	return 1000

# Returns display name
static func get_item_name(item_id: String) -> String:
	if ITEMS.has(item_id):
		return str(ITEMS[item_id].get("name", item_id))
	return item_id
