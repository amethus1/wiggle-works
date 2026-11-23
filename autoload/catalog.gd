extends Node
## Every Wiggly, toy, world, magic spell and sticker in Wiggle Works.
## Autoloaded as `Catalog`.

# ---------------------------------------------------------------- Wigglies
## Soft jelly critters. radius = body size; stiff/press = how firm the jelly is;
## special = what "Use" (F) does.
const WIGGLIES := {
	"bloop": {"name": "Bloop", "color": Color("4aa8ff"), "dark": Color("1f5fbf"), "mass": 0.18, "stiff": 0.55, "press": 1.0,
		"bounce": 0.55, "fric": 0.7, "special": "Super Bounce", "desc": "Bouncy and brave. Loves being thrown!"},
	"gummy": {"name": "Gummy", "color": Color("5ad66a"), "dark": Color("23893a"), "mass": 0.2, "stiff": 0.4, "press": 0.85,
		"bounce": 0.15, "fric": 1.4, "special": "Sticky Mode", "desc": "Sticks to anything it lands on."},
	"zappy": {"name": "Zappy", "color": Color("ffd43b"), "dark": Color("c9900a"), "mass": 0.17, "stiff": 0.6, "press": 1.0,
		"bounce": 0.45, "fric": 0.7, "special": "Zap!", "desc": "Full of sparks. Zaps machines on!"},
	"blaze": {"name": "Blaze", "color": Color("ff7a3d"), "dark": Color("c23c12"), "mass": 0.17, "stiff": 0.55, "press": 1.0,
		"bounce": 0.4, "fric": 0.7, "special": "Flame Puff", "desc": "Warm and glowy. Lights fireworks and melts ice."},
	"frosty": {"name": "Frosty", "color": Color("8fe8ff"), "dark": Color("3aa7cf"), "mass": 0.19, "stiff": 0.6, "press": 1.0,
		"bounce": 0.3, "fric": 0.08, "special": "Frost Breath", "desc": "Slides like a penguin. Freezes things solid."},
	"puffy": {"name": "Puffy", "color": Color("ff8fd0"), "dark": Color("cc4f9a"), "mass": 0.08, "stiff": 0.35, "press": 1.25,
		"bounce": 0.6, "fric": 0.6, "special": "Puff Up", "desc": "Light as a cloud. Puffs up and floats away."},
	"boulder": {"name": "Boulder", "color": Color("9aa3b5"), "dark": Color("5a6276"), "mass": 0.6, "stiff": 0.9, "press": 1.2,
		"bounce": 0.08, "fric": 0.9, "special": "Ground Pound", "desc": "Heavy and stubborn. Smashes through stuff."},
	"twinkle": {"name": "Twinkle", "color": Color("b48cff"), "dark": Color("7246d1"), "mass": 0.16, "stiff": 0.55, "press": 1.0,
		"bounce": 0.5, "fric": 0.7, "special": "Twinkle Warp", "desc": "Magic sparkles. Teleports in a flash!"},
}
const WIGGLY_ORDER := ["bloop", "gummy", "zappy", "blaze", "frosty", "puffy", "boulder", "twinkle"]

