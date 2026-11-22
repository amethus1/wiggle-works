class_name B3Rules
## Battle Rules: the options in the ⚙️ panel (the battle goal, gravity,
## explosion size, knockback, toughness, speed, friendly fire, reinforcements,
## time of day and weather). Values are remembered between games
## (Settings.b3_rules). The 🏁 goals are run by B3Modes.

const OPTIONS := [
	{"id": "goal", "name": "Battle goal", "icon": "🏁", "choices": [
		["last", "⚔️ Last team standing"], ["king", "👑 Defend the King"], ["hill", "🚩 King of the Hill"]]},
	{"id": "gravity", "name": "Gravity", "icon": "🌍", "choices": [
		["normal", "🌍 Normal"], ["moon", "🌙 Moon"], ["floaty", "🪐 Floaty"], ["heavy", "🪨 Heavy"]]},
	{"id": "booms", "name": "Explosions", "icon": "💥", "choices": [
		["normal", "💥 Normal"], ["big", "💥 Big"], ["mega", "☄️ MEGA"]]},
	{"id": "knock", "name": "Knockback", "icon": "💨", "choices": [
		["normal", "Normal"], ["big", "💨 Big"], ["crazy", "🌪️ Crazy"]]},
	{"id": "health", "name": "Toughness", "icon": "❤️", "choices": [
		["glass", "🥚 Fragile"], ["normal", "Normal"], ["tough", "💪 Tough"], ["super", "🦾 Super"]]},
	{"id": "speed", "name": "Fighter speed", "icon": "👟", "choices": [
		["slow", "🐌 Slow"], ["normal", "Normal"], ["fast", "⚡ Fast"]]},
	{"id": "friendly", "name": "Blasts hurt teammates", "icon": "🤝", "choices": [
		["on", "Yes"], ["off", "No"]]},
	{"id": "respawn", "name": "Reinforcements", "icon": "♾️", "choices": [
		["off", "Off"], ["on", "♾️ Endless battle"]]},
	{"id": "time", "name": "Time of day", "icon": "🌞", "choices": [
		["day", "🌞 Day"], ["sunset", "🌅 Sunset"], ["night", "🌙 Night"]]},
	{"id": "weather", "name": "Weather", "icon": "🌦️", "choices": [
		["clear", "☀️ Clear"], ["rain", "🌧️ Rain"], ["snow", "🌨️ Snow"]]},
	{"id": "shake", "name": "Screen shake", "icon": "📳", "choices": [
		["off", "Off"], ["little", "A little"], ["lots", "📳 Lots"]]},
]

const DEFAULTS := {"goal": "last", "gravity": "normal", "booms": "normal", "knock": "normal", "health": "normal", "speed": "normal",
	"friendly": "on", "respawn": "off", "time": "day", "weather": "clear", "shake": "little"}

const TIPS := {
	"goal": "How to win: knock everyone out, keep your King safe, or hold the glowing circle",
	"gravity": "Moon and Floaty gravity make everything fly much higher",
	"booms": "Bigger blasts, bigger fireballs",
	"knock": "How far fighters fly when they get hit",
	"health": "Fragile: one hit and they're down. Super: they take a LOT",
	"speed": "How fast fighters run",
	"friendly": "Can grenades and rockets knock over your own team?",
	"respawn": "Knocked-out fighters come back where you put them, so the battle never ends",
	"time": "Night makes explosions and gunfire light everything up",
	"weather": "Rain or snow over the battlefield",
	"shake": "How much the screen wobbles when things blow up",
}

static var values := {}


static func value(id: String) -> String:
	if values.is_empty():
		load_from_settings()
	return String(values.get(id, DEFAULTS.get(id, "")))


static func set_value(id: String, v: String) -> void:
	if values.is_empty():
		load_from_settings()
	values[id] = v
	Settings.b3_rules = values.duplicate()
	Settings.save()


static func load_from_settings() -> void:
	values = DEFAULTS.duplicate()
	for k in Settings.b3_rules:
		if DEFAULTS.has(k):
			values[k] = String(Settings.b3_rules[k])


## Everything back to normal, except Screen shake (that's how you like to watch, not a rule).
static func reset() -> void:
	var sh := value("shake")
	values = DEFAULTS.duplicate()
	values["shake"] = sh
	Settings.b3_rules = values.duplicate()
	Settings.save()


static func is_default() -> bool:
	for k in DEFAULTS:
		if k != "shake" and value(k) != String(DEFAULTS[k]):
			return false
	return true


# ------------------------------------------------------------- numbers
static func gravity_k() -> float:
	return float({"normal": 1.0, "moon": 0.32, "floaty": 0.12, "heavy": 2.0}.get(value("gravity"), 1.0))


## Explosion radius and push.
static func boom_r() -> float:
	return float({"normal": 1.0, "big": 1.5, "mega": 2.3}.get(value("booms"), 1.0))


static func boom_power() -> float:
	return float({"normal": 1.0, "big": 1.35, "mega": 1.9}.get(value("booms"), 1.0))


static func knock_k() -> float:
	return float({"normal": 1.0, "big": 1.7, "crazy": 3.0}.get(value("knock"), 1.0))


## Damage taken is divided by this.
static func toughness() -> float:
	return float({"glass": 0.25, "normal": 1.0, "tough": 2.5, "super": 6.0}.get(value("health"), 1.0))


static func speed_k() -> float:
	return float({"slow": 0.55, "normal": 1.0, "fast": 1.6}.get(value("speed"), 1.0))


## How much the camera shakes (0 = never).
static func shake_k() -> float:
	return float({"off": 0.0, "little": 0.3, "lots": 1.0}.get(value("shake"), 0.3))


static func friendly_fire() -> bool:
	return value("friendly") != "off"


static func respawn() -> bool:
	return value("respawn") == "on"


## 🏁 "last" (last team standing), "king" (👑 Defend the King) or "hill" (🚩 King of the Hill).
static func goal() -> String:
	return value("goal")
