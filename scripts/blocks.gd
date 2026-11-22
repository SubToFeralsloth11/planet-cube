extends Node
## Block, item and recipe registry (autoload "B").

# --- blocks (0..99) ---
const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4
const SAND := 5
const SANDSTONE := 6
const SNOW := 7
const ICE := 8
const LOG := 9
const LEAVES := 10
const PLANKS := 11
const BIRCH_LOG := 12
const BIRCH_LEAVES := 13
const SPRUCE_LOG := 14
const SPRUCE_LEAVES := 15
const CACTUS := 16
const COAL_ORE := 17
const IRON_ORE := 18
const GOLD_ORE := 19
const DIAMOND_ORE := 20
const STARCORE_ORE := 21
const CORE_ROCK := 22
const BASALT := 23
const OBSIDIAN := 24
const WATER := 25
const LAVA := 26
const GRAVEL := 27
const CRAFTING_TABLE := 28
const FURNACE := 29
const TORCH := 30
const GLASS := 31
const STONE_BRICKS := 32
const BRICKS := 33
const IRON_BLOCK := 34
const GOLD_BLOCK := 35
const DIAMOND_BLOCK := 36
const LAMP := 37
const TNT := 38
const WOOL_WHITE := 39
const WOOL_RED := 40
const WOOL_ORANGE := 41
const WOOL_YELLOW := 42
const WOOL_GREEN := 43
const WOOL_BLUE := 44
const WOOL_PURPLE := 45
const WOOL_BLACK := 46
const TALL_GRASS := 47
const FLOWER_RED := 48
const FLOWER_YELLOW := 49
const DEAD_BUSH := 50
const ASH := 51
const MAGMA := 52
const SPRUCE_PLANKS := 53
const BIRCH_PLANKS := 54
const SMOOTH_STONE := 55
const CHEST := 56
const FARMLAND := 57
const WHEAT_0 := 58  # four growth stages, 58..61
const WHEAT_3 := 61
const ASH_PORTAL := 62
const EMBER_CORE := 63
const EMBERITE_ORE := 64

# --- items (100+) ---
const STICK := 100
const COAL := 101
const IRON_INGOT := 102
const GOLD_INGOT := 103
const DIAMOND := 104
const STARCORE := 105
const RAW_MEAT := 106
const COOKED_MEAT := 107
const GUNPOWDER := 108
const APPLE := 109
const WOOD_PICK := 110
const STONE_PICK := 111
const IRON_PICK := 112
const DIAMOND_PICK := 113
const WOOD_AXE := 114
const STONE_AXE := 115
const IRON_AXE := 116
const DIAMOND_AXE := 117
const WOOD_SHOVEL := 118
const STONE_SHOVEL := 119
const IRON_SHOVEL := 120
const DIAMOND_SHOVEL := 121
const WOOD_SWORD := 122
const STONE_SWORD := 123
const IRON_SWORD := 124
const DIAMOND_SWORD := 125
const ROCKET_HULL := 130
const ROCKET_ENGINE := 131
const FUEL_CELL := 132
const NAV_CORE := 133
const ROCKET := 134
const BUCKET := 135
const WATER_BUCKET := 136
const LAVA_BUCKET := 137
const SHIELD := 138
const IRON_HELMET := 139
const IRON_CHESTPLATE := 140
const IRON_LEGGINGS := 141
const IRON_BOOTS := 142
const DIAMOND_HELMET := 143
const DIAMOND_CHESTPLATE := 144
const DIAMOND_LEGGINGS := 145
const DIAMOND_BOOTS := 146
const SEEDS := 147
const WHEAT := 148
const BREAD := 149
const HOE := 150
const BOW := 151
const ARROW := 152
const FLINT := 153
const FLINT_AND_STEEL := 154
const EMBERITE := 155

## Armor piece names by slot index (0 helmet .. 3 boots) and points per material (iron, diamond).
const ARMOR_PARTS := ["Helmet", "Chestplate", "Leggings", "Boots"]
const ARMOR_POINTS := [[2, 6, 5, 2], [3, 8, 6, 3]]

# ingredient groups (negative ids)
const G_PLANKS := -1
const G_LOG := -2

# render types
const R_CUBE := 0
const R_CUTOUT := 1
const R_WATER := 2
const R_CROSS := 3
const R_LAVA := 4
const R_TORCH := 5