# -------------------------------------------------------------------- Toys
## shape: circle (r) | box (w, h) | tri (w, h).  mass in kg-ish units.
## metal = magnets pull it.  breaks = shatters on a hard hit.  floaty = floats in water.
## power: "source" makes power on wires; "use" gadgets run while powered.
const TOYS := [
	# Balls
	{"id": "beach_ball", "cat": "Balls", "name": "Beach Ball", "desc": "Light, bouncy and floats.", "shape": "circle", "r": 30, "mass": 0.5, "bounce": 0.75, "fric": 0.6, "color": Color("ff5a5a"), "floaty": true},
	{"id": "bouncy_ball", "cat": "Balls", "name": "Super Bouncy Ball", "desc": "Boing boing boing!", "shape": "circle", "r": 13, "mass": 0.35, "bounce": 0.98, "fric": 0.8, "color": Color("ff3df0")},
	{"id": "soccer_ball", "cat": "Balls", "name": "Soccer Ball", "desc": "Kick it at the goal.", "shape": "circle", "r": 22, "mass": 1.0, "bounce": 0.6, "fric": 0.7, "color": Color("ffffff")},
	{"id": "bowling_ball", "cat": "Balls", "name": "Bowling Ball", "desc": "Heavy. Knocks everything over.", "shape": "circle", "r": 24, "mass": 14.0, "bounce": 0.05, "fric": 0.5, "color": Color("5b3fbf"), "metal": false},
	{"id": "marble", "cat": "Balls", "name": "Marble", "desc": "Tiny, shiny and rolls forever.", "shape": "circle", "r": 9, "mass": 0.6, "bounce": 0.4, "fric": 0.15, "color": Color("4fd1c5")},
	{"id": "steel_ball", "cat": "Balls", "name": "Steel Ball", "desc": "Magnets love it.", "shape": "circle", "r": 16, "mass": 6.0, "bounce": 0.2, "fric": 0.4, "color": Color("c9d3e0"), "metal": true},

	# Blocks
	{"id": "wood_block", "cat": "Blocks", "name": "Wood Block", "desc": "The building basic.", "shape": "box", "w": 36, "h": 36, "mass": 2.0, "bounce": 0.1, "fric": 0.8, "color": Color("d99a55"), "floaty": true},
	{"id": "plank", "cat": "Blocks", "name": "Long Plank", "desc": "For bridges, ramps and see-saws.", "shape": "box", "w": 150, "h": 14, "mass": 2.4, "bounce": 0.1, "fric": 0.8, "color": Color("c98a48"), "floaty": true},
	{"id": "brick", "cat": "Blocks", "name": "Brick", "desc": "Heavy and solid.", "shape": "box", "w": 48, "h": 24, "mass": 4.0, "bounce": 0.05, "fric": 0.9, "color": Color("d0573f")},
	{"id": "abc_block", "cat": "Blocks", "name": "Letter Block", "desc": "A, B, C… spell something!", "shape": "box", "w": 38, "h": 38, "mass": 1.6, "bounce": 0.15, "fric": 0.8, "color": Color("ffcf4a"), "floaty": true},
	{"id": "glass_pane", "cat": "Blocks", "name": "Glass Pane", "desc": "Smashes into sparkly bits.", "shape": "box", "w": 14, "h": 110, "mass": 2.0, "bounce": 0.1, "fric": 0.3, "color": Color(0.7, 0.9, 1.0, 0.55), "breaks": 380.0},
	{"id": "ice_cube", "cat": "Blocks", "name": "Ice Cube", "desc": "Slippery! Melts near Blaze.", "shape": "box", "w": 40, "h": 40, "mass": 1.5, "bounce": 0.05, "fric": 0.02, "color": Color(0.75, 0.95, 1.0, 0.8), "breaks": 520.0, "floaty": true},
	{"id": "pillow", "cat": "Blocks", "name": "Pillow", "desc": "Soft landing guaranteed.", "shape": "box", "w": 80, "h": 34, "mass": 0.7, "bounce": 0.35, "fric": 0.9, "color": Color("f2f0ff"), "floaty": true},
	{"id": "ramp", "cat": "Blocks", "name": "Ramp", "desc": "Launch things off it.", "shape": "tri", "w": 120, "h": 64, "mass": 6.0, "bounce": 0.05, "fric": 0.7, "color": Color("7cc1ff")},
	{"id": "metal_beam", "cat": "Blocks", "name": "Metal Beam", "desc": "Strong. Magnets pull it.", "shape": "box", "w": 160, "h": 18, "mass": 8.0, "bounce": 0.1, "fric": 0.6, "color": Color("9fb0c4"), "metal": true},

	# Machines: power sources
	{"id": "battery", "cat": "Machines", "name": "Battery", "desc": "Always makes power. Wire it to machines.", "shape": "box", "w": 30, "h": 48, "mass": 1.5, "bounce": 0.1, "fric": 0.7, "color": Color("3ddc84"), "power": "source", "metal": true},
	{"id": "switch", "cat": "Machines", "name": "Switch", "desc": "Click Use to turn power on and off.", "shape": "box", "w": 40, "h": 30, "mass": 1.0, "bounce": 0.1, "fric": 0.8, "color": Color("ff6b6b"), "power": "source", "use": "Flip"},
	{"id": "button", "cat": "Machines", "name": "Big Button", "desc": "Makes power while something presses it.", "shape": "box", "w": 56, "h": 18, "mass": 3.0, "bounce": 0.0, "fric": 0.9, "color": Color("ff4757"), "power": "source"},
	{"id": "timer", "cat": "Machines", "name": "Blinky Timer", "desc": "Power on, power off, every second.", "shape": "box", "w": 36, "h": 36, "mass": 1.2, "bounce": 0.1, "fric": 0.8, "color": Color("a29bfe"), "power": "source"},
	# Machines: things that run on power (or on Use)
	{"id": "lamp", "cat": "Machines", "name": "Lamp", "desc": "Lights up. Best at night!", "shape": "box", "w": 26, "h": 40, "mass": 1.2, "bounce": 0.1, "fric": 0.8, "color": Color("ffe066"), "power": "use", "use": "On/Off"},
	{"id": "bell", "cat": "Machines", "name": "Bell", "desc": "Ding! when powered or hit.", "shape": "circle", "r": 20, "mass": 1.5, "bounce": 0.3, "fric": 0.6, "color": Color("ffc93c"), "power": "use", "use": "Ding", "metal": true},
	{"id": "fan", "cat": "Machines", "name": "Fan", "desc": "Blows things away. Whoosh!", "shape": "box", "w": 46, "h": 56, "mass": 3.0, "bounce": 0.05, "fric": 0.9, "color": Color("74b9ff"), "power": "use", "use": "On/Off"},
	{"id": "magnet", "cat": "Machines", "name": "Magnet", "desc": "Pulls metal things close.", "shape": "box", "w": 50, "h": 34, "mass": 4.0, "bounce": 0.05, "fric": 0.8, "color": Color("e74c3c"), "power": "use", "use": "On/Off", "metal": true},
	{"id": "motor", "cat": "Machines", "name": "Motor Wheel", "desc": "Spins when powered. Hinge it on!", "shape": "circle", "r": 24, "mass": 2.0, "bounce": 0.2, "fric": 1.2, "color": Color("2d3436"), "power": "use", "use": "On/Off", "metal": true},
	{"id": "rocket", "cat": "Machines", "name": "Rocket Booster", "desc": "Glue it to anything. Blast off!", "shape": "box", "w": 54, "h": 22, "mass": 1.0, "bounce": 0.1, "fric": 0.6, "color": Color("dfe6e9"), "power": "use", "use": "On/Off", "metal": true},
	{"id": "propeller", "cat": "Machines", "name": "Propeller", "desc": "Lifts things into the sky.", "shape": "box", "w": 70, "h": 16, "mass": 1.0, "bounce": 0.1, "fric": 0.6, "color": Color("fd79a8"), "power": "use", "use": "On/Off"},
	{"id": "conveyor", "cat": "Machines", "name": "Conveyor Belt", "desc": "Carries things along.", "shape": "box", "w": 180, "h": 20, "mass": 10.0, "bounce": 0.0, "fric": 1.0, "color": Color("636e72"), "power": "use", "use": "On/Off", "metal": true},
	{"id": "spring_pad", "cat": "Machines", "name": "Spring Pad", "desc": "Step on it to get launched!", "shape": "box", "w": 70, "h": 20, "mass": 4.0, "bounce": 0.2, "fric": 0.9, "color": Color("00cec9")},
	{"id": "cannon", "cat": "Machines", "name": "Ball Cannon", "desc": "Fires bouncy balls. Use or power it.", "shape": "box", "w": 64, "h": 30, "mass": 6.0, "bounce": 0.05, "fric": 0.9, "color": Color("2c3e50"), "power": "use", "use": "Fire!", "metal": true},
	{"id": "bubbler", "cat": "Machines", "name": "Bubble Maker", "desc": "Blows bubbles that lift small things.", "shape": "box", "w": 44, "h": 44, "mass": 2.0, "bounce": 0.1, "fric": 0.8, "color": Color("81ecec"), "power": "use", "use": "On/Off"},

	# Booms
	{"id": "confetti", "cat": "Booms", "name": "Confetti Popper", "desc": "Pop! A party in a tube.", "shape": "box", "w": 18, "h": 40, "mass": 0.5, "bounce": 0.2, "fric": 0.7, "color": Color("ff9ff3"), "use": "Pop!"},
	{"id": "firework", "cat": "Booms", "name": "Firework", "desc": "Light it and watch the sky!", "shape": "box", "w": 14, "h": 48, "mass": 0.5, "bounce": 0.1, "fric": 0.7, "color": Color("ff6b81"), "use": "Light"},
	{"id": "paint_bomb", "cat": "Booms", "name": "Paint Bomb", "desc": "Splats everything nearby with color.", "shape": "circle", "r": 17, "mass": 1.0, "bounce": 0.2, "fric": 0.7, "color": Color("6c5ce7"), "use": "Splat!"},
	{"id": "bubble_bomb", "cat": "Booms", "name": "Bubble Bomb", "desc": "Traps things in floaty bubbles.", "shape": "circle", "r": 17, "mass": 0.8, "bounce": 0.3, "fric": 0.7, "color": Color("74d7ff"), "use": "Pop!"},
	{"id": "glue_bomb", "cat": "Booms", "name": "Glue Bomb", "desc": "Sticks everything nearby together.", "shape": "circle", "r": 17, "mass": 1.0, "bounce": 0.1, "fric": 0.9, "color": Color("fdcb6e"), "use": "Splat!"},
	{"id": "freeze_bomb", "cat": "Booms", "name": "Freeze Bomb", "desc": "Freezes things right where they are.", "shape": "circle", "r": 17, "mass": 1.0, "bounce": 0.2, "fric": 0.5, "color": Color("a5f3ff"), "use": "Freeze!"},
	{"id": "boom_barrel", "cat": "Booms", "name": "Boom Barrel", "desc": "KA-BOOM! Sends everything flying.", "shape": "box", "w": 40, "h": 52, "mass": 3.0, "bounce": 0.1, "fric": 0.8, "color": Color("e84118"), "use": "Boom!"},
	{"id": "mega_boom", "cat": "Booms", "name": "Mega Boom", "desc": "The biggest boom of all.", "shape": "circle", "r": 30, "mass": 6.0, "bounce": 0.1, "fric": 0.8, "color": Color("2f3542"), "use": "BOOM!"},

	# Rides (built from several parts)
	{"id": "go_kart", "cat": "Rides", "name": "Go-Kart", "desc": "Zoom zoom! Use to drive.", "build": "car", "shape": "box", "w": 110, "h": 22, "mass": 6.0, "bounce": 0.1, "fric": 0.6, "color": Color("ff4757"), "power": "use", "use": "Drive", "metal": true},
	{"id": "monster_truck", "cat": "Rides", "name": "Monster Truck", "desc": "Huge wheels. Climbs anything.", "build": "car", "shape": "box", "w": 140, "h": 34, "mass": 12.0, "bounce": 0.1, "fric": 0.6, "color": Color("2ed573"), "power": "use", "use": "Drive", "metal": true},
	{"id": "balloon", "cat": "Rides", "name": "Balloon", "desc": "Floats up. Tie things to it with Rope!", "shape": "circle", "r": 24, "mass": 0.2, "bounce": 0.3, "fric": 0.5, "color": Color("ff6b9a"), "floaty": true, "lift": 900.0},
	{"id": "hot_air", "cat": "Rides", "name": "Hot Air Balloon", "desc": "A basket that floats up and away.", "build": "hot_air", "shape": "box", "w": 70, "h": 40, "mass": 2.0, "bounce": 0.1, "fric": 0.8, "color": Color("c8814a"), "floaty": true},
	{"id": "saucer", "cat": "Rides", "name": "Hover Saucer", "desc": "Hovers in the air. Use for a tractor beam!", "shape": "box", "w": 110, "h": 30, "mass": 4.0, "bounce": 0.2, "fric": 0.6, "color": Color("a4b0be"), "use": "Beam", "metal": true},
	{"id": "boat", "cat": "Rides", "name": "Sail Boat", "desc": "Floats and sails on water.", "build": "boat", "shape": "box", "w": 130, "h": 26, "mass": 4.0, "bounce": 0.1, "fric": 0.6, "color": Color("e17055"), "floaty": true},

	# Weapons: drop one on a person (or use Give) and they'll fight with it
	{"id": "sword", "cat": "Weapons", "name": "Sword", "desc": "A trusty sword.", "shape": "box", "w": 62, "h": 8, "mass": 1.4, "bounce": 0.1, "fric": 0.5, "color": Color("dfe6e9"), "metal": true,
		"weapon": {"type": "melee", "dmg": 30.0, "reach": 64.0, "rate": 0.6, "knock": 320.0, "sound": "slash"}},
	{"id": "katana", "cat": "Weapons", "name": "Katana", "desc": "Fast and sharp.", "shape": "box", "w": 66, "h": 6, "mass": 1.0, "bounce": 0.1, "fric": 0.5, "color": Color("f5f6fa"), "metal": true,
		"weapon": {"type": "melee", "dmg": 24.0, "reach": 66.0, "rate": 0.38, "knock": 220.0, "sound": "slash"}},
	{"id": "axe", "cat": "Weapons", "name": "Battle Axe", "desc": "Big chops.", "shape": "box", "w": 58, "h": 10, "mass": 2.2, "bounce": 0.1, "fric": 0.6, "color": Color("b2bec3"), "metal": true,
		"weapon": {"type": "melee", "dmg": 38.0, "reach": 60.0, "rate": 0.85, "knock": 480.0, "sound": "slash"}},
	{"id": "spear", "cat": "Weapons", "name": "Spear", "desc": "Pokes from far away.", "shape": "box", "w": 100, "h": 6, "mass": 1.4, "bounce": 0.1, "fric": 0.6, "color": Color("c98a48"),
		"weapon": {"type": "melee", "dmg": 24.0, "reach": 100.0, "rate": 0.7, "knock": 280.0, "sound": "slash"}},
	{"id": "hammer", "cat": "Weapons", "name": "War Hammer", "desc": "BONK! Sends people flying.", "shape": "box", "w": 64, "h": 12, "mass": 3.5, "bounce": 0.1, "fric": 0.6, "color": Color("636e72"), "metal": true,
		"weapon": {"type": "melee", "dmg": 42.0, "reach": 62.0, "rate": 1.0, "knock": 950.0, "sound": "bonk"}},
	{"id": "club", "cat": "Weapons", "name": "Club", "desc": "A big wooden club.", "shape": "box", "w": 52, "h": 12, "mass": 1.6, "bounce": 0.15, "fric": 0.7, "color": Color("a0703c"),
		"weapon": {"type": "melee", "dmg": 20.0, "reach": 54.0, "rate": 0.55, "knock": 420.0, "sound": "bonk"}},
	{"id": "laser_sword", "cat": "Weapons", "name": "Laser Sword", "desc": "Hums and glows.", "shape": "box", "w": 66, "h": 6, "mass": 0.8, "bounce": 0.1, "fric": 0.5, "color": Color("4fc3ff"),
		"weapon": {"type": "melee", "dmg": 34.0, "reach": 68.0, "rate": 0.45, "knock": 260.0, "sound": "gun_laser", "glow": true}},
	{"id": "pistol", "cat": "Weapons", "name": "Pistol", "desc": "Pew pew.", "shape": "box", "w": 30, "h": 14, "mass": 0.8, "bounce": 0.1, "fric": 0.6, "color": Color("2d3436"), "metal": true,
		"weapon": {"type": "gun", "dmg": 16.0, "range": 700.0, "rate": 0.45, "spread": 0.06, "knock": 120.0, "sound": "gun_pistol"}},
	{"id": "rifle", "cat": "Weapons", "name": "Rifle", "desc": "Accurate and strong.", "shape": "box", "w": 66, "h": 12, "mass": 2.4, "bounce": 0.1, "fric": 0.6, "color": Color("6d4c2e"), "metal": true,
		"weapon": {"type": "gun", "dmg": 24.0, "range": 950.0, "rate": 0.55, "spread": 0.03, "knock": 180.0, "sound": "gun_rifle"}},
	{"id": "shotgun", "cat": "Weapons", "name": "Shotgun", "desc": "Close-range blast.", "shape": "box", "w": 60, "h": 12, "mass": 2.6, "bounce": 0.1, "fric": 0.6, "color": Color("4a3728"), "metal": true,
		"weapon": {"type": "gun", "dmg": 11.0, "pellets": 6, "range": 460.0, "rate": 0.95, "spread": 0.22, "knock": 120.0, "sound": "gun_shotgun"}},
	{"id": "mg", "cat": "Weapons", "name": "Machine Gun", "desc": "Rat-a-tat-tat!", "shape": "box", "w": 72, "h": 16, "mass": 4.0, "bounce": 0.1, "fric": 0.6, "color": Color("2d3436"), "metal": true,
		"weapon": {"type": "gun", "dmg": 9.0, "range": 850.0, "rate": 0.09, "spread": 0.08, "knock": 60.0, "sound": "gun_mg", "burst": 14, "reload": 1.6}},
	{"id": "sniper", "cat": "Weapons", "name": "Sniper Rifle", "desc": "Hits from across the map.", "shape": "box", "w": 92, "h": 10, "mass": 3.0, "bounce": 0.1, "fric": 0.6, "color": Color("3b5e3b"), "metal": true,
		"weapon": {"type": "gun", "dmg": 70.0, "range": 1700.0, "rate": 2.0, "spread": 0.006, "knock": 420.0, "sound": "gun_sniper"}},
	{"id": "laser_gun", "cat": "Weapons", "name": "Laser Blaster", "desc": "Zap zap!", "shape": "box", "w": 46, "h": 14, "mass": 1.2, "bounce": 0.1, "fric": 0.6, "color": Color("a29bfe"), "metal": true,
		"weapon": {"type": "gun", "dmg": 20.0, "range": 1000.0, "rate": 0.28, "spread": 0.01, "knock": 140.0, "sound": "gun_laser", "laser": true}},
	{"id": "bazooka", "cat": "Weapons", "name": "Bazooka", "desc": "Fires rockets that go boom.", "shape": "box", "w": 72, "h": 16, "mass": 3.5, "bounce": 0.1, "fric": 0.6, "color": Color("556b2f"), "metal": true,
		"weapon": {"type": "launcher", "range": 1100.0, "rate": 2.4, "spread": 0.04, "sound": "bazooka"}},
	{"id": "bow", "cat": "Weapons", "name": "Bow", "desc": "Shoots arrows in an arc.", "shape": "box", "w": 14, "h": 64, "mass": 0.6, "bounce": 0.1, "fric": 0.6, "color": Color("8b5a2b"),
		"weapon": {"type": "bow", "dmg": 30.0, "range": 1000.0, "rate": 1.1, "spread": 0.03, "sound": "bow"}},
	{"id": "flamethrower", "cat": "Weapons", "name": "Flamethrower", "desc": "Whoosh! Sets things on fire.", "shape": "box", "w": 62, "h": 16, "mass": 3.0, "bounce": 0.1, "fric": 0.6, "color": Color("c0392b"), "metal": true,
		"weapon": {"type": "flame", "dmg": 40.0, "range": 230.0, "rate": 0.06, "sound": "flame"}},
	{"id": "grenades", "cat": "Weapons", "name": "Grenade Bag", "desc": "Throws grenades forever.", "shape": "box", "w": 26, "h": 22, "mass": 1.2, "bounce": 0.1, "fric": 0.7, "color": Color("556b2f"),
		"weapon": {"type": "throw", "range": 650.0, "rate": 2.2, "spread": 0.05, "sound": "pin"}},

	# Armor: drop it on a person to put it on
	{"id": "helmet", "cat": "Armor", "name": "Helmet", "desc": "Protects your head.", "shape": "box", "w": 28, "h": 16, "mass": 0.8, "bounce": 0.2, "fric": 0.6, "color": Color("556b2f"), "metal": true, "armor": {"slot": "helmet", "value": 0.15}},
	{"id": "body_armor", "cat": "Armor", "name": "Body Armor", "desc": "A tough vest.", "shape": "box", "w": 30, "h": 36, "mass": 2.0, "bounce": 0.1, "fric": 0.6, "color": Color("7f8c8d"), "metal": true, "armor": {"slot": "body", "value": 0.3}},
	{"id": "shield", "cat": "Armor", "name": "Shield", "desc": "Blocks hits from the front.", "shape": "box", "w": 10, "h": 58, "mass": 2.0, "bounce": 0.2, "fric": 0.6, "color": Color("c0392b"), "metal": true, "armor": {"slot": "shield", "value": 0.25}},

	# Combat booms
	{"id": "grenade", "cat": "Booms", "name": "Grenade", "desc": "Pull the pin… throw!", "shape": "circle", "r": 9, "mass": 0.6, "bounce": 0.3, "fric": 0.7, "color": Color("556b2f"), "use": "Pull pin", "metal": true, "explode": {"r": 170.0, "power": 1100.0, "dmg": 55.0}},
	{"id": "dynamite", "cat": "Booms", "name": "Dynamite", "desc": "A long fuse and a big bang.", "shape": "box", "w": 14, "h": 44, "mass": 0.8, "bounce": 0.1, "fric": 0.7, "color": Color("e74c3c"), "use": "Light", "explode": {"r": 220.0, "power": 1400.0, "dmg": 70.0}},
	{"id": "c4", "cat": "Booms", "name": "C4", "desc": "Stick it anywhere. Press 💣 Detonate!", "shape": "box", "w": 34, "h": 18, "mass": 1.0, "bounce": 0.0, "fric": 1.0, "color": Color("dcc69a"), "use": "Detonate", "explode": {"r": 250.0, "power": 1600.0, "dmg": 80.0}},
	{"id": "landmine", "cat": "Booms", "name": "Landmine", "desc": "Goes off when stepped on.", "shape": "box", "w": 40, "h": 10, "mass": 2.0, "bounce": 0.0, "fric": 1.0, "color": Color("4b5320"), "metal": true, "explode": {"r": 190.0, "power": 1400.0, "dmg": 70.0}},
	{"id": "barrel", "cat": "Booms", "name": "Explosive Barrel", "desc": "Shoot it, burn it… BOOM.", "shape": "box", "w": 40, "h": 54, "mass": 4.0, "bounce": 0.1, "fric": 0.8, "color": Color("d35400"), "metal": true, "explode": {"r": 230.0, "power": 1500.0, "dmg": 65.0}},
	{"id": "cluster", "cat": "Booms", "name": "Cluster Bomb", "desc": "One boom becomes many.", "shape": "circle", "r": 18, "mass": 2.0, "bounce": 0.2, "fric": 0.7, "color": Color("34495e"), "use": "Light", "metal": true, "explode": {"r": 180.0, "power": 1000.0, "dmg": 45.0}},
	{"id": "napalm", "cat": "Booms", "name": "Napalm", "desc": "A burst of fire that keeps burning.", "shape": "circle", "r": 16, "mass": 1.2, "bounce": 0.2, "fric": 0.7, "color": Color("e67e22"), "use": "Light", "explode": {"r": 200.0, "power": 600.0, "dmg": 25.0}},
	{"id": "acid_bomb", "cat": "Booms", "name": "Acid Bomb", "desc": "Splashes fizzy green acid.", "shape": "circle", "r": 16, "mass": 1.2, "bounce": 0.2, "fric": 0.7, "color": Color("7bed9f"), "use": "Light", "explode": {"r": 190.0, "power": 500.0, "dmg": 20.0}},
	{"id": "nuke", "cat": "Booms", "name": "Nuke", "desc": "The biggest boom there is. Stand back!", "shape": "box", "w": 90, "h": 40, "mass": 12.0, "bounce": 0.05, "fric": 0.8, "color": Color("f1c40f"), "use": "Launch", "metal": true, "explode": {"r": 1100.0, "power": 2300.0, "dmg": 400.0}},

	# Hazards: a tub of something you don't want to fall into
	{"id": "lava_tub", "cat": "Hazards", "name": "Lava Pit", "desc": "Hot hot hot! Burns anything that falls in.", "tub": "lava", "shape": "box", "w": 260, "h": 120, "color": Color("e74c3c")},
	{"id": "acid_vat", "cat": "Hazards", "name": "Acid Vat", "desc": "Fizzy green acid dissolves things.", "tub": "acid", "shape": "box", "w": 240, "h": 130, "color": Color("7bed9f")},
	{"id": "water_tub", "cat": "Hazards", "name": "Water Tank", "desc": "A tank of water to splash in.", "tub": "water", "shape": "box", "w": 260, "h": 130, "color": Color("4aa8ff")},
]

