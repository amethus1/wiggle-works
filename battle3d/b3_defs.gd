class_name B3Defs
## All the data for 3D Battle: teams, personalities, units, weapons,
## explosives, hazards, structures and maps. What it shares with the 2D game
## (the teams' order and names, the personalities, fighter names, stickers)
## lives in Catalog, and is read from there.

# physics layers (bit values)
const L_TERRAIN := 1
const L_STRUCT := 2
const L_UNIT := 4
const L_RAGDOLL := 8
const L_PROP := 16
const L_SCENERY := 32

const BOUNDS := 186.0         # units/props beyond this (x or z) are removed (maps are ±192 m, B3World.HALF)
const MAX_CORPSES := 140      # oldest knocked-out ragdolls are tidied away
const MAX_CHUNKS := 220       # flying structure pieces and debris

# The teams' order and names are the 2D game's (Catalog: the one home of what
# both share); 3D has its own brighter colours, and an icon each.
const TEAM_ORDER := Catalog.TEAM_ORDER
const TEAM := {
	"red": {"name": Catalog.TEAMS.red.name, "col": Color("ff4646"), "icon": "🔴"},
	"blue": {"name": Catalog.TEAMS.blue.name, "col": Color("3d86ff"), "icon": "🔵"},
	"green": {"name": Catalog.TEAMS.green.name, "col": Color("3fcf4e"), "icon": "🟢"},
	"yellow": {"name": Catalog.TEAMS.yellow.name, "col": Color("ffcc1a"), "icon": "🟡"},
	"wild": {"name": Catalog.TEAMS.wild.name, "col": Color("a37a4c"), "icon": "🐾"},
}

# The same six personalities as the 2D game (their order, names and icons are
# Catalog's), with ✨ Auto first and 3D's own tips.
const PERS_ORDER := ["auto"] + Catalog.PERS_ORDER
const PERS := {
	"auto": {"name": "Auto", "icon": "✨", "tip": "Each one does what it's best at"},
	"attack": {"name": Catalog.PERS.attack.name, "icon": Catalog.PERS.attack.emoji, "tip": "Charges at the nearest enemy"},
	"defend": {"name": Catalog.PERS.defend.name, "icon": Catalog.PERS.defend.emoji, "tip": "Guards the spot where you put it"},
	"ranged": {"name": Catalog.PERS.ranged.name, "icon": Catalog.PERS.ranged.emoji, "tip": "Keeps its distance and shoots"},
	"berserk": {"name": Catalog.PERS.berserk.name, "icon": Catalog.PERS.berserk.emoji, "tip": "Super fast and wild! Always charges in"},
	"coward": {"name": Catalog.PERS.coward.name, "icon": Catalog.PERS.coward.emoji, "tip": "Runs away when it gets hurt"},
	"peaceful": {"name": Catalog.PERS.peaceful.name, "icon": Catalog.PERS.peaceful.emoji, "tip": "Wanders around and never fights"},
}

const CATS := [
	{"id": "people", "name": "People", "icon": "🧍"},
	{"id": "animals", "name": "Animals", "icon": "🐾"},
	{"id": "dinos", "name": "Dinos", "icon": "🦖"},
	{"id": "vehicles", "name": "Vehicles", "icon": "🚜"},
	{"id": "history", "name": "History", "icon": "📜"},
	{"id": "booms", "name": "Booms", "icon": "💣"},
	{"id": "hazards", "name": "Hazards", "icon": "🌋"},
	{"id": "build", "name": "Build", "icon": "🧱"},
]

