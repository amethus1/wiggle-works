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
	# 🪙 the same points for every army (B3Defs.cost: a soldier is 2, a tank 15)
	var budget := rng.randi_range(20, 36) if n_teams <= 2 else rng.randi_range(14, 26)
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
			var dp := Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
			dp.y = b.surface_y(Vector3(dp.x, 60.0, dp.z))      # on the ground, not inside a hill
			b.spawn_unit(dk, "wild", dp, "attack")
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


## Fills `budget` 🪙 points of fighters (B3Defs.cost, the same prices as
## budget battles, so every army is as strong) in rows behind
## `base`, people in front and the big ones (tanks, T-Rexes) behind, each
## with as much room as it needs so nobody starts inside anyone else.
static func _army(b, rng: RandomNumberGenerator, team: String, base: Vector3, face: Vector3, pool: Array, budget: int) -> void:
	var roster: Array = []
	for k in rng.randi_range(2, 4):
		var id := String(pool[rng.randi() % pool.size()])
		if B3Defs.UNITS.has(id) and id != "chicken":
			roster.append(id)
	if roster.is_empty():
		roster = ["soldier"]
	var left := budget
	var picks: Array = []
	var guard := 0
	while left > 0 and guard < 60:
		guard += 1
		var id := String(roster[rng.randi() % roster.size()])
		var c := B3Defs.cost(id)
		if c > left and guard < 40:
			continue
		picks.append(id)
		left -= c
	picks.sort_custom(func(p1, p2): return room(String(p1)) < room(String(p2)))
	var side := Vector3(-face.z, 0, face.x)
	var yaw := atan2(face.x, face.z)
	var width := maxi(4, int(ceil(sqrt(picks.size() * 2.0)))) * 1.7
	var back := 0.0      # how far behind `base` the middle of the last row was
	var last_deep := 0.0
	var i := 0
	while i < picks.size():
		# one row: as many as fit across (always at least one)
		var row: Array = []
		var used := 0.0
		var deep := 0.0
		while i < picks.size() and (row.is_empty() or used + room(String(picks[i])) <= width + 0.01):
			var rm := room(String(picks[i]))
			row.append(picks[i])
			used += rm
			deep = maxf(deep, rm)
			i += 1
		if last_deep > 0.0:
			back += (last_deep + deep) * 0.5
		last_deep = deep
		var x := -used * 0.5
		for id in row:
			var rm2 := room(String(id))
			var p: Vector3 = base + side * (x + rm2 * 0.5) - face * back + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			x += rm2
			p.y = b.surface_y(Vector3(p.x, 60.0, p.z))
			b.spawn_unit(String(id), team, p, "auto", yaw)


## How much space (metres across) a fighter needs in a line: 1.7 for a
## person, more for horses, big animals, dinosaurs and vehicles.
static func room(id: String) -> float:
	var d := B3Defs.unit_def(id)
	var r := 0.44      # about how wide it is from its middle, before its size (like B3Rig's radius)
	match String(d.get("body", "")):
		"vehicle":
			return float(d.get("size", 3.0)) + 1.0
		"quad":
			var q: Dictionary = B3Rig.QUAD.get(String(d.style), {"bw": 1.0, "bl": 1.0})
			r = maxf(float(q.bw) * 0.6, float(q.bl) * 0.32)
		"biped":
			var q2: Dictionary = B3Rig.BIPED.get(String(d.style), {"bl": 1.0})
			r = float(q2.bl) * 0.38
		"rider", "dragon":
			r = 0.65      # horses and dragons are long
	return maxf(1.7, r * float(d.get("size", 1.0)) * 2.0 + 0.8)


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