# --------------------------------------------------------------- Fighters
const TEAMS := {
	"red": {"name": "Red", "color": Color("e74c3c")},
	"blue": {"name": "Blue", "color": Color("3d8bfd")},
	"green": {"name": "Green", "color": Color("27ae60")},
	"yellow": {"name": "Yellow", "color": Color("f1c40f")},
	"wild": {"name": "Wild", "color": Color("95a5a6")},
}
const TEAM_ORDER := ["red", "blue", "green", "yellow", "wild"]

const PERSONALITIES := [
	{"id": "attack", "name": "Attack", "emoji": "⚔️", "desc": "Charges the nearest enemy."},
	{"id": "defend", "name": "Defend", "emoji": "🛡️", "desc": "Guards its spot and fights anyone who comes close."},
	{"id": "ranged", "name": "Ranged", "emoji": "🎯", "desc": "Keeps its distance and shoots."},
	{"id": "berserk", "name": "Berserk", "emoji": "😡", "desc": "Fast and fearless. Always charges."},
	{"id": "coward", "name": "Coward", "emoji": "😱", "desc": "Runs away when it gets hurt."},
	{"id": "peaceful", "name": "Peaceful", "emoji": "🌼", "desc": "Just wanders around. Never fights."},
]

## People, animals and dinosaurs. Spawn ids are "f:<id>".
## kind: person | beast.  For beasts: body (w, h), legs (length), biped, neck, head, tail, attack.
const FIGHTERS := {
	"stick": {"cat": "People", "name": "Stick Figure", "desc": "Fights with fists. Give it a weapon!", "hp": 100.0, "speed": 160.0, "pers": "attack", "skin": Color("f6d7b0")},
	"soldier": {"cat": "People", "name": "Soldier", "desc": "Rifle and helmet.", "hp": 110.0, "speed": 150.0, "weapon": "rifle", "helmet": "army", "armor": 0.1, "pers": "ranged", "skin": Color("e0b48c")},
	"knight": {"cat": "People", "name": "Knight", "desc": "Sword, shield and shiny armor.", "hp": 140.0, "speed": 120.0, "weapon": "sword", "helmet": "knight", "armor": 0.35, "shield": true, "pers": "attack", "skin": Color("f6d7b0")},
	"viking": {"cat": "People", "name": "Viking", "desc": "Battle axe and horned helmet.", "hp": 125.0, "speed": 150.0, "weapon": "axe", "helmet": "viking", "armor": 0.1, "pers": "berserk", "skin": Color("f3c9a3"), "beard": Color("d35400")},
	"archer": {"cat": "People", "name": "Archer", "desc": "Shoots arrows from afar.", "hp": 90.0, "speed": 160.0, "weapon": "bow", "helmet": "hood", "pers": "ranged", "skin": Color("f6d7b0")},
	"sniper": {"cat": "People", "name": "Sniper", "desc": "Hits from across the map.", "hp": 90.0, "speed": 140.0, "weapon": "sniper", "helmet": "beret", "pers": "ranged", "skin": Color("c68e65")},
	"rocketeer": {"cat": "People", "name": "Rocketeer", "desc": "Bazooka! Blows things up.", "hp": 110.0, "speed": 135.0, "weapon": "bazooka", "helmet": "army", "armor": 0.1, "pers": "ranged", "skin": Color("e0b48c")},
	"grenadier": {"cat": "People", "name": "Grenadier", "desc": "Throws grenades in big arcs.", "hp": 110.0, "speed": 145.0, "weapon": "grenades", "helmet": "army", "pers": "ranged", "skin": Color("8d5524")},
	"gunner": {"cat": "People", "name": "Gunner", "desc": "Machine gun. Rat-a-tat!", "hp": 130.0, "speed": 120.0, "weapon": "mg", "helmet": "army", "armor": 0.2, "pers": "ranged", "skin": Color("f3c9a3")},
	"medic": {"cat": "People", "name": "Medic", "desc": "Heals hurt teammates.", "hp": 100.0, "speed": 165.0, "weapon": "pistol", "helmet": "medic", "pers": "defend", "heals": true, "skin": Color("f6d7b0")},
	"ninja": {"cat": "People", "name": "Ninja", "desc": "Super fast with a katana.", "hp": 90.0, "speed": 250.0, "weapon": "katana", "helmet": "ninja", "pers": "berserk", "skin": Color("f3c9a3"), "jumpy": true},
	"giant": {"cat": "People", "name": "Giant", "desc": "Huge and strong. War hammer!", "hp": 360.0, "speed": 110.0, "weapon": "hammer", "scale": 1.6, "armor": 0.1, "pers": "attack", "skin": Color("c68e65")},

	"dog": {"cat": "Animals", "kind": "beast", "name": "Dog", "desc": "Loyal and bitey.", "hp": 70.0, "speed": 260.0, "pers": "attack", "team": "wild",
		"body": Vector2(54, 24), "legs": 22.0, "neck": 10.0, "head": 13.0, "tail": 20.0, "color": Color("c8814a"), "attack": "bite", "dmg": 14.0, "reach": 34.0, "rate": 0.6, "voice": "bark", "ears": "flop"},
	"wolf": {"cat": "Animals", "kind": "beast", "name": "Wolf", "desc": "Hunts in packs.", "hp": 85.0, "speed": 280.0, "pers": "attack", "team": "wild",
		"body": Vector2(62, 26), "legs": 26.0, "neck": 12.0, "head": 14.0, "tail": 30.0, "color": Color("7f8c8d"), "attack": "bite", "dmg": 18.0, "reach": 38.0, "rate": 0.6, "voice": "growl", "ears": "point"},
	"bear": {"cat": "Animals", "kind": "beast", "name": "Bear", "desc": "Big, strong and grumpy.", "hp": 260.0, "speed": 170.0, "pers": "defend", "team": "wild",
		"body": Vector2(96, 52), "legs": 28.0, "neck": 6.0, "head": 22.0, "tail": 6.0, "color": Color("6d4c41"), "attack": "maul", "dmg": 34.0, "reach": 52.0, "rate": 1.0, "knock": 700.0, "voice": "growl", "ears": "round"},
	"bull": {"cat": "Animals", "kind": "beast", "name": "Bull", "desc": "Charges and launches things.", "hp": 240.0, "speed": 230.0, "pers": "attack", "team": "wild",
		"body": Vector2(100, 46), "legs": 32.0, "neck": 6.0, "head": 20.0, "tail": 24.0, "color": Color("4e342e"), "attack": "charge", "dmg": 30.0, "reach": 40.0, "rate": 1.4, "knock": 1100.0, "voice": "moo", "horns": true},
	"elephant": {"cat": "Animals", "kind": "beast", "name": "Elephant", "desc": "Huge. Stomps the ground.", "hp": 520.0, "speed": 110.0, "pers": "defend", "team": "wild",
		"body": Vector2(150, 90), "legs": 52.0, "neck": 4.0, "head": 36.0, "tail": 22.0, "color": Color("95a5a6"), "attack": "stomp", "dmg": 40.0, "reach": 120.0, "rate": 2.0, "knock": 1000.0, "voice": "trumpet", "trunk": true},
	"chicken": {"cat": "Animals", "kind": "beast", "name": "Chicken", "desc": "Bawk! Runs around.", "hp": 30.0, "speed": 200.0, "pers": "peaceful", "team": "wild", "biped": true,
		"body": Vector2(26, 22), "legs": 16.0, "neck": 8.0, "head": 9.0, "tail": 8.0, "color": Color("ffffff"), "attack": "peck", "dmg": 4.0, "reach": 20.0, "rate": 0.5, "voice": "cluck", "comb": true},

	"trex": {"cat": "Dinos", "kind": "beast", "name": "T-Rex", "desc": "The king! Big bites and a mighty roar.", "hp": 700.0, "speed": 170.0, "pers": "attack", "team": "wild", "biped": true,
		"body": Vector2(170, 76), "legs": 70.0, "neck": 30.0, "head": 44.0, "tail": 120.0, "color": Color("5d8233"), "attack": "bite", "dmg": 60.0, "reach": 90.0, "rate": 1.2, "knock": 1300.0, "voice": "roar", "tiny_arms": true},
	"raptor": {"cat": "Dinos", "kind": "beast", "name": "Raptor", "desc": "Fast and clever.", "hp": 110.0, "speed": 330.0, "pers": "berserk", "team": "wild", "biped": true,
		"body": Vector2(70, 28), "legs": 38.0, "neck": 18.0, "head": 18.0, "tail": 60.0, "color": Color("a1887f"), "attack": "bite", "dmg": 20.0, "reach": 40.0, "rate": 0.5, "voice": "screech", "jumpy": true},
	"triceratops": {"cat": "Dinos", "kind": "beast", "name": "Triceratops", "desc": "Three horns. Charges!", "hp": 560.0, "speed": 160.0, "pers": "defend", "team": "wild",
		"body": Vector2(160, 72), "legs": 40.0, "neck": 8.0, "head": 40.0, "tail": 50.0, "color": Color("8e6e53"), "attack": "charge", "dmg": 45.0, "reach": 60.0, "rate": 1.6, "knock": 1400.0, "voice": "growl", "frill": true},
	"stego": {"cat": "Dinos", "kind": "beast", "name": "Stegosaurus", "desc": "Spiky tail swipes.", "hp": 480.0, "speed": 120.0, "pers": "defend", "team": "wild",
		"body": Vector2(170, 70), "legs": 44.0, "neck": 14.0, "head": 18.0, "tail": 90.0, "color": Color("7cb342"), "attack": "tail", "dmg": 40.0, "reach": 110.0, "rate": 1.4, "knock": 1100.0, "voice": "growl", "plates": true},
	"brachio": {"cat": "Dinos", "kind": "beast", "name": "Brachiosaurus", "desc": "So tall! Gentle, but stomps when angry.", "hp": 1100.0, "speed": 90.0, "pers": "peaceful", "team": "wild",
		"body": Vector2(200, 100), "legs": 90.0, "neck": 170.0, "head": 24.0, "tail": 120.0, "color": Color("80cbc4"), "attack": "stomp", "dmg": 50.0, "reach": 150.0, "rate": 2.5, "knock": 1300.0, "voice": "trumpet", "long_neck": true},
	"ptero": {"cat": "Dinos", "kind": "beast", "name": "Pterodactyl", "desc": "Flies and swoops down.", "hp": 90.0, "speed": 280.0, "pers": "attack", "team": "wild", "flies": true, "biped": true,
		"body": Vector2(50, 22), "legs": 16.0, "neck": 16.0, "head": 22.0, "tail": 10.0, "color": Color("e67e22"), "attack": "peck", "dmg": 18.0, "reach": 44.0, "rate": 0.9, "knock": 500.0, "voice": "screech", "wings": true},
}