## body: human | quad | biped | bird | robot | ape | dragon | vehicle.
## stab = how hard it is to knock over.  voice: sound when it spots an enemy.
## size scales the whole model (for vehicles it only sets how far apart a
## dragged line of them is).  special: has extra moves (see B3Special).
## Vehicles (see B3Vehicle): turn = turning speed, shot/melee/fire = how much
## of that kind of damage gets through the armour (blast > 1: explosives do
## extra), boom = wreck blast radius.
## The kinds the 2D game has too take their names from it (Catalog.FIGHTERS).
const UNITS := {
	"stick": {"name": Catalog.FIGHTERS.stick.name, "icon": "🧍", "cat": "people", "body": "human", "style": "stick",
		"hp": 60, "speed": 4.6, "armor": 0.0, "size": 1.0, "weapon": "fists", "pers": "attack", "mass": 55.0, "stab": 0.9},
	"soldier": {"name": Catalog.FIGHTERS.soldier.name, "icon": "🪖", "cat": "people", "body": "human", "style": "soldier",
		"hp": 100, "speed": 4.0, "armor": 0.05, "size": 1.0, "weapon": "rifle", "pers": "ranged", "mass": 75.0, "stab": 1.0},
	"knight": {"name": Catalog.FIGHTERS.knight.name, "icon": "🛡️", "cat": "people", "body": "human", "style": "knight",
		"hp": 150, "speed": 3.4, "armor": 0.35, "size": 1.05, "weapon": "sword", "pers": "attack", "mass": 95.0, "stab": 1.5, "shield": true},
	"viking": {"name": Catalog.FIGHTERS.viking.name, "icon": "🪓", "cat": "people", "body": "human", "style": "viking",
		"hp": 140, "speed": 4.2, "armor": 0.1, "size": 1.05, "weapon": "axe", "pers": "berserk", "mass": 90.0, "stab": 1.3},
	"archer": {"name": Catalog.FIGHTERS.archer.name, "icon": "🏹", "cat": "people", "body": "human", "style": "archer",
		"hp": 80, "speed": 4.1, "armor": 0.0, "size": 1.0, "weapon": "bow", "pers": "ranged", "mass": 65.0, "stab": 0.9},
	"sniper": {"name": Catalog.FIGHTERS.sniper.name, "icon": "🎯", "cat": "people", "body": "human", "style": "sniper",
		"hp": 80, "speed": 3.7, "armor": 0.0, "size": 1.0, "weapon": "sniper", "pers": "ranged", "mass": 70.0, "stab": 0.9},
	"rocketeer": {"name": Catalog.FIGHTERS.rocketeer.name, "icon": "🚀", "cat": "people", "body": "human", "style": "rocketeer",
		"hp": 100, "speed": 3.6, "armor": 0.05, "size": 1.0, "weapon": "bazooka", "pers": "ranged", "mass": 80.0, "stab": 1.0},
	"grenadier": {"name": Catalog.FIGHTERS.grenadier.name, "icon": "🤾", "cat": "people", "body": "human", "style": "grenadier",
		"hp": 100, "speed": 3.9, "armor": 0.05, "size": 1.0, "weapon": "grenade", "pers": "ranged", "mass": 75.0, "stab": 1.0},
	"gunner": {"name": Catalog.FIGHTERS.gunner.name, "icon": "🔫", "cat": "people", "body": "human", "style": "gunner",
		"hp": 130, "speed": 3.2, "armor": 0.1, "size": 1.08, "weapon": "mg", "pers": "ranged", "mass": 95.0, "stab": 1.3},
	"medic": {"name": Catalog.FIGHTERS.medic.name, "icon": "⛑️", "cat": "people", "body": "human", "style": "medic",
		"hp": 90, "speed": 4.4, "armor": 0.0, "size": 1.0, "weapon": "pistol", "pers": "ranged", "mass": 65.0, "stab": 0.9, "heals": true},
	"ninja": {"name": Catalog.FIGHTERS.ninja.name, "icon": "🥷", "cat": "people", "body": "human", "style": "ninja",
		"hp": 90, "speed": 7.2, "armor": 0.0, "size": 0.95, "weapon": "katana", "pers": "attack", "mass": 60.0, "stab": 1.0, "dodge": 0.3},
	"giant": {"name": Catalog.FIGHTERS.giant.name, "icon": "🧌", "cat": "people", "body": "human", "style": "giant",
		"hp": 520, "speed": 3.1, "armor": 0.1, "size": 2.1, "weapon": "hammer", "pers": "attack", "mass": 400.0, "stab": 4.5, "voice": "roar"},
	"wizard": {"name": "Wizard", "icon": "🧙", "cat": "people", "body": "human", "style": "wizard",
		"hp": 85, "speed": 3.8, "armor": 0.0, "size": 1.0, "weapon": "fireball", "pers": "ranged", "mass": 65.0, "stab": 0.9, "special": true},
	"robot": {"name": "Robot", "icon": "🤖", "cat": "people", "body": "robot", "style": "robot",
		"hp": 380, "speed": 2.7, "armor": 0.4, "size": 1.12, "weapon": "laser", "pers": "ranged", "mass": 260.0, "stab": 2.6, "special": true},

	# 📜 History (see B3History): shield = the kind of shield on the left arm,
	# coat = a uniform colour instead of the team colour (the team colour then
	# shows on a sash, cuffs or hat band), bayonet = stabs with it up close.
	# body "rider" = a person on a horse (fast charges, both fall off when hit).
	"hoplite": {"name": "Hoplite", "icon": "🏺", "cat": "history", "body": "human", "style": "hoplite",
		"hp": 150, "speed": 3.6, "armor": 0.3, "size": 1.0, "weapon": "spear", "pers": "defend", "mass": 90.0, "stab": 1.6, "shield": "hoplon"},
	"immortal": {"name": "Immortal", "icon": "🗡️", "cat": "history", "body": "human", "style": "immortal",
		"hp": 110, "speed": 4.0, "armor": 0.12, "size": 1.0, "weapon": "spear", "pers": "attack", "mass": 75.0, "stab": 1.1, "shield": "wicker"},
	"legionary": {"name": "Legionary", "icon": "🦅", "cat": "history", "body": "human", "style": "legionary",
		"hp": 140, "speed": 3.8, "armor": 0.3, "size": 1.0, "weapon": "gladius", "pers": "attack", "mass": 88.0, "stab": 1.5, "shield": "scutum"},
	"gaul": {"name": "Gaul", "icon": "🐗", "cat": "history", "body": "human", "style": "gaul",
		"hp": 130, "speed": 4.5, "armor": 0.05, "size": 1.0, "weapon": "longsword", "pers": "berserk", "mass": 85.0, "stab": 1.3, "shield": "oval"},
	"saxon": {"name": "Saxon", "icon": "⚔️", "cat": "history", "body": "human", "style": "saxon",
		"hp": 140, "speed": 3.8, "armor": 0.15, "size": 1.0, "weapon": "axe", "pers": "defend", "mass": 88.0, "stab": 1.5, "shield": "round"},
	"longbow": {"name": "Longbowman", "icon": "🪶", "cat": "history", "body": "human", "style": "longbow",
		"hp": 80, "speed": 4.1, "armor": 0.0, "size": 1.0, "weapon": "longbow", "pers": "ranged", "mass": 65.0, "stab": 0.9},
	"horseknight": {"name": "Mounted Knight", "icon": "🏇", "cat": "history", "body": "rider", "style": "horseknight",
		"hp": 260, "speed": 6.0, "armor": 0.3, "size": 1.0, "weapon": "lance", "pers": "attack", "mass": 600.0, "stab": 3.0, "charge": true, "shield": "kite"},
	"redcoat": {"name": "Redcoat", "icon": "💂", "cat": "history", "body": "human", "style": "redcoat",
		"hp": 100, "speed": 3.7, "armor": 0.0, "size": 1.0, "weapon": "musket", "pers": "ranged", "mass": 72.0, "stab": 1.0, "bayonet": true},
	"minuteman": {"name": "Militia", "icon": "🌾", "cat": "history", "body": "human", "style": "minuteman",
		"hp": 90, "speed": 4.2, "armor": 0.0, "size": 1.0, "weapon": "musket", "pers": "ranged", "mass": 68.0, "stab": 0.95, "coat": "7b5a3c"},
	"linesman": {"name": "Line Infantry", "icon": "🥁", "cat": "history", "body": "human", "style": "linesman",
		"hp": 105, "speed": 3.7, "armor": 0.0, "size": 1.0, "weapon": "musket", "pers": "ranged", "mass": 72.0, "stab": 1.0, "bayonet": true},
	"cavalry": {"name": "Cavalry", "icon": "🐎", "cat": "history", "body": "rider", "style": "cavalry",
		"hp": 220, "speed": 6.6, "armor": 0.2, "size": 1.0, "weapon": "sabre", "pers": "attack", "mass": 550.0, "stab": 2.8, "charge": true},
	"union": {"name": "Union Soldier", "icon": "🧢", "cat": "history", "body": "human", "style": "union",
		"hp": 100, "speed": 3.8, "armor": 0.0, "size": 1.0, "weapon": "musket", "pers": "ranged", "mass": 72.0, "stab": 1.0, "bayonet": true, "coat": "2b3a67"},
	"confed": {"name": "Confederate", "icon": "🎺", "cat": "history", "body": "human", "style": "confed",
		"hp": 100, "speed": 3.9, "armor": 0.0, "size": 1.0, "weapon": "musket", "pers": "ranged", "mass": 70.0, "stab": 1.0, "bayonet": true, "coat": "8d9097"},
	"gi": {"name": "GI", "icon": "🎖️", "cat": "history", "body": "human", "style": "gi",
		"hp": 100, "speed": 4.0, "armor": 0.05, "size": 1.0, "weapon": "rifle", "pers": "ranged", "mass": 75.0, "stab": 1.0, "coat": "6b6a42"},

	"dog": {"name": Catalog.FIGHTERS.dog.name, "icon": "🐕", "cat": "animals", "body": "quad", "style": "dog",
		"hp": 70, "speed": 7.0, "armor": 0.0, "size": 1.0, "weapon": "bite", "pers": "attack", "mass": 30.0, "stab": 0.8, "voice": "bark"},
	"wolf": {"name": Catalog.FIGHTERS.wolf.name, "icon": "🐺", "cat": "animals", "body": "quad", "style": "wolf",
		"hp": 95, "speed": 7.6, "armor": 0.0, "size": 1.0, "weapon": "bite_big", "pers": "attack", "mass": 45.0, "stab": 1.0, "voice": "growl"},
	"bear": {"name": Catalog.FIGHTERS.bear.name, "icon": "🐻", "cat": "animals", "body": "quad", "style": "bear",
		"hp": 300, "speed": 5.2, "armor": 0.1, "size": 1.0, "weapon": "claw", "pers": "attack", "mass": 300.0, "stab": 3.0, "voice": "growl"},
	"bull": {"name": Catalog.FIGHTERS.bull.name, "icon": "🐂", "cat": "animals", "body": "quad", "style": "bull",
		"hp": 330, "speed": 5.4, "armor": 0.1, "size": 1.0, "weapon": "horns", "pers": "attack", "mass": 500.0, "stab": 3.5, "voice": "moo", "charge": true},
	"elephant": {"name": Catalog.FIGHTERS.elephant.name, "icon": "🐘", "cat": "animals", "body": "quad", "style": "elephant",
		"hp": 750, "speed": 3.7, "armor": 0.15, "size": 1.0, "weapon": "stomp", "pers": "defend", "mass": 2000.0, "stab": 7.0, "voice": "trumpet"},
	"chicken": {"name": Catalog.FIGHTERS.chicken.name, "icon": "🐔", "cat": "animals", "body": "bird", "style": "chicken",
		"hp": 25, "speed": 4.2, "armor": 0.0, "size": 1.0, "weapon": "peck", "pers": "peaceful", "mass": 4.0, "stab": 0.45, "voice": "cluck"},
	"gorilla": {"name": "Gorilla", "icon": "🦍", "cat": "animals", "body": "ape", "style": "gorilla",
		"hp": 400, "speed": 6.2, "armor": 0.12, "size": 1.3, "weapon": "gorilla_punch", "pers": "attack", "mass": 220.0, "stab": 2.8, "voice": "growl", "special": true},
	"mammoth": {"name": "Mammoth", "icon": "🦣", "cat": "animals", "body": "quad", "style": "mammoth",
		"hp": 1050, "speed": 4.4, "armor": 0.15, "size": 1.0, "weapon": "mammoth_tusks", "pers": "attack", "mass": 2600.0, "stab": 7.5, "voice": "trumpet", "charge": true},

	"trex": {"name": Catalog.FIGHTERS.trex.name, "icon": "🦖", "cat": "dinos", "body": "biped", "style": "trex",
		"hp": 1300, "speed": 5.6, "armor": 0.15, "size": 1.0, "weapon": "trex_bite", "pers": "attack", "mass": 3000.0, "stab": 9.0, "voice": "roar"},
	"raptor": {"name": Catalog.FIGHTERS.raptor.name, "icon": "🦎", "cat": "dinos", "body": "biped", "style": "raptor",
		"hp": 120, "speed": 8.6, "armor": 0.0, "size": 1.0, "weapon": "raptor_claw", "pers": "attack", "mass": 60.0, "stab": 1.1, "voice": "screech", "pounce": true},
	"trike": {"name": Catalog.FIGHTERS.triceratops.name, "icon": "🦏", "cat": "dinos", "body": "quad", "style": "trike",
		"hp": 850, "speed": 4.6, "armor": 0.25, "size": 1.0, "weapon": "trike_horns", "pers": "attack", "mass": 2500.0, "stab": 7.0, "voice": "growl", "charge": true},
	"stego": {"name": Catalog.FIGHTERS.stego.name, "icon": "🦔", "cat": "dinos", "body": "quad", "style": "stego",
		"hp": 700, "speed": 3.7, "armor": 0.2, "size": 1.0, "weapon": "tail_swipe", "pers": "defend", "mass": 2200.0, "stab": 6.5, "voice": "growl"},
	"brachio": {"name": Catalog.FIGHTERS.brachio.name, "icon": "🦕", "cat": "dinos", "body": "quad", "style": "brachio",
		"hp": 1800, "speed": 2.9, "armor": 0.1, "size": 1.0, "weapon": "brachio_stomp", "pers": "defend", "mass": 6000.0, "stab": 12.0, "voice": "trumpet"},
	"ptero": {"name": Catalog.FIGHTERS.ptero.name, "icon": "🦅", "cat": "dinos", "body": "bird", "style": "ptero",
		"hp": 140, "speed": 8.0, "armor": 0.0, "size": 1.0, "weapon": "swoop", "pers": "attack", "mass": 30.0, "stab": 1.0, "voice": "screech", "flying": true},
	"dragon": {"name": "Dragon", "icon": "🐉", "cat": "dinos", "body": "dragon", "style": "dragon",
		"hp": 800, "speed": 6.5, "armor": 0.15, "size": 2.0, "weapon": "fire_breath", "pers": "attack", "mass": 900.0, "stab": 5.0, "voice": "roar", "flying": true, "special": true},

	"tank": {"name": "Tank", "icon": "🪖", "cat": "vehicles", "body": "vehicle", "style": "tank",
		"hp": 480, "speed": 3.8, "armor": 0.05, "size": 3.4, "weapon": "tank_shell", "pers": "attack", "mass": 4000.0, "stab": 5.5,
		"turn": 1.1, "shot": 0.15, "melee": 0.4, "fire": 0.4, "blast": 1.8, "boom": 5.2},
	"jeep": {"name": "Jeep", "icon": "🚙", "cat": "vehicles", "body": "vehicle", "style": "jeep",
		"hp": 270, "speed": 9.0, "armor": 0.0, "size": 2.7, "weapon": "jeep_mg", "pers": "attack", "mass": 900.0, "stab": 1.6,
		"turn": 2.4, "shot": 0.4, "melee": 0.7, "fire": 0.7, "blast": 1.2, "boom": 4.0},
	"cannon": {"name": "Cannon", "icon": "💥", "cat": "vehicles", "body": "vehicle", "style": "cannon",
		"hp": 300, "speed": 0.0, "armor": 0.0, "size": 2.4, "weapon": "cannonball", "pers": "defend", "mass": 700.0, "stab": 2.2,
		"turn": 0.9, "shot": 0.5, "melee": 0.6, "fire": 0.6, "boom": 3.6},
	"mgnest": {"name": "MG Turret", "icon": "🔫", "cat": "vehicles", "body": "vehicle", "style": "mgnest",
		"hp": 380, "speed": 0.0, "armor": 0.0, "size": 2.6, "weapon": "turret_mg", "pers": "defend", "mass": 1500.0, "stab": 5.0,
		"turn": 3.2, "shot": 0.35, "melee": 0.6, "fire": 0.6, "boom": 3.2},
	# air: true = B3Aircraft (flies; see b3_aircraft.gd)
	"car": {"name": "Race Car", "icon": "🏎️", "cat": "vehicles", "body": "vehicle", "style": "car",
		"hp": 170, "speed": 13.0, "armor": 0.0, "size": 2.6, "weapon": "car_bump", "pers": "attack", "mass": 650.0, "stab": 1.2,
		"turn": 2.8, "shot": 0.45, "melee": 0.6, "fire": 0.7, "blast": 1.2, "boom": 3.2},
	"heli": {"name": "Helicopter", "icon": "🚁", "cat": "vehicles", "body": "vehicle", "style": "heli", "flying": true, "air": true,
		"hp": 360, "speed": 9.0, "armor": 0.0, "size": 7.0, "weapon": "heli_mg", "pers": "attack", "mass": 1200.0, "stab": 3.0,
		"turn": 2.0, "shot": 0.3, "melee": 0.5, "fire": 0.5, "blast": 0.8, "boom": 4.2},
	"plane": {"name": "Fighter Plane", "icon": "🛩️", "cat": "vehicles", "body": "vehicle", "style": "plane", "flying": true, "air": true,
		"hp": 240, "speed": 22.0, "armor": 0.0, "size": 7.5, "weapon": "plane_mg", "pers": "attack", "mass": 900.0, "stab": 3.0,
		"turn": 1.25, "shot": 0.25, "melee": 0.5, "fire": 0.5, "blast": 0.9, "boom": 4.0},
}
const UNIT_ORDER := {
	"people": ["stick", "soldier", "knight", "viking", "archer", "sniper", "rocketeer", "grenadier", "gunner", "medic", "ninja", "giant", "wizard", "robot"],
	"animals": ["dog", "wolf", "bear", "bull", "elephant", "chicken", "gorilla", "mammoth"],
	"dinos": ["trex", "raptor", "trike", "stego", "brachio", "ptero", "dragon"],
	"history": ["hoplite", "immortal", "legionary", "gaul", "saxon", "longbow", "horseknight", "redcoat", "minuteman", "linesman", "cavalry", "union", "confed", "gi"],
	"vehicles": ["tank", "jeep", "cannon", "mgnest", "car", "heli", "plane"],
}

