class_name B3Surprise
## 🎲 Surprise Battle: a random map, 2–4 armies of equal strength around the
## middle, some buildings, barrels, mines and pools, then the fight starts.

const THEMES := ["soldiers", "mixed", "beasts", "dinos", "medieval", "everything"]
const THEME_NAMES := {
	"soldiers": "Army vs army", "mixed": "Mixed armies", "beasts": "People and animals",
	"dinos": "Dinosaur attack", "medieval": "Knights and vikings", "everything": "Total chaos",
}


static func run(b, seed_v := 0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	if b.tools:
		b.tools.stop_playing()
	b.set_fighting(false)
	var maps: Array = B3Defs.MAP_ORDER
	b.load_map(String(maps[rng.randi() % maps.size()]))
	b.apply_rules()
	var theme := String(THEMES[rng.randi() % THEMES.size()])
	var r := rng.randf()
	var n_teams := 2 if r < 0.6 else (3 if r < 0.85 else 4)
	var narrow: bool = b.map_id == "pass"     # the pass is a long, thin valley: two armies, one at each end
	if narrow:
		n_teams = 2
	var teams: Array = ["red", "blue", "green", "yellow"]
	_shuffle(teams, rng)
	teams.resize(n_teams)
	var budget := rng.randi_range(9, 18) if n_teams <= 2 else rng.randi_range(7, 13)
	var pool := _pool(theme)
	var spin := 0.0 if narrow else rng.randf() * TAU
	var ring := 15.0 + n_teams * 2.0
	for i in n_teams:
		var team := String(teams[i])
		var ang := spin + TAU * i / n_teams
		var dir := Vector3(cos(ang), 0, sin(ang))
		var base := dir * ring
		_army(b, rng, team, base, -dir, pool, budget)
		# a little cover for each side
		if rng.randf() < 0.7:
			var cover := String(["wall", "sandbags", "sandbags", "crates", "bunker"][rng.randi() % 5])
			var side := Vector3(-dir.z, 0, dir.x)
			b.spawn_struct(cover, base - dir * 5.5 + side * rng.randf_range(-3, 3), atan2(side.x, side.z), 8.0)
		if rng.randf() < 0.35:
			b.spawn_struct("tower", base + dir * 4.0 + Vector3(-dir.z, 0, dir.x) * 5.0, ang)
	if theme == "dinos" or (theme == "everything" and rng.randf() < 0.5):
		var dinos: Array = B3Defs.UNIT_ORDER.get("dinos", [])
		for k in rng.randi_range(2, 4):
			var dk := String(dinos[rng.randi() % dinos.size()])
			b.spawn_unit(dk, "wild", Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)), "attack")
	# the middle: barrels, mines and maybe a pool
	for k in rng.randi_range(0, 6):
		var p := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		b.spawn_prop("xbarrel" if rng.randf() < 0.7 else "mine", Vector3(p.x, b.surface_y(Vector3(p.x, 60, p.z)), p.z))
	if rng.randf() < 0.45:
		var hz := "lava" if rng.randf() < 0.6 else "acid"
		var hp := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
		if b.hazard_at(hp, 2.0) == null:
			b.spawn_hazard(hz, hp, rng.randf_range(2.5, 4.0))
	b.cam.fit(Vector3.ZERO, ring * 2.1 + 6.0)
	if b.ui:
		var md: Dictionary = B3Defs.MAPS[b.map_id]
		var names: Array = []
		for t in teams:
			names.append(String(B3Defs.TEAM[t].icon))
		b.ui.toast("🎲 Surprise!  %s on %s %s:  %s" % [THEME_NAMES[theme], md.icon, md.name, " vs ".join(names)])
		b.ui.refresh()
	b.later(2.0, func():
		if not b.fighting:
			b.set_fighting(true))


static func _pool(theme: String) -> Array:
	var people: Array = B3Defs.UNIT_ORDER.get("people", [])
	var animals: Array = B3Defs.UNIT_ORDER.get("animals", [])
	var vehicles: Array = B3Defs.UNIT_ORDER.get("vehicles", [])
	match theme:
		"soldiers":
			return ["soldier", "soldier", "gunner", "sniper", "rocketeer", "grenadier", "medic"] + vehicles
		"medieval":
			return ["knight", "knight", "viking", "viking", "archer", "archer", "giant"]
		"beasts":
			return people + animals
		"dinos":
			return ["soldier", "rocketeer", "gunner", "knight", "sniper"] + vehicles
		"everything":
			var all: Array = []
			for c in B3Defs.UNIT_ORDER:
				all += B3Defs.UNIT_ORDER[c]
			return all
	return people + vehicles


## Fills `budget` points of fighters (big ones cost more) in rows behind `base`.
static func _army(b, rng: RandomNumberGenerator, team: String, base: Vector3, face: Vector3, pool: Array, budget: int) -> void:
	var roster: Array = []
	for k in rng.randi_range(2, 4):
		var id := String(pool[rng.randi() % pool.size()])
		if B3Defs.UNITS.has(id) and id != "chicken":
			roster.append(id)
	if roster.is_empty():
		roster = ["soldier"]
	var left := float(budget)
	var picks: Array = []
	var guard := 0
	while left > 0.0 and guard < 60:
		guard += 1
		var id := String(roster[rng.randi() % roster.size()])
		var c := cost(id)
		if c > left + 0.5 and guard < 40:
			continue
		picks.append(id)
		left -= c
	var side := Vector3(-face.z, 0, face.x)
	var yaw := atan2(face.x, face.z)
	var per_row := maxi(4, int(ceil(sqrt(picks.size() * 2.0))))
	for i in picks.size():
		var row := floori(float(i) / per_row)
		var col := i % per_row
		var off := (col - (per_row - 1) * 0.5) * 1.7
		var spacing := 1.7 + (2.0 if cost(String(picks[i])) >= 4.0 else 0.0)
		var p: Vector3 = base + side * off - face * row * spacing + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		p.y = b.surface_y(Vector3(p.x, 60.0, p.z))
		b.spawn_unit(String(picks[i]), team, p, "auto", yaw)


## How many army points a fighter is worth (by toughness).
static func cost(id: String) -> float:
	var d := B3Defs.unit_def(id)
	return clampf(float(d.get("hp", 100)) / 120.0, 1.0, 9.0)


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