## Platforms you can place (spawn ids "plat:<id>"); the Platform tool draws your own.
const PLATFORMS := [
	{"id": "small", "name": "Small Platform", "desc": "A ledge to stand on.", "w": 140, "h": 20, "style": "wood"},
	{"id": "big", "name": "Big Platform", "desc": "A big wide floor.", "w": 320, "h": 26, "style": "metal"},
	{"id": "wall", "name": "Wall", "desc": "Blocks the way.", "w": 26, "h": 200, "style": "stone"},
	{"id": "tower", "name": "Tower", "desc": "A tall lookout for snipers.", "w": 120, "h": 300, "style": "stone"},
	{"id": "bunker", "name": "Bunker", "desc": "A safe place to hide.", "w": 260, "h": 120, "style": "concrete"},
	{"id": "bridge", "name": "Bridge", "desc": "A long thin walkway.", "w": 480, "h": 14, "style": "wood"},
]

## Contraptions: several toys glued, hinged and wired together.
const BUILDS := [
	{"id": "seesaw", "name": "See-Saw", "desc": "Up and down!"},
	{"id": "catapult", "name": "Catapult", "desc": "Flip the switch to fling!"},
	{"id": "ferris", "name": "Spinny Wheel", "desc": "A motor wheel with seats."},
	{"id": "rocket_cart", "name": "Rocket Cart", "desc": "A go-kart with rockets. Flip the switch!"},
	{"id": "domino", "name": "Domino Run", "desc": "Push the first one…"},
	{"id": "lamp_show", "name": "Light Show", "desc": "A timer blinking three lamps."},
	# 🔌 Battle Trap Builds: ready-made wired traps
	{"id": "trap_minefield", "name": "Minefield", "desc": "Step on the plate and every mine wired to it goes BOOM!"},
	{"id": "disarm_gate", "name": "Disarm Gate", "desc": "Walk under the magnet and it yanks swords and guns away!"},
	{"id": "ufo_abductor", "name": "UFO Abductor", "desc": "Step on the plate and the saucer beams you up!"},
]