const TIER_NAMES := ["Hand", "Wood", "Stone", "Iron", "Diamond"]
const MAT_COLORS := [Color(0.62, 0.45, 0.25), Color(0.55, 0.55, 0.55), Color(0.86, 0.86, 0.88), Color(0.35, 0.95, 0.92)]
const SMELT_TIME := 2.5  # seconds per item in a furnace

var info := {}
var SOLID := PackedByteArray()
var OPAQUE := PackedByteArray()
var OCCLUDE := PackedByteArray()  # blocks sky & casts AO (opaque or leaves)
var RENDER := PackedByteArray()
var TARGET := PackedByteArray()
var TEX_TOP := PackedInt32Array()
var TEX_SIDE := PackedInt32Array()
var TEX_BOT := PackedInt32Array()
var EMIT := PackedFloat32Array()
var LIGHT := PackedFloat32Array()
var texture_names: Array[String] = []
var tex_index := {}
var recipes: Array = []
var block_list: Array[int] = []
var item_list: Array[int] = []
var smelts := {}  # input id -> [output id, count], from the single-ingredient furnace recipes
var fuels := {}  # item id -> burn seconds


func _init() -> void:
	SOLID.resize(256)
	OPAQUE.resize(256)
	OCCLUDE.resize(256)
	RENDER.resize(256)
	TARGET.resize(256)
	TEX_TOP.resize(256)
	TEX_SIDE.resize(256)
	TEX_BOT.resize(256)
	EMIT.resize(256)
	LIGHT.resize(256)
	_register_blocks()
	_register_items()
	_register_recipes()
	for r in recipes:
		if r["st"] == "furnace" and r["in"].size() == 1:
			smelts[r["in"].keys()[0]] = [r["out"], r["n"]]
	fuels[COAL] = 20.0
	fuels[STICK] = 1.25
	for id in group_members(G_LOG):
		fuels[id] = 7.5
	for id in group_members(G_PLANKS):
		fuels[id] = 3.75


func _tex(n: String) -> int:
	if not tex_index.has(n):
		tex_index[n] = texture_names.size()
		texture_names.append(n)
	return tex_index[n]


func _blk(id: int, nm: String, tex, hard: float, tool := "", tier := 0, ex := {}) -> void:
	var t: Array = tex if tex is Array else [tex, tex, tex]
	if t.size() == 2:
		t = [t[0], t[1], t[0]]
	var render: int = ex.get("render", R_CUBE)
	var opaque: bool = ex.get("opaque", render == R_CUBE or render == R_LAVA)
	info[id] = {
		"name": nm, "block": true, "hard": hard, "tool": tool, "tier": tier,
		"drop": ex.get("drop", id), "drop_n": ex.get("drop_n", 1),
		"sound": ex.get("sound", "stone"), "stack": 64,
	}
	SOLID[id] = 1 if ex.get("solid", true) else 0
	OPAQUE[id] = 1 if opaque else 0
	OCCLUDE[id] = 1 if (opaque or ex.get("occlude", false)) else 0
	RENDER[id] = render
	TARGET[id] = 0 if (id == WATER or id == LAVA) else 1
	TEX_TOP[id] = _tex(t[0])
	TEX_SIDE[id] = _tex(t[1])
	TEX_BOT[id] = _tex(t[2])
	EMIT[id] = ex.get("emit", 0.0)
	LIGHT[id] = ex.get("light", 0.0)
	if id != AIR and id != WATER and id != LAVA:
		block_list.append(id)