## type: melee | gun | proj | throw.  range in metres (scaled by unit size for melee).
## knock: speed (m/s) given to a normal-sized target; big hits knock it over.
const WEAPONS := {
	"fists": {"type": "melee", "range": 1.3, "dmg": 9.0, "cd": 0.55, "knock": 3.5, "snd": "punch", "anim": "punch"},
	"bash": {"type": "melee", "range": 1.4, "dmg": 12.0, "cd": 0.8, "knock": 4.5, "snd": "bonk", "anim": "swing"},
	"sword": {"type": "melee", "range": 1.7, "dmg": 22.0, "cd": 0.85, "knock": 4.5, "snd": "slash", "anim": "swing"},
	"axe": {"type": "melee", "range": 1.7, "dmg": 26.0, "cd": 0.95, "knock": 6.5, "snd": "slash", "anim": "swing"},
	"katana": {"type": "melee", "range": 1.7, "dmg": 17.0, "cd": 0.42, "knock": 3.5, "snd": "slash", "anim": "swing"},
	"hammer": {"type": "melee", "range": 1.35, "dmg": 45.0, "cd": 1.7, "knock": 16.0, "aoe": 1.2, "snd": "bonk", "anim": "slam", "shake": 0.35},
	"rifle": {"type": "gun", "range": 22.0, "dmg": 14.0, "cd": 1.0, "spread": 0.03, "knock": 1.5, "snd": "gun_rifle", "tracer": Color(4.0, 3.2, 1.2)},
	"pistol": {"type": "gun", "range": 15.0, "dmg": 9.0, "cd": 0.75, "spread": 0.05, "knock": 1.0, "snd": "gun_pistol", "tracer": Color(4.0, 3.2, 1.2)},
	"mg": {"type": "gun", "range": 19.0, "dmg": 6.0, "cd": 0.085, "burst": 10, "reload": 1.4, "spread": 0.075, "knock": 1.2, "snd": "gun_mg", "tracer": Color(4.0, 2.4, 0.8)},
	"sniper": {"type": "gun", "range": 48.0, "dmg": 70.0, "cd": 3.0, "aim": 0.9, "spread": 0.004, "knock": 7.5, "snd": "gun_sniper", "tracer": Color(5.0, 5.0, 4.0)},
	"bow": {"type": "proj", "proj": "arrow", "range": 26.0, "dmg": 22.0, "cd": 1.5, "speed": 24.0, "knock": 2.0, "snd": "bow", "anim": "bow"},
	"bazooka": {"type": "proj", "proj": "rocket", "range": 24.0, "dmg": 45.0, "cd": 3.2, "speed": 19.0, "radius": 3.2, "power": 11.0, "snd": "bazooka"},
	"grenade": {"type": "throw", "proj": "grenade", "range": 16.0, "dmg": 45.0, "cd": 3.6, "radius": 3.6, "power": 12.0, "snd": "swing", "anim": "throw"},
	"bite": {"type": "melee", "range": 1.25, "dmg": 10.0, "cd": 0.7, "knock": 2.5, "snd": "snap", "anim": "bite"},
	"bite_big": {"type": "melee", "range": 1.35, "dmg": 14.0, "cd": 0.8, "knock": 3.0, "snd": "snap", "anim": "bite"},
	"claw": {"type": "melee", "range": 1.9, "dmg": 28.0, "cd": 1.2, "knock": 9.0, "snd": "slash", "anim": "bite"},
	"horns": {"type": "melee", "range": 2.1, "dmg": 22.0, "cd": 1.2, "knock": 9.0, "snd": "bonk", "anim": "bite", "charge_dmg": 32.0, "charge_knock": 17.0},
	"stomp": {"type": "melee", "range": 2.6, "dmg": 35.0, "cd": 1.8, "knock": 13.0, "aoe": 3.2, "snd": "stomp", "anim": "stomp", "shake": 0.3},
	"peck": {"type": "melee", "range": 0.9, "dmg": 3.0, "cd": 0.6, "knock": 1.0, "snd": "cluck", "anim": "bite"},
	"trex_bite": {"type": "melee", "range": 3.7, "dmg": 60.0, "cd": 1.4, "knock": 16.0, "toss": true, "snd": "snap", "anim": "bite", "shake": 0.2},
	"raptor_claw": {"type": "melee", "range": 1.5, "dmg": 16.0, "cd": 0.55, "knock": 4.0, "snd": "slash", "anim": "bite"},
	"trike_horns": {"type": "melee", "range": 3.0, "dmg": 30.0, "cd": 1.3, "knock": 12.0, "snd": "bonk", "anim": "bite", "charge_dmg": 40.0, "charge_knock": 20.0},
	"tail_swipe": {"type": "melee", "range": 3.6, "dmg": 32.0, "cd": 1.6, "knock": 14.0, "aoe": 3.8, "snd": "swing", "anim": "tail", "shake": 0.15},
	"brachio_stomp": {"type": "melee", "range": 4.0, "dmg": 50.0, "cd": 2.2, "knock": 16.0, "aoe": 4.8, "snd": "stomp", "anim": "stomp", "shake": 0.5},
	"swoop": {"type": "melee", "range": 1.7, "dmg": 16.0, "cd": 1.7, "knock": 8.0, "snd": "screech", "anim": "bite"},
	# new fighters (see B3Special)
	"fireball": {"type": "proj", "proj": "fireball", "range": 19.0, "dmg": 28.0, "cd": 2.6, "speed": 15.0, "radius": 2.4, "power": 8.0, "snd": "flame"},
	"laser": {"type": "gun", "range": 24.0, "dmg": 34.0, "cd": 1.5, "aim": 0.45, "spread": 0.012, "knock": 3.5, "snd": "gun_laser", "tracer": Color(3.2, 0.3, 0.4), "beam": 0.24},
	"gorilla_punch": {"type": "melee", "range": 1.5, "dmg": 17.0, "cd": 0.5, "knock": 6.5, "snd": "punch", "anim": "punch"},
	"gorilla_pound": {"type": "melee", "range": 1.0, "dmg": 30.0, "cd": 1.0, "knock": 13.0, "aoe": 3.8, "snd": "pound", "anim": "slam", "shake": 0.35},
	"boulder": {"type": "throw", "proj": "boulder", "range": 17.0, "dmg": 40.0, "cd": 7.0, "radius": 1.9, "power": 9.0, "knock": 9.0, "snd": "swing"},
	"mammoth_tusks": {"type": "melee", "range": 3.0, "dmg": 36.0, "cd": 1.4, "knock": 13.0, "aoe": 2.4, "snd": "bonk", "anim": "bite", "shake": 0.15, "charge_dmg": 45.0, "charge_knock": 21.0},
	"fire_breath": {"type": "breath", "range": 12.0, "dmg": 5.0, "cd": 5.0, "len": 1.5, "snd": "flame"},
	# 📜 history (see B3History). thrust: stabs forward instead of swinging.
	# musket: a slow reload, one loud shot with a big puff of smoke (smoke), and
	# everyone on a team fires together (volley).
	"spear": {"type": "melee", "range": 2.4, "dmg": 17.0, "cd": 0.85, "knock": 4.0, "snd": "slash", "anim": "thrust"},
	"gladius": {"type": "melee", "range": 1.4, "dmg": 19.0, "cd": 0.55, "knock": 3.5, "snd": "slash", "anim": "swing"},
	"longsword": {"type": "melee", "range": 1.9, "dmg": 24.0, "cd": 0.95, "knock": 6.0, "snd": "slash", "anim": "swing"},
	"longbow": {"type": "proj", "proj": "arrow", "range": 42.0, "dmg": 22.0, "cd": 1.8, "speed": 25.0, "knock": 2.0, "snd": "bow", "anim": "bow"},
	"musket": {"type": "gun", "range": 30.0, "dmg": 36.0, "cd": 4.2, "spread": 0.05, "knock": 3.5, "snd": "gun_shotgun", "tracer": Color(4.0, 3.4, 2.0), "smoke": true, "volley": 5.0},
	"bayonet": {"type": "melee", "range": 1.9, "dmg": 22.0, "cd": 0.9, "knock": 5.0, "snd": "slash", "anim": "thrust"},
	"sabre": {"type": "melee", "range": 2.0, "dmg": 21.0, "cd": 0.75, "knock": 5.5, "snd": "slash", "anim": "swing", "charge_dmg": 30.0, "charge_knock": 15.0},
	"lance": {"type": "melee", "range": 2.8, "dmg": 18.0, "cd": 1.1, "knock": 7.0, "snd": "bonk", "anim": "thrust", "charge_dmg": 44.0, "charge_knock": 18.0},
	# right-click powers (see B3Player.power): a kick (people) or a shove
	# (animals) that pushes an enemy back a little. word: pops up on a hit.
	"kick": {"type": "melee", "range": 1.2, "dmg": 6.0, "cd": 1.2, "knock": 5.5, "snd": "bonk", "anim": "kick", "word": "POW!"},
	"shove": {"type": "melee", "range": 1.3, "dmg": 6.0, "cd": 1.2, "knock": 5.5, "snd": "bonk", "anim": "bite", "word": "BONK!"},
	# vehicles (see B3Vehicle)
	"tank_shell": {"type": "proj", "proj": "tankshell", "range": 26.0, "dmg": 48.0, "cd": 4.0, "speed": 30.0, "radius": 3.0, "power": 11.0, "snd": "cannon", "min": 5.5},
	"tank_mg": {"type": "gun", "range": 14.0, "dmg": 5.0, "cd": 0.09, "burst": 8, "reload": 1.3, "spread": 0.07, "knock": 1.0, "snd": "gun_mg", "tracer": Color(4.0, 2.4, 0.8)},
	"jeep_mg": {"type": "gun", "range": 20.0, "dmg": 8.0, "cd": 0.08, "burst": 12, "reload": 1.3, "spread": 0.07, "knock": 1.3, "snd": "gun_mg", "tracer": Color(4.0, 2.4, 0.8)},
	"cannonball": {"type": "proj", "proj": "cannonball", "range": 42.0, "dmg": 70.0, "cd": 3.6, "speed": 18.0, "radius": 3.6, "power": 14.0, "snd": "cannon", "min": 7.0},
	"turret_mg": {"type": "gun", "range": 25.0, "dmg": 9.0, "cd": 0.075, "burst": 14, "reload": 1.3, "spread": 0.06, "knock": 1.4, "snd": "gun_mg", "tracer": Color(4.0, 2.4, 0.8)},
	"car_bump": {"type": "melee", "range": 1.0, "dmg": 10.0, "cd": 1.0, "knock": 14.0, "snd": "boing", "anim": "bite"},
	"heli_mg": {"type": "gun", "range": 28.0, "dmg": 7.0, "cd": 0.08, "burst": 14, "reload": 1.2, "spread": 0.05, "knock": 1.3, "snd": "gun_mg", "tracer": Color(4.0, 2.4, 0.8)},
	"heli_rocket": {"type": "proj", "proj": "rocket", "range": 34.0, "dmg": 42.0, "cd": 3.6, "speed": 26.0, "radius": 3.0, "power": 11.0, "snd": "rocket"},
	"plane_mg": {"type": "gun", "range": 42.0, "dmg": 10.0, "cd": 0.06, "burst": 18, "reload": 1.1, "spread": 0.035, "knock": 1.5, "snd": "gun_mg", "tracer": Color(4.0, 3.0, 1.0)},
	"plane_bomb": {"type": "proj", "proj": "bomb", "range": 30.0, "dmg": 65.0, "cd": 2.2, "speed": 0.0, "radius": 4.4, "power": 14.0, "snd": "whistle"},
}