const CATEGORY_ORDER := ["People", "Animals", "Dinos", "Weapons", "Armor", "Booms", "Hazards", "Platforms", "Wigglies", "Balls", "Blocks", "Machines", "Rides", "Builds"]
const CATEGORY_EMOJI := {
	"People": "🧍", "Animals": "🐻", "Dinos": "🦖", "Weapons": "⚔️", "Armor": "🛡️", "Hazards": "🌋", "Platforms": "🏗️",
	"Wigglies": "🫧", "Balls": "⚽", "Blocks": "🧱", "Machines": "⚙️", "Booms": "💣", "Rides": "🚗", "Builds": "🛠️", "Recent": "🕘",
}
const FIGHTER_CATS := ["People", "Animals", "Dinos"]

# ------------------------------------------------------------------ Worlds
const WORLDS := [
	{"id": "meadow", "name": "Sunny Meadow", "emoji": "🌼", "desc": "Rolling hills, a pond and lots of flowers."},
	{"id": "toyroom", "name": "Toy Room", "emoji": "🧸", "desc": "A giant playroom with shelves to climb."},
	{"id": "candy", "name": "Candy Canyon", "emoji": "🍭", "desc": "Bouncy gumdrop hills. Everything boings!"},
	{"id": "frosty", "name": "Frosty Peaks", "emoji": "❄️", "desc": "Snowy slopes made for sliding."},
	{"id": "lagoon", "name": "Splash Lagoon", "emoji": "🏝️", "desc": "A sandy beach and a big blue sea."},
	{"id": "moon", "name": "Moon Garden", "emoji": "🌙", "desc": "Low gravity under glowing stars."},
	{"id": "clouds", "name": "Cloud Kingdom", "emoji": "☁️", "desc": "Floating islands high in the sky."},
	{"id": "battle", "name": "Battle Valley", "emoji": "🏰", "desc": "Two forts across a valley. Pick a side!"},
	{"id": "factory", "name": "Acid Factory", "emoji": "🧪", "desc": "Bubbling acid vats and conveyor belts."},
	{"id": "volcano", "name": "Volcano", "emoji": "🌋", "desc": "A lava lake and an erupting volcano."},
	{"id": "dino", "name": "Dino Valley", "emoji": "🦕", "desc": "Ferns, a river and lots of dinosaurs."},
	{"id": "canvas", "name": "Blank Canvas", "emoji": "📐", "desc": "A flat, empty space for big builds."},
]