func _register_blocks() -> void:
	info[AIR] = {"name": "Air", "block": true, "hard": 0.0, "tool": "", "tier": 0, "drop": 0, "drop_n": 0, "sound": "", "stack": 64}
	_blk(GRASS, "Grass Block", ["grass_top", "grass_side", "dirt"], 0.6, "shovel", 0, {"drop": DIRT, "sound": "grass"})
	_blk(DIRT, "Dirt", "dirt", 0.5, "shovel", 0, {"sound": "dirt"})
	_blk(STONE, "Stone", "stone", 1.5, "pick", 1, {"drop": COBBLE})
	_blk(COBBLE, "Cobblestone", "cobble", 2.0, "pick", 1)
	_blk(SAND, "Sand", "sand", 0.5, "shovel", 0, {"sound": "sand"})
	_blk(SANDSTONE, "Sandstone", ["sandstone_top", "sandstone"], 0.8, "pick", 1)
	_blk(SNOW, "Snowy Grass", ["snow", "snow_side", "dirt"], 0.6, "shovel", 0, {"drop": DIRT, "sound": "sand"})
	_blk(ICE, "Ice", "ice", 0.5, "pick", 0, {"sound": "glass"})
	_blk(LOG, "Oak Log", ["log_top", "log"], 2.0, "axe", 0, {"sound": "wood"})
	_blk(LEAVES, "Oak Leaves", "leaves", 0.2, "", 0, {"render": R_CUTOUT, "occlude": true, "drop": 0, "sound": "grass"})
	_blk(PLANKS, "Oak Planks", "planks", 2.0, "axe", 0, {"sound": "wood"})
	_blk(BIRCH_LOG, "Birch Log", ["birch_top", "birch"], 2.0, "axe", 0, {"sound": "wood"})
	_blk(BIRCH_LEAVES, "Birch Leaves", "birch_leaves", 0.2, "", 0, {"render": R_CUTOUT, "occlude": true, "drop": 0, "sound": "grass"})
	_blk(SPRUCE_LOG, "Spruce Log", ["spruce_top", "spruce"], 2.0, "axe", 0, {"sound": "wood"})
	_blk(SPRUCE_LEAVES, "Spruce Leaves", "spruce_leaves", 0.2, "", 0, {"render": R_CUTOUT, "occlude": true, "drop": 0, "sound": "grass"})
	_blk(CACTUS, "Cactus", ["cactus_top", "cactus"], 0.4, "", 0, {"sound": "grass"})
	_blk(COAL_ORE, "Coal Ore", "coal_ore", 3.0, "pick", 1, {"drop": COAL})
	_blk(IRON_ORE, "Iron Ore", "iron_ore", 3.0, "pick", 2)
	_blk(GOLD_ORE, "Gold Ore", "gold_ore", 3.0, "pick", 3)
	_blk(DIAMOND_ORE, "Diamond Ore", "diamond_ore", 3.5, "pick", 3, {"drop": DIAMOND})
	_blk(STARCORE_ORE, "Starcore Ore", "starcore_ore", 4.0, "pick", 4, {"drop": STARCORE, "emit": 0.9})
	_blk(CORE_ROCK, "Core Rock", "core_rock", 3.5, "pick", 4, {"emit": 0.35})
	_blk(BASALT, "Basalt", ["basalt_top", "basalt"], 1.5, "pick", 1)
	_blk(OBSIDIAN, "Obsidian", "obsidian", 12.0, "pick", 4)
	_blk(WATER, "Water", "water", -1.0, "", 0, {"render": R_WATER, "solid": false, "drop": 0})
	_blk(LAVA, "Lava", "lava", -1.0, "", 0, {"render": R_LAVA, "solid": false, "opaque": false, "emit": 1.6, "drop": 0})
	_blk(GRAVEL, "Gravel", "gravel", 0.6, "shovel", 0, {"sound": "sand"})
	_blk(CRAFTING_TABLE, "Crafting Table", ["table_top", "table_side", "planks"], 2.0, "axe", 0, {"sound": "wood"})
	_blk(FURNACE, "Furnace", ["furnace_top", "furnace_front", "furnace_top"], 3.0, "pick", 1)
	_blk(TORCH, "Torch", "torch", 0.05, "", 0, {"render": R_TORCH, "solid": false, "light": 1.0, "emit": 1.2, "sound": "wood"})
	_blk(GLASS, "Glass", "glass", 0.4, "", 0, {"render": R_CUTOUT, "sound": "glass"})
	_blk(STONE_BRICKS, "Stone Bricks", "stone_bricks", 2.0, "pick", 1)
	_blk(BRICKS, "Bricks", "bricks", 2.0, "pick", 1)
	_blk(IRON_BLOCK, "Iron Block", "iron_block", 4.0, "pick", 2)
	_blk(GOLD_BLOCK, "Gold Block", "gold_block", 4.0, "pick", 2)
	_blk(DIAMOND_BLOCK, "Diamond Block", "diamond_block", 4.0, "pick", 2)
	_blk(LAMP, "Glow Lamp", "lamp", 0.4, "", 0, {"light": 1.4, "emit": 1.0, "sound": "glass"})
	_blk(TNT, "TNT", ["tnt_top", "tnt_side", "tnt_bottom"], 0.1, "", 0, {"sound": "grass"})
	var wools := [["White", "wool_white"], ["Red", "wool_red"], ["Orange", "wool_orange"], ["Yellow", "wool_yellow"],
		["Green", "wool_green"], ["Blue", "wool_blue"], ["Purple", "wool_purple"], ["Black", "wool_black"]]
	for k in wools.size():
		_blk(WOOL_WHITE + k, "%s Wool" % wools[k][0], wools[k][1], 0.8, "", 0, {"sound": "grass"})
	_blk(TALL_GRASS, "Tall Grass", "tall_grass", 0.0, "", 0, {"render": R_CROSS, "solid": false, "drop": SEEDS, "sound": "grass"})
	_blk(FLOWER_RED, "Red Flower", "flower_red", 0.0, "", 0, {"render": R_CROSS, "solid": false, "sound": "grass"})
	_blk(FLOWER_YELLOW, "Yellow Flower", "flower_yellow", 0.0, "", 0, {"render": R_CROSS, "solid": false, "sound": "grass"})
	_blk(DEAD_BUSH, "Dead Bush", "dead_bush", 0.0, "", 0, {"render": R_CROSS, "solid": false, "drop": STICK, "sound": "grass"})
	_blk(ASH, "Ash", "ash", 0.5, "shovel", 0, {"sound": "sand"})
	_blk(MAGMA, "Magma", "magma", 1.5, "pick", 1, {"emit": 0.8})
	_blk(SPRUCE_PLANKS, "Spruce Planks", "spruce_planks", 2.0, "axe", 0, {"sound": "wood"})
	_blk(BIRCH_PLANKS, "Birch Planks", "birch_planks", 2.0, "axe", 0, {"sound": "wood"})
	_blk(SMOOTH_STONE, "Smooth Stone", "smooth_stone", 2.0, "pick", 1)
	_blk(CHEST, "Chest", ["chest_top", "chest_front", "chest_top"], 1.2, "axe", 0, {"sound": "wood"})
	_blk(FARMLAND, "Farmland", ["farmland", "dirt"], 0.5, "shovel", 0, {"drop": DIRT, "sound": "dirt"})
	for s in 4:
		_blk(WHEAT_0 + s, "Wheat Crop", "wheat_%d" % s, 0.0, "", 0, {"render": R_CROSS, "solid": false, "drop": WHEAT if s == 3 else SEEDS, "sound": "grass"})
	_blk(ASH_PORTAL, "Ash Portal", ["portal_top", "portal_side"], 6.0, "pick", 2, {"emit": 0.7, "light": 0.8})
	_blk(EMBER_CORE, "Ember Core", "ember_core", 4.0, "pick", 2, {"emit": 0.6})
	_blk(EMBERITE_ORE, "Emberite Ore", "emberite_ore", 3.5, "pick", 3, {"emit": 0.4})