## Things you drop or place from the Booms tab.
const BOOMS := {
	"grenade": {"name": "Grenade", "icon": "💣", "radius": 4.0, "power": 13.0, "dmg": 55.0, "tip": "Drops and goes boom after a moment"},
	"dynamite": {"name": "Dynamite", "icon": "🧨", "radius": 5.5, "power": 17.0, "dmg": 80.0, "tip": "Fizzes for 3 seconds, then BOOM"},
	"c4": {"name": "C4", "icon": "📟", "radius": 6.0, "power": 19.0, "dmg": 90.0, "tip": "Place lots, then press Detonate!"},
	"mine": {"name": "Landmine", "icon": "🪤", "radius": 4.2, "power": 19.0, "dmg": 70.0, "tip": "Goes off when someone steps on it"},
	"xbarrel": {"name": "Boom Barrel", "icon": "🛢️", "radius": 5.2, "power": 15.0, "dmg": 70.0, "tip": "Explodes when it's shot or blasted"},
	"cluster": {"name": "Cluster Bomb", "icon": "🎆", "radius": 3.2, "power": 11.0, "dmg": 40.0, "tip": "Splits into lots of little bombs"},
	"napalm": {"name": "Napalm", "icon": "🔥", "radius": 3.5, "power": 8.0, "dmg": 25.0, "tip": "Sets the ground on fire"},
	"acidbomb": {"name": "Acid Bomb", "icon": "🫙", "radius": 3.0, "power": 7.0, "dmg": 20.0, "tip": "Splashes a gooey acid puddle"},
	"airstrike": {"name": "Airstrike", "icon": "✈️", "radius": 4.6, "power": 15.0, "dmg": 70.0, "tip": "A plane drops a line of bombs"},
	"artillery": {"name": "Artillery", "icon": "☄️", "radius": 4.0, "power": 14.0, "dmg": 60.0, "tip": "Lots of shells rain down"},
	"nuke": {"name": "NUKE", "icon": "☢️", "radius": 44.0, "power": 42.0, "dmg": 500.0, "tip": "The biggest boom of all!"},
}
const BOOM_ORDER := ["grenade", "dynamite", "c4", "mine", "xbarrel", "cluster", "napalm", "acidbomb", "airstrike", "artillery", "nuke"]