# ------------------------------------------------------------------- Magic
const MAGIC := [
	{"id": "party", "name": "Party Time", "emoji": "🎉", "desc": "Confetti and dancing Wigglies."},
	{"id": "ball_rain", "name": "Ball Rain", "emoji": "⚽", "desc": "Balls fall from the sky."},
	{"id": "wind", "name": "Big Wind", "emoji": "🌬️", "desc": "A gust blows everything sideways."},
	{"id": "rain", "name": "Rain Shower", "emoji": "🌧️", "desc": "Pitter-patter, everything gets wet."},
	{"id": "snow", "name": "Snow Day", "emoji": "🌨️", "desc": "Fluffy snow falls down."},
	{"id": "wobble", "name": "Wobble Quake", "emoji": "🫨", "desc": "The ground shakes everything up."},
	{"id": "float", "name": "Float Away", "emoji": "🎈", "desc": "Gravity turns off for a few seconds."},
	{"id": "rainbow", "name": "Rainbow Paint", "emoji": "🌈", "desc": "Paints every toy a rainbow color."},
	{"id": "airstrike", "name": "Airstrike", "emoji": "✈️", "desc": "A plane drops a line of bombs."},
	{"id": "artillery", "name": "Artillery", "emoji": "💥", "desc": "Shells rain down on the battlefield."},
	{"id": "meteors", "name": "Meteor Shower", "emoji": "☄️", "desc": "Flaming rocks fall from the sky."},
	{"id": "heal_all", "name": "Heal Everyone", "emoji": "💖", "desc": "Everyone gets back up, good as new."},
]