func _item(id: int, nm: String, ex := {}) -> void:
	info[id] = {
		"name": nm, "block": false, "stack": ex.get("stack", 64), "tool": ex.get("tool", ""),
		"tier": ex.get("tier", 0), "speed": ex.get("speed", 1.0), "dmg": ex.get("dmg", 1.0),
		"food": ex.get("food", 0), "desc": ex.get("desc", ""), "armor": ex.get("armor", 0), "slot": ex.get("slot", -1),
	}
	item_list.append(id)


func _register_items() -> void:
	_item(STICK, "Stick")
	_item(COAL, "Coal", {"desc": "Fuel. Makes torches."})
	_item(IRON_INGOT, "Iron Ingot")
	_item(GOLD_INGOT, "Gold Ingot")
	_item(DIAMOND, "Diamond")
	_item(STARCORE, "Starcore Crystal", {"desc": "Pulses with the planet's heartbeat."})
	_item(RAW_MEAT, "Raw Meat", {"food": 3})
	_item(COOKED_MEAT, "Steak", {"food": 8})
	_item(GUNPOWDER, "Gunpowder")
	_item(APPLE, "Apple", {"food": 4})
	var mats := ["Wooden", "Stone", "Iron", "Diamond"]
	var speeds := [2.5, 4.5, 7.0, 10.0]
	for t in 4:
		_item(WOOD_PICK + t, "%s Pickaxe" % mats[t], {"stack": 1, "tool": "pick", "tier": t + 1, "speed": speeds[t], "dmg": 2.0 + t})
		_item(WOOD_AXE + t, "%s Axe" % mats[t], {"stack": 1, "tool": "axe", "tier": t + 1, "speed": speeds[t], "dmg": 3.0 + t})
		_item(WOOD_SHOVEL + t, "%s Shovel" % mats[t], {"stack": 1, "tool": "shovel", "tier": t + 1, "speed": speeds[t], "dmg": 1.5 + t})
		_item(WOOD_SWORD + t, "%s Sword" % mats[t], {"stack": 1, "tool": "sword", "tier": t + 1, "speed": 1.5, "dmg": [4.0, 5.0, 6.5, 8.5][t]})
	_item(ROCKET_HULL, "Rocket Hull", {"stack": 1})
	_item(ROCKET_ENGINE, "Rocket Engine", {"stack": 1})
	_item(FUEL_CELL, "Fuel Cell", {"stack": 8})
	_item(NAV_CORE, "Navigation Core", {"stack": 1})
	_item(ROCKET, "Rocket", {"stack": 1, "desc": "Place on open ground, then right-click it."})
	_item(BUCKET, "Bucket", {"stack": 16, "desc": "Right-click a water or lava source to scoop it up."})
	_item(WATER_BUCKET, "Water Bucket", {"stack": 1, "desc": "Right-click to pour. Saves you from a long fall."})
	_item(LAVA_BUCKET, "Lava Bucket", {"stack": 1, "desc": "Right-click to pour. Careful!"})
	_item(SHIELD, "Shield", {"stack": 1, "desc": "Hold Right Mouse to block hits from the front. F: move to offhand."})
	for m in 2:
		for k in 4:
			_item(IRON_HELMET + m * 4 + k, "%s %s" % [["Iron", "Diamond"][m], ARMOR_PARTS[k]],
				{"stack": 1, "armor": ARMOR_POINTS[m][k], "slot": k})
	_item(SEEDS, "Wheat Seeds", {"desc": "Right-click farmland to plant."})
	_item(WHEAT, "Wheat")
	_item(BREAD, "Bread", {"food": 6})
	_item(HOE, "Hoe", {"stack": 1, "desc": "Right-click grass or dirt to till farmland."})
	_item(BOW, "Bow", {"stack": 1, "desc": "Hold Right Mouse to draw, release to fire. Uses arrows."})
	_item(ARROW, "Arrow")
	_item(FLINT, "Flint")
	_item(FLINT_AND_STEEL, "Flint and Steel", {"stack": 1, "desc": "Lights TNT. Light an Ash Portal to travel between worlds."})
	_item(EMBERITE, "Emberite", {"desc": "Found only in the Ash Lands."})