const HAZARDS := {
	"lava": {"name": "Lava Pool", "icon": "🌋", "kind": "lava", "radius": 3.5, "tip": "Hot hot hot! Drag to make it bigger"},
	"lava_lake": {"name": "Lava Lake", "icon": "🔥", "kind": "lava", "radius": 7.0, "tip": "A big lake of lava"},
	"acid": {"name": "Acid Pool", "icon": "🧪", "kind": "acid", "radius": 3.5, "tip": "Gooey green acid. Drag to make it bigger"},
	"acid_swamp": {"name": "Acid Swamp", "icon": "☣️", "kind": "acid", "radius": 7.0, "tip": "A big bubbly acid swamp"},
}
const HAZARD_ORDER := ["lava", "lava_lake", "acid", "acid_swamp"]

const STRUCTS := {
	"block": {"name": "Block", "icon": "🔲", "tip": "A big stone platform"},
	"wall": {"name": "Wall", "icon": "🧱", "tip": "Drag to build a wall that long"},
	"ramp": {"name": "Ramp", "icon": "📐", "tip": "Walk up! Drag to point it"},
	"tower": {"name": "Tower", "icon": "🗼", "tip": "Put archers and snipers on top"},
	"bunker": {"name": "Bunker", "icon": "🏚️", "tip": "A strong concrete hideout"},
	"bridge": {"name": "Bridge", "icon": "🌉", "tip": "Drag to point it. Great over lava!"},
	"sandbags": {"name": "Sandbags", "icon": "🟫", "tip": "Low cover to hide behind"},
	"crates": {"name": "Crates", "icon": "📦", "tip": "A wobbly stack of crates"},
}
const STRUCT_ORDER := ["block", "wall", "ramp", "tower", "bunker", "bridge", "sandbags", "crates"]