const GRAVITIES := [
	{"id": "normal", "name": "Normal", "g": Vector2(0, 980)},
	{"id": "moon", "name": "Moon", "g": Vector2(0, 240)},
	{"id": "zero", "name": "Zero-G", "g": Vector2.ZERO},
	{"id": "flip", "name": "Upside Down", "g": Vector2(0, -700)},
	{"id": "heavy", "name": "Heavy", "g": Vector2(0, 2000)},
]

# ---------------------------------------------------------------- Stickers
const STICKERS := [
	{"id": "hello", "emoji": "👋", "name": "Hello, Wiggly!", "desc": "Make your first Wiggly."},
	{"id": "pop", "emoji": "💥", "name": "Pop Goes the Jelly", "desc": "Pull a Wiggly so hard it splits in two."},
	{"id": "family", "emoji": "👨‍👩‍👧", "name": "Big Family", "desc": "Have 12 Wigglies at once."},
	{"id": "sky", "emoji": "🚀", "name": "Sky High", "desc": "Send a Wiggly way up into the sky."},
	{"id": "splash", "emoji": "💦", "name": "Splash!", "desc": "Drop a Wiggly in the water."},
	{"id": "tower", "emoji": "🗼", "name": "Tower Builder", "desc": "Stack blocks taller than a house."},
	{"id": "boom", "emoji": "🎆", "name": "Boom Boom Boom", "desc": "Set off 10 booms."},
	{"id": "fireworks", "emoji": "🎇", "name": "Light Up the Night", "desc": "Launch a firework at night."},
	{"id": "inventor", "emoji": "🔌", "name": "Inventor", "desc": "Wire a power source to a machine."},
	{"id": "rider", "emoji": "🏎️", "name": "Road Trip", "desc": "Drive a Go-Kart or Monster Truck."},
	{"id": "freeze", "emoji": "🧊", "name": "Chill Out", "desc": "Freeze something in mid-air."},
	{"id": "painter", "emoji": "🎨", "name": "Little Painter", "desc": "Paint 10 things."},
	{"id": "explorer", "emoji": "🗺️", "name": "Explorer", "desc": "Visit every world."},
	{"id": "special", "emoji": "✨", "name": "Show Off", "desc": "Use every Wiggly's special move."},
	{"id": "friends", "emoji": "🤝", "name": "Better Together", "desc": "Play with a friend over Wi-Fi."},
	{"id": "player", "emoji": "🎮", "name": "Hop To It", "desc": "Play as a Wiggly and jump 10 times."},
	{"id": "general", "emoji": "🎖️", "name": "General", "desc": "Win a battle with 5 or more on each team."},
	{"id": "dino", "emoji": "🦖", "name": "Jurassic", "desc": "Put a T-Rex in the playground."},
	{"id": "nuke", "emoji": "☢️", "name": "Big Bada Boom", "desc": "Set off a nuke."},
	{"id": "armory", "emoji": "🗡️", "name": "Armory", "desc": "Give 5 weapons or armor to people."},
	{"id": "builder", "emoji": "🏗️", "name": "Architect", "desc": "Draw 10 platforms."},
	{"id": "hero", "emoji": "🦸", "name": "Hero", "desc": "Play as a person and knock out 5 enemies."},
	# ⚔️ 3D Battle (it also gives General, Hero, Big Bada Boom, Boom Boom Boom and Better Together)
	{"id": "b3win", "emoji": "🏆", "name": "Victory!", "desc": "Fight a 3D Battle until one team wins."},
	{"id": "ace", "emoji": "✈️", "name": "Ace Pilot", "desc": "Fly a plane or helicopter and knock out 3 enemies."},
	{"id": "tankbuster", "emoji": "🧨", "name": "Tank Buster", "desc": "Wreck a tank with a boom, or while you play."},
	{"id": "historybuff", "emoji": "📜", "name": "History Buff", "desc": "Finish 3 different History battles."},
	{"id": "fphero", "emoji": "👀", "name": "First-Person Hero", "desc": "Win a 3D Battle while you play in first person."},
	{"id": "puzzles", "emoji": "🧩", "name": "Puzzle Master", "desc": "Solve every 3D Army Puzzle."},
]