func _rec(out: int, n: int, ingredients: Dictionary, station := "") -> void:
	recipes.append({"out": out, "n": n, "in": ingredients, "st": station})


func _register_recipes() -> void:
	_rec(PLANKS, 4, {LOG: 1})
	_rec(SPRUCE_PLANKS, 4, {SPRUCE_LOG: 1})
	_rec(BIRCH_PLANKS, 4, {BIRCH_LOG: 1})
	_rec(STICK, 4, {G_PLANKS: 2})
	_rec(CRAFTING_TABLE, 1, {G_PLANKS: 4})
	_rec(TORCH, 4, {COAL: 1, STICK: 1})
	var heads := [G_PLANKS, COBBLE, IRON_INGOT, DIAMOND]
	for t in 4:
		var h: int = heads[t]
		_rec(WOOD_PICK + t, 1, {h: 3, STICK: 2}, "table")
		_rec(WOOD_AXE + t, 1, {h: 3, STICK: 2}, "table")
		_rec(WOOD_SHOVEL + t, 1, {h: 1, STICK: 2}, "table")
		_rec(WOOD_SWORD + t, 1, {h: 2, STICK: 1}, "table")
	_rec(FURNACE, 1, {COBBLE: 8}, "table")
	_rec(IRON_INGOT, 1, {IRON_ORE: 1}, "furnace")
	_rec(GOLD_INGOT, 1, {GOLD_ORE: 1}, "furnace")
	_rec(GLASS, 1, {SAND: 1}, "furnace")
	_rec(SMOOTH_STONE, 1, {COBBLE: 1}, "furnace")
	_rec(COOKED_MEAT, 1, {RAW_MEAT: 1}, "furnace")
	_rec(BRICKS, 4, {GRAVEL: 2, SAND: 2}, "table")
	_rec(STONE_BRICKS, 4, {SMOOTH_STONE: 4}, "table")
	_rec(SANDSTONE, 2, {SAND: 4}, "table")
	_rec(IRON_BLOCK, 1, {IRON_INGOT: 9}, "table")
	_rec(GOLD_BLOCK, 1, {GOLD_INGOT: 9}, "table")
	_rec(DIAMOND_BLOCK, 1, {DIAMOND: 9}, "table")
	_rec(LAMP, 2, {GLASS: 2, TORCH: 2}, "table")
	_rec(TNT, 1, {GUNPOWDER: 3, SAND: 4}, "table")
	_rec(WOOL_RED, 1, {WOOL_WHITE: 1, FLOWER_RED: 1})
	_rec(WOOL_YELLOW, 1, {WOOL_WHITE: 1, FLOWER_YELLOW: 1})
	_rec(WOOL_ORANGE, 2, {WOOL_WHITE: 2, FLOWER_RED: 1, FLOWER_YELLOW: 1})
	_rec(WOOL_GREEN, 1, {WOOL_WHITE: 1, CACTUS: 1})
	_rec(WOOL_BLUE, 1, {WOOL_WHITE: 1, ICE: 1})
	_rec(WOOL_PURPLE, 2, {WOOL_WHITE: 2, FLOWER_RED: 1, ICE: 1})
	_rec(WOOL_BLACK, 1, {WOOL_WHITE: 1, COAL: 1})
	_rec(ROCKET_HULL, 1, {IRON_INGOT: 8, GLASS: 2}, "table")
	_rec(ROCKET_ENGINE, 1, {IRON_INGOT: 3, GOLD_INGOT: 4, FURNACE: 1, EMBER_CORE: 1}, "table")
	_rec(FUEL_CELL, 1, {COAL: 6, STARCORE: 1}, "table")
	_rec(NAV_CORE, 1, {DIAMOND: 2, GOLD_INGOT: 2, STARCORE: 1}, "table")
	_rec(ROCKET, 1, {ROCKET_HULL: 1, ROCKET_ENGINE: 1, FUEL_CELL: 3, NAV_CORE: 1}, "table")
	_rec(CHEST, 1, {G_PLANKS: 8}, "table")
	_rec(BUCKET, 1, {IRON_INGOT: 3}, "table")
	_rec(SHIELD, 1, {G_PLANKS: 6, IRON_INGOT: 1}, "table")
	var armor_cost := [5, 8, 7, 4]
	for k in 4:
		_rec(IRON_HELMET + k, 1, {IRON_INGOT: armor_cost[k]}, "table")
		_rec(DIAMOND_HELMET + k, 1, {DIAMOND: armor_cost[k]}, "table")
	_rec(HOE, 1, {G_PLANKS: 2, STICK: 2}, "table")
	_rec(BREAD, 1, {WHEAT: 3})
	_rec(FLINT, 1, {GRAVEL: 3})
	_rec(FLINT_AND_STEEL, 1, {FLINT: 1, IRON_INGOT: 1})
	_rec(ARROW, 4, {FLINT: 1, STICK: 1, WHEAT: 1})
	_rec(BOW, 1, {STICK: 3, WOOL_WHITE: 3}, "table")
	_rec(ASH_PORTAL, 1, {OBSIDIAN: 4, DIAMOND: 1}, "table")
	_rec(EMBERITE, 1, {EMBERITE_ORE: 1}, "furnace")
	_rec(EMBER_CORE, 1, {EMBERITE: 4, STARCORE: 1}, "table")


func is_block(id: int) -> bool:
	return id > 0 and id < 100 and info.has(id)


func item_name(id: int) -> String:
	if id == G_PLANKS:
		return "Any Planks"
	if id == G_LOG:
		return "Any Log"
	return info[id]["name"] if info.has(id) else "?"


func stack_max(id: int) -> int:
	return info[id]["stack"] if info.has(id) else 64


func group_members(id: int) -> Array:
	if id == G_PLANKS:
		return [PLANKS, SPRUCE_PLANKS, BIRCH_PLANKS]
	if id == G_LOG:
		return [LOG, SPRUCE_LOG, BIRCH_LOG]
	return [id]


func tool_of(id: int) -> Dictionary:
	if id >= 100 and info.has(id) and info[id]["tool"] != "":
		return info[id]
	return {}


## Armor slot (0 helmet .. 3 boots) for an armor item, else -1.
func armor_slot(id: int) -> int:
	return info[id]["slot"] if id >= 100 and info.has(id) else -1


func armor_points(id: int) -> int:
	return info[id]["armor"] if id >= 100 and info.has(id) else 0