## Maps (built by B3World). dust: colour of the dust puffs on that ground.
## beach: the sea is on the +z side (shore about z = +48, bluffs from
## z = -30 to -64). pass: a 20 m wide gap along x through cliffs (tall to
## -z, a low bank and the sea to +z), opening out past x = ±50.
const MAPS := {
	"grassland": {"name": "Grassland", "icon": "🌳", "ground": Color("62b347"), "ground2": Color("86c95a"), "skirt": Color("58a63f"),
		"sky_top": Color("3f8fe0"), "sky_horizon": Color("bfe3ff"), "sun": Color("fff1d6"), "sun_energy": 1.15, "ambient": 0.42,
		"dust": Color(0.62, 0.55, 0.4)},
	"desert": {"name": "Desert", "icon": "🏜️", "ground": Color("e8c27a"), "ground2": Color("f3d699"), "skirt": Color("deb46a"),
		"sky_top": Color("4a9be8"), "sky_horizon": Color("ffe7c2"), "sun": Color("fff0d0"), "sun_energy": 1.15, "ambient": 0.4,
		"dust": Color(0.9, 0.78, 0.55)},
	"snow": {"name": "Snow", "icon": "❄️", "ground": Color("eef4fb"), "ground2": Color("d6e4f2"), "skirt": Color("e4edf7"),
		"sky_top": Color("7fa8d6"), "sky_horizon": Color("e8f0fa"), "sun": Color("eef4ff"), "sun_energy": 0.95, "ambient": 0.42,
		"dust": Color(0.95, 0.97, 1.0)},
	"volcano": {"name": "Volcano", "icon": "🌋", "ground": Color("5a4c48"), "ground2": Color("6f5d55"), "skirt": Color("4a3e3b"),
		"sky_top": Color("4a3550"), "sky_horizon": Color("e08a5a"), "sun": Color("ffd0a8"), "sun_energy": 1.0, "ambient": 0.45,
		"dust": Color(0.35, 0.3, 0.28)},
	"beach": {"name": "Beach", "icon": "🏖️", "ground": Color("e9d49a"), "ground2": Color("f2e2b0"), "skirt": Color("6aaa45"),
		"sky_top": Color("4d9be6"), "sky_horizon": Color("d6ecff"), "sun": Color("fff4dc"), "sun_energy": 1.15, "ambient": 0.42,
		"dust": Color(0.88, 0.8, 0.6)},
	"farmland": {"name": "Farmland", "icon": "🌾", "ground": Color("6fb84a"), "ground2": Color("93cc5c"), "skirt": Color("62a845"),
		"sky_top": Color("4592e0"), "sky_horizon": Color("cbe8ff"), "sun": Color("fff0d0"), "sun_energy": 1.15, "ambient": 0.42,
		"dust": Color(0.6, 0.52, 0.38)},
	"pass": {"name": "Mountain Pass", "icon": "⛰️", "ground": Color("b5ab78"), "ground2": Color("c4b98a"), "skirt": Color("9c9468"),
		"sky_top": Color("3f8de0"), "sky_horizon": Color("cfe6ff"), "sun": Color("fff2d8"), "sun_energy": 1.15, "ambient": 0.42,
		"dust": Color(0.7, 0.62, 0.48)},
	"town": {"name": "Town", "icon": "🏘️", "ground": Color("72b552"), "ground2": Color("8cc766"), "skirt": Color("62a845"),
		"sky_top": Color("4592e0"), "sky_horizon": Color("cfe8ff"), "sun": Color("fff1d6"), "sun_energy": 1.15, "ambient": 0.42,
		"dust": Color(0.62, 0.6, 0.56)},
}
const MAP_ORDER := ["grassland", "farmland", "desert", "beach", "snow", "pass", "town", "volcano"]