const PAINT := [
	Color("ff5a5a"), Color("ff9f43"), Color("ffd43b"), Color("5ad66a"), Color("2ec4b6"), Color("4aa8ff"),
	Color("8c6cff"), Color("ff8fd0"), Color("ffffff"), Color("2f3542"),
]

var toy_by_id := {}
var build_by_id := {}


func _init() -> void:
	for t in TOYS:
		toy_by_id[t.id] = t
	for b in BUILDS:
		build_by_id[b.id] = b


func toy(id: String) -> Dictionary:
	return toy_by_id.get(id, {})


## Display name for anything spawnable ("w:bloop", "build:seesaw" or a toy id).
func spawn_name(id: String) -> String:
	if id.begins_with("f:"):
		return String(FIGHTERS.get(id.substr(2), {}).get("name", id))
	if id.begins_with("plat:"):
		return String(platform_def(id.substr(5)).get("name", id))
	if id.begins_with("w:"):
		return String(WIGGLIES.get(id.substr(2), {}).get("name", id))
	if id.begins_with("build:"):
		return String(build_by_id.get(id.substr(6), {}).get("name", id))
	return String(toy_by_id.get(id, {}).get("name", id))


func spawn_desc(id: String) -> String:
	if id.begins_with("f:"):
		return String(FIGHTERS.get(id.substr(2), {}).get("desc", ""))
	if id.begins_with("plat:"):
		return String(platform_def(id.substr(5)).get("desc", ""))
	if id.begins_with("w:"):
		return String(WIGGLIES.get(id.substr(2), {}).get("desc", ""))
	if id.begins_with("build:"):
		return String(build_by_id.get(id.substr(6), {}).get("desc", ""))
	return String(toy_by_id.get(id, {}).get("desc", ""))


## All spawnable ids in a category, in display order.
func ids_in(cat: String) -> Array:
	var out: Array = []
	match cat:
		"Wigglies":
			for w in WIGGLY_ORDER:
				out.append("w:" + w)
		"Builds":
			for b in BUILDS:
				out.append("build:" + String(b.id))
		"People", "Animals", "Dinos":
			for k in FIGHTERS:
				if FIGHTERS[k].cat == cat:
					out.append("f:" + String(k))
		"Platforms":
			for p in PLATFORMS:
				out.append("plat:" + String(p.id))
		_:
			for t in TOYS:
				if t.cat == cat:
					out.append(t.id)
	return out


func platform_def(id: String) -> Dictionary:
	for p in PLATFORMS:
		if p.id == id:
			return p
	return {}


func fighter(id: String) -> Dictionary:
	return FIGHTERS.get(id, {})


func team_color(team: String) -> Color:
	return TEAMS.get(team, TEAMS.wild).color


func personality(id: String) -> Dictionary:
	for p in PERSONALITIES:
		if p.id == id:
			return p
	return PERSONALITIES[0]


func world_def(id: String) -> Dictionary:
	for w in WORLDS:
		if w.id == id:
			return w
	return WORLDS[0]


func gravity_def(id: String) -> Dictionary:
	for g in GRAVITIES:
		if g.id == id:
			return g
	return GRAVITIES[0]