static func team_col(t: String) -> Color:
	var d: Dictionary = TEAM.get(t, TEAM.wild)
	var c: Color = d.col
	return c


## 🪙 What each thing costs in budget battles (🧩 Puzzles, 🌊 Wave Defense):
## fighters, animals, dinosaurs, vehicles, buildings, pools and booms.
const COSTS := {
	"stick": 1, "soldier": 2, "knight": 3, "viking": 3, "archer": 2, "sniper": 4, "rocketeer": 4,
	"grenadier": 3, "gunner": 4, "medic": 3, "ninja": 3, "giant": 7, "wizard": 6, "robot": 8,
	"hoplite": 3, "immortal": 2, "legionary": 3, "gaul": 2, "saxon": 2, "longbow": 2, "horseknight": 5,
	"redcoat": 2, "minuteman": 2, "linesman": 2, "cavalry": 4, "union": 2, "confed": 2, "gi": 2,
	"dog": 1, "wolf": 2, "bear": 4, "bull": 4, "elephant": 7, "chicken": 1, "gorilla": 6, "mammoth": 9,
	"trex": 12, "raptor": 3, "trike": 8, "stego": 7, "brachio": 10, "ptero": 4, "dragon": 15,
	"tank": 15, "jeep": 6, "cannon": 6, "mgnest": 5, "car": 3, "heli": 12, "plane": 14,
	"block": 1, "wall": 2, "ramp": 1, "tower": 5, "bunker": 6, "bridge": 3, "sandbags": 1, "crates": 1,
	"lava": 4, "lava_lake": 8, "acid": 4, "acid_swamp": 8,
	"grenade": 2, "dynamite": 2, "c4": 3, "mine": 2, "xbarrel": 2, "cluster": 5, "napalm": 5,
	"acidbomb": 5, "airstrike": 10, "artillery": 10, "nuke": 30,
}


## 🪙 The price of `id` in a budget battle (3 if it isn't in COSTS).
static func cost(id: String) -> int:
	return int(COSTS.get(id, 3))


static func unit_def(kind: String) -> Dictionary:
	var d: Dictionary = UNITS.get(kind, UNITS.stick)
	return d


static func weapon(id: String) -> Dictionary:
	var d: Dictionary = WEAPONS.get(id, WEAPONS.fists)
	return d


static func is_vehicle(kind: String) -> bool:
	var d: Dictionary = UNITS.get(kind, {})
	return String(d.get("body", "")) == "vehicle"


## Name + icon for anything you can place.
static func item_label(id: String) -> String:
	for table in [UNITS, BOOMS, HAZARDS, STRUCTS]:
		if table.has(id):
			var d: Dictionary = table[id]
			return "%s %s" % [d.icon, d.name]
	return id


static func item_cat(id: String) -> String:
	if UNITS.has(id):
		var d: Dictionary = UNITS[id]
		return String(d.cat)
	if BOOMS.has(id):
		return "booms"
	if HAZARDS.has(id):
		return "hazards"
	if STRUCTS.has(id):
		return "build"
	return ""
