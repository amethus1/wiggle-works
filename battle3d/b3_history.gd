class_name B3History
## 📜 History: famous battles set up the moment before they began, with both
## armies in their real formations (in team colours) and the battlefield built
## around them: walls, stakes, earth forts, fences, beach obstacles. Nothing
## moves until you press ▶ Fight! or pick a soldier to play.
##   godot --path . -- --battle3d --history=agincourt
## Every battle is laid out along a line: `a` metres from the first army (on
## the left of the screen) toward the second, `s` metres across.

const LIST := [
	{"id": "thermopylae", "name": "Thermopylae", "year": -480, "place": "Greece", "icon": "🏛️", "map": "pass",
		"sides": "🔴 Greeks (Spartans) vs 🔵 Persians",
		"blurb": "In 480 BC, King Leonidas with his 300 Spartans and a few thousand other Greeks held a narrow mountain pass against the huge army of the Persian king Xerxes. For three days they stood shoulder to shoulder behind their big round shields in a wall called a phalanx. Watch the red shield wall try to hold the gap!"},
	{"id": "alesia", "name": "Alesia", "year": -52, "place": "Gaul (France)", "icon": "🦅", "map": "grassland",
		"sides": "🔴 Romans vs 🔵 Gauls",
		"blurb": "In 52 BC, Julius Caesar trapped the Gaulish chief Vercingetorix in the hill town of Alesia. The Romans built miles of walls, ditches and sharp stakes, and held them when a huge Gaulish army attacked. Watch the Romans lock their big rectangular shields together!"},
	{"id": "hastings", "name": "Hastings", "year": 1066, "place": "England", "icon": "👑", "map": "grassland",
		"sides": "🔴 Saxons vs 🔵 Normans",
		"blurb": "In 1066, King Harold's Saxons made a wall of round shields along the top of a hill near Hastings. Duke William's Normans attacked again and again with archers, foot soldiers and knights on horseback, and William became King of England. Watch the knights charge up the hill at the shield wall!"},
	{"id": "agincourt", "name": "Agincourt", "year": 1415, "place": "France", "icon": "🏹", "map": "farmland",
		"sides": "🔴 English vs 🔵 French",
		"blurb": "In 1415, King Henry V's small, tired English army met a much bigger French army in a muddy field in France. English longbowmen stood behind sharp wooden stakes, and the heavy French knights got stuck in the deep mud. Watch the clouds of arrows from the longbows!"},
	{"id": "bunkerhill", "name": "Bunker Hill", "year": 1775, "place": "Boston, America", "icon": "🔔", "map": "grassland",
		"sides": "🔴 British redcoats vs 🔵 American militia",
		"blurb": "In 1775, American militia dug a fort of earth on Breed's Hill, next to Bunker Hill, in just one night. British redcoats marched up the hill in long straight lines three times before the Americans ran out of gunpowder and had to leave. Watch the redcoats climb toward the dirt walls!"},
	{"id": "waterloo", "name": "Waterloo", "year": 1815, "place": "Belgium", "icon": "🥁", "map": "farmland",
		"sides": "🔴 British vs 🔵 French",
		"blurb": "In 1815, Napoleon's French army fought the Duke of Wellington's British and allied army near Waterloo. The British soldiers stood in hollow squares facing outward, so charging horsemen couldn't get behind them, and Napoleon lost his last battle. Watch the French cavalry thunder around the red squares!"},
	{"id": "gettysburg", "name": "Gettysburg", "year": 1863, "place": "Pennsylvania, USA", "icon": "🌾", "map": "farmland",
		"sides": "🔵 Union vs 🟡 Confederates",
		"blurb": "On July 3, 1863, about 12,000 Confederate soldiers marched across an open field at Gettysburg toward Union soldiers behind a low stone wall on Cemetery Ridge. It was called Pickett's Charge, and the Union line held. Watch the long grey lines cross the field!"},
	{"id": "britain", "name": "Battle of Britain", "year": 1940, "place": "the skies over England", "icon": "✈️", "map": "grassland",
		"sides": "🔵 Royal Air Force vs 🔴 German air force",
		"blurb": "In the summer of 1940, the pilots of the Royal Air Force defended Britain against waves of German planes. They flew up again and again, and the Germans had to give up their plan to invade. Watch the fighter planes twist and turn in the sky!"},
	{"id": "dday", "name": "D-Day: Omaha Beach", "year": 1944, "place": "Normandy, France", "icon": "🌊", "map": "beach",
		"sides": "🔵 Americans vs 🔴 Germans",
		"blurb": "On June 6, 1944, called D-Day, Allied soldiers crossed the sea in landing boats to free France. At Omaha Beach, American troops ran across the sand, past steel obstacles, toward bunkers on the bluffs, and by nightfall they held the beach. Watch the tanks and soldiers storm the shore!"},
	{"id": "bulge", "name": "Battle of the Bulge", "year": 1944, "place": "the Ardennes, Belgium", "icon": "❄️", "map": "snow",
		"sides": "🔵 Americans vs 🔴 Germans",
		"blurb": "In the snowy winter of 1944, German tanks made a surprise attack through the Ardennes forest. American soldiers held on at the town of Bastogne, even when they were surrounded, until help arrived. Watch the tanks roll through the snow!"},
]

## Screen-right and screen-up on the ground in the usual (45°) view.
const R := Vector3(0.7071, 0, -0.7071)
const F := Vector3(-0.7071, 0, -0.7071)
const DIRT := Color("8d6a45")
const STAKE := Color("9a6a3a")
const STONE := Color("b9b2a6")
const CLEARABLE := ["tree", "pine", "pine_snow", "rock", "cactus", "deadtree", "palm", "olive", "bush", "shrub", "stump"]
## The team each History fighter usually fights for in these battles.
const NATURAL := {"hoplite": "red", "immortal": "blue", "legionary": "red", "gaul": "blue", "saxon": "red", "longbow": "red",
	"horseknight": "blue", "redcoat": "red", "minuteman": "blue", "linesman": "red", "cavalry": "blue", "union": "blue", "confed": "yellow", "gi": "blue"}


## The ground plan of one battle: where the middle is and which way the
## armies face each other.
class Field:
	var b = null
	var o := Vector3.ZERO          # the middle of the battle
	var ax := R                    # from the left army toward the right one
	var sd := F                    # along the battle lines
	var rng := RandomNumberGenerator.new()
	var units: Array = []

	## The ground (or a building's top) `a` metres along the battle, `s` across.
	func at(a: float, s: float) -> Vector3:
		var p := o + ax * a + sd * s
		var gy: float = b.world.height_at(p.x, p.z)
		var y: float = b.surface_y(Vector3(p.x, gy + 40.0, p.z))
		return Vector3(p.x, y, p.z)

	## Just the terrain (ignores buildings).
	func ground(a: float, s: float) -> Vector3:
		var p := o + ax * a + sd * s
		var gy: float = b.world.height_at(p.x, p.z)
		return Vector3(p.x, gy, p.z)

	## Turned to face along the battle: +1 toward the right army, -1 toward the left.
	func yaw(face: float) -> float:
		var d := ax * face
		return atan2(d.x, d.z)

	func yaw_dir(d: Vector3) -> float:
		return atan2(d.x, d.z)

	## For walls (which run along their local x): one running across the battle.
	func across_yaw() -> float:
		return atan2(-sd.z, sd.x)

	## ...and one running along it.
	func along_yaw() -> float:
		return atan2(-ax.z, ax.x)

	func unit(kind: String, team: String, a: float, s: float, face: float, pers := "auto") -> B3Unit:
		if not B3Defs.UNITS.has(kind):
			return null
		var u: B3Unit = b.spawn_unit(kind, team, at(a, s), pers, yaw(face))
		if u:
			units.append(u)
		return u

	## A block `cols` wide and `rows` deep; the front rank is at `a` and the
	## others stand behind it (away from the way they face).
	func block(kind: String, team: String, a: float, s: float, cols: int, rows: int, gap_s: float, gap_a: float, face: float, pers := "auto", jit := 0.12) -> Array:
		var out: Array = []
		for r in rows:
			for c in cols:
				var aa := a - face * r * gap_a + rng.randf_range(-jit, jit)
				var ss := s + (c - (cols - 1) * 0.5) * gap_s + rng.randf_range(-jit, jit)
				var u := unit(kind, team, aa, ss, face, pers)
				if u:
					out.append(u)
		return out

	## A hollow square, `n` fighters a side, everyone facing outward.
	func square(kind: String, team: String, a: float, s: float, n: int, gap: float, pers := "defend") -> Array:
		var out: Array = []
		var half := n * gap * 0.5
		var nrms: Array[Vector3] = [ax, sd, -ax, -sd]
		for side in 4:
			# each side starts at the corner it shares with the side before it
			var nrm := nrms[side]
			var along := nrms[(side + 1) % 4]
			for i in n:
				var p := o + ax * a + sd * s + nrm * half + along * (-half + i * gap)
				var off := p - o
				var u: B3Unit = b.spawn_unit(kind, team, at(off.dot(ax), off.dot(sd)), pers, yaw_dir(nrm))
				if u:
					units.append(u)
					out.append(u)
		return out

	## Clears trees and rocks out of a rectangle (so nobody starts inside one).
	func clear(a0: float, a1: float, s0: float, s1: float) -> void:
		var sc: Node = b.world.scenery
		for c in sc.get_children():
			if not (c is StaticBody3D) or not c.has_meta("scenery") or c.has_meta("gone"):
				continue
			if not String(c.get_meta("scenery")) in CLEARABLE:
				continue
			var d: Vector3 = (c as Node3D).global_position - o
			var aa := d.dot(ax)
			var ss := d.dot(sd)
			if aa > a0 - 2.5 and aa < a1 + 2.5 and ss > s0 - 2.5 and ss < s1 + 2.5:
				var sb := c as StaticBody3D
				sb.collision_layer = 0
				sb.set_meta("gone", true)
				if sb.has_meta("mm"):
					# drawn as one of many: shrink that one away (like B3World.uproot)
					var mm: MultiMesh = sb.get_meta("mm")
					var mi: int = sb.get_meta("mi")
					var ixf := mm.get_instance_transform(mi)
					mm.set_instance_transform(mi, Transform3D(Basis.from_scale(Vector3.ZERO), ixf.origin))
				if "trees" in b.world:
					b.world.trees.erase(sb)
				sb.queue_free()


static func info(id: String) -> Dictionary:
	for d in LIST:
		var e: Dictionary = d
		if String(e.id) == id:
			return e
	return {}


## "480 BC" or "1066".
static func year_text(y: int) -> String:
	return "%d BC" % -y if y < 0 else str(y)


## The battles you can pick (the dogfight needs the fighter plane).
static func available() -> Array:
	var out: Array = []
	for d in LIST:
		var e: Dictionary = d
		if String(e.id) == "britain" and not B3Defs.UNITS.has("plane"):
			continue
		out.append(e)
	return out


static func map_for(id: String) -> String:
	var d := info(id)
	var want := String(d.get("map", "grassland"))
	if B3Defs.MAPS.has(want):
		return want
	var fallback := {"pass": "grassland", "beach": "desert", "farmland": "grassland"}
	return String(fallback.get(want, "grassland"))


static func run(b, id_s: String) -> void:
	# "waterloo!" starts the fight a moment later (for screenshots of the action)
	var go := id_s.ends_with("!")
	var id := id_s.trim_suffix("!")
	var d := info(id)
	if id == "lineup" or id == "lineup2":
		_lineup(b, id == "lineup2")
		return
	if d.is_empty():
		if b.ui:
			b.ui.toast("Unknown history battle: " + id)
		return
	if b.tools:
		b.tools.stop_playing()
	b.set_fighting(false)
	b.load_map(map_for(id))
	b.apply_rules()
	var f := Field.new()
	f.b = b
	f.rng.seed = hash(id)
	var view := 40.0
	match id:
		"thermopylae":
			view = _thermopylae(b, f)
		"alesia":
			view = _alesia(b, f)
		"hastings":
			view = _hastings(b, f)
		"agincourt":
			view = _agincourt(b, f)
		"bunkerhill":
			view = _bunkerhill(b, f)
		"waterloo":
			view = _waterloo(b, f)
		"gettysburg":
			view = _gettysburg(b, f)
		"britain":
			view = _britain(b, f)
		"dday":
			view = _dday(b, f)
		"bulge":
			view = _bulge(b, f)
	_watch(b, _next_gen(b), f.units)
	# turn the view so the two armies face each other across the screen
	var yaw_deg := rad_to_deg(atan2(-f.ax.z, f.ax.x))
	b.cam.yaw = yaw_deg
	b.cam.yaw_target = yaw_deg
	# (the camera looks at height 0: raised ground shows up higher on screen)
	var gy: float = b.world.height_at(f.o.x, f.o.z)
	b.cam.fit(f.o + f.sd * gy / tan(deg_to_rad(float(b.cam.pitch))), view)
	if b.ui:
		b.ui.toast("📜 %s %s, %s.  %s.  Press ▶ Fight! to start, or pick a soldier and play as them!" % [d.icon, d.name, year_text(int(d.year)), d.sides])
		b.ui.refresh()
	if go:
		b.later(0.6, func(): b.set_fighting(true))


static func _next_gen(b) -> int:
	var g := int(b.get_meta("history_gen", 0)) + 1
	b.set_meta("history_gen", g)
	b.set_meta("history_fight_t", 0.0)
	return g


## Keeps an eye on the battle: once it has been going a while, defenders with
## nobody to fight near their post go out and finish it, and musket lines
## still trading shots make a last bayonet charge (so a battle can't stall
## with the last few waiting for each other). Only this battle's fighters.
static func _watch(b, gen: int, units: Array) -> void:
	b.later(2.0, func():
		if not is_instance_valid(b) or int(b.get_meta("history_gen", 0)) != gen:
			return
		var left: Array = []
		for u in units:
			if is_instance_valid(u) and not (u as B3Unit).dead:
				left.append(u)
		if left.is_empty():
			return
		if b.fighting and b.winner == "":
			var ft := float(b.get_meta("history_fight_t", 0.0)) + 2.0
			b.set_meta("history_fight_t", ft)
			for o in left:
				var u: B3Unit = o
				if u.down or u.player:
					continue
				if ft > 40.0 and u.pers == "defend" and u.speed > 0.0 and (u.target == null or not is_instance_valid(u.target)):
					u.set_personality("attack")
				elif ft > 60.0 and u.pers == "attack" and u.wpn.has("volley"):
					u.set_personality("berserk")
		_watch(b, gen, left))


## Shifts the battle so the rectangle a0..a1 x s0..s1 stays on the map.
static func _keep_inside(b, f: Field, a0: float, a1: float, s0: float, s1: float) -> void:
	var half: float = float(b.world.call("half_size")) if b.world.has_method("half_size") else B3Defs.BOUNDS
	var lim := half - 8.0
	for k in 2:
		var push := Vector3.ZERO
		for c in [Vector2(a0, s0), Vector2(a0, s1), Vector2(a1, s0), Vector2(a1, s1)]:
			var v: Vector2 = c
			var p := f.o + f.ax * v.x + f.sd * v.y
			if p.x > lim:
				push.x = minf(push.x, lim - p.x)
			elif p.x < -lim:
				push.x = maxf(push.x, -lim - p.x)
			if p.z > lim:
				push.z = minf(push.z, lim - p.z)
			elif p.z < -lim:
				push.z = maxf(push.z, -lim - p.z)
		f.o += push


## Every History fighter in two rows, close up (`--history=lineup`, or
## `lineup2` for the other teams), for checking the costumes.
static func _lineup(b, other: bool) -> void:
	if b.tools:
		b.tools.stop_playing()
	b.set_fighting(false)
	b.load_map("grassland")
	b.apply_rules()
	var ids: Array = B3Defs.UNIT_ORDER.get("history", [])
	var n := ids.size()
	var per_row := 5
	for i in n:
		var row := floori(float(i) / per_row)
		var col := i % per_row
		var p := R * (-5.0 + col * 2.8 + (row % 2) * 1.0) + F * (4.5 - row * 4.2)
		p.y = b.world.height_at(p.x, p.z)
		var team: String = NATURAL.get(String(ids[i]), "red")
		if other:
			team = String({"red": "blue", "blue": "red", "yellow": "green"}.get(team, "green"))
		b.spawn_unit(String(ids[i]), team, p, "peaceful", deg_to_rad(95.0))
	b.cam.yaw = 45.0
	b.cam.yaw_target = 45.0
	b.cam.fit(R * 0.6 + F * 0.3, 14.0)


# ------------------------------------------------------------- ground plans
## Finds the best hill near the middle: returns [top, downhill direction].
static func _hill(b, reach: float) -> Array:
	var best := Vector3.ZERO
	var best_score := -INF
	var step := 4.0
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var h: float = b.world.height_at(x, z)
			var ring := 0.0
			for i in 8:
				var a := TAU * i / 8.0
				ring += float(b.world.height_at(x + cos(a) * 20.0, z + sin(a) * 20.0))
			var score := h - ring / 8.0 - Vector2(x, z).length() * 0.025
			if score > best_score:
				best_score = score
				best = Vector3(x, h, z)
			z += step
		x += step
	return [best, _downhill(b, best, 22.0)]


## The direction from `c` where the ground is lowest `r` metres away.
static func _downhill(b, c: Vector3, r: float) -> Vector3:
	var best := R
	var lowest := INF
	for i in 24:
		var a := TAU * i / 24.0
		var d := Vector3(cos(a), 0, sin(a))
		var h := 0.0
		for k in 3:
			var rr := r * (k + 1) / 3.0
			h += float(b.world.height_at(c.x + d.x * rr, c.z + d.z * rr))
		if h < lowest:
			lowest = h
			best = d
	return best


## Sets the battle line along `dir` (the view turns so it runs left to right).
static func _line_up(f: Field, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	f.ax = d
	f.sd = Vector3(d.z, 0, -d.x)


## How wide the low ground is across the battle line at `a` (for passes).
static func _gap_width(b, f: Field, a: float, rise: float) -> Vector2:
	var base: float = f.ground(a, 0).y
	var lo := -30.0
	var hi := 30.0
	var s := 0.0
	while s < 30.0:
		s += 1.0
		if f.ground(a, s).y - base > rise:
			hi = s
			break
	s = 0.0
	while s > -30.0:
		s -= 1.0
		if f.ground(a, s).y - base > rise:
			lo = s
			break
	return Vector2(lo, hi)


# ------------------------------------------------------- terrain features
static func _custom(b, f: Field, kind_s: String, a: float, s: float, yaw: float) -> B3Struct:
	var p := f.ground(a, s)
	var st := B3Struct.new()
	st.position = Vector3(p.x, p.y - 0.08, p.z)
	st.rotation.y = yaw
	st.setup(b, kind_s, 0.0, f.rng.randi())      # an unknown kind builds nothing: we add the pieces
	b.struct_root.add_child(st)
	b.structs.append(st)
	return st


## Adds one solid piece to `st`, sitting on the ground under it.
static func _piece(b, st: B3Struct, size: Vector3, lp: Vector3, c: Color, hp: float, rot := Vector3.ZERO) -> B3Piece:
	var p := st._piece(size, lp, c, hp)
	p.rotation_degrees = rot
	var wp := st.transform * Vector3(lp.x, 0, lp.z)
	p.position.y += float(b.world.height_at(wp.x, wp.z)) - st.position.y - 0.08
	return p


## A solid earth slope rising toward local +z (no planks, unlike a ramp).
static func _slope(b, st: B3Struct, size: Vector3, lp: Vector3, yaw: float, c: Color) -> B3Piece:
	var p := B3Piece.new()
	p.structure = st
	p.size = size
	p.hp = 260.0
	p.col = c
	p.wedge = true
	p.whole = true
	p.position = lp
	p.rotation.y = yaw
	p.collision_layer = B3Defs.L_STRUCT
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var w := size.x * 0.5
	var l := size.z * 0.5
	shape.points = PackedVector3Array([
		Vector3(-w, 0, -l), Vector3(w, 0, -l), Vector3(-w, 0, l), Vector3(w, 0, l),
		Vector3(-w, size.y, l), Vector3(w, size.y, l)])
	cs.shape = shape
	p.add_child(cs)
	B3Mats.add(p, B3Mats.prism(Vector3(size.z, size.y, size.x), 1.0), B3Mats.mat(c, 0.95), Vector3(0, size.y * 0.5, 0), Vector3(0, -90, 0))
	st.add_child(p)
	st.pieces.append(p)
	var wp := st.transform * Vector3(lp.x, 0, lp.z)
	p.position.y += float(b.world.height_at(wp.x, wp.z)) - st.position.y - 0.08
	return p


## Rows of sharpened wooden stakes leaning toward the enemy (who is at `face`).
static func _stakes(b, f: Field, a: float, s0: float, s1: float, face: float, rows := 2, gap := 1.5) -> void:
	var st := _custom(b, f, "stakes", a, (s0 + s1) * 0.5, f.yaw(face))
	var L := absf(s1 - s0)
	var n := int(L / gap) + 1
	var tip := B3Mats.mat(STAKE.lightened(0.25))
	for r in rows:
		for i in n:
			var x := -L * 0.5 + i * gap + (gap * 0.5 if r % 2 == 1 else 0.0) + f.rng.randf_range(-0.15, 0.15)
			if absf(x) > L * 0.5 + 0.1:
				continue
			var lean := f.rng.randf_range(42.0, 55.0)
			var z := float(r) * 1.1
			var lp := Vector3(x, 0.85 * cos(deg_to_rad(lean)), z + 0.85 * sin(deg_to_rad(lean)))
			var p := _piece(b, st, Vector3(0.13, 1.7, 0.13), lp, STAKE.darkened(f.rng.randf_range(0.0, 0.15)), 50.0, Vector3(lean, f.rng.randf_range(-12, 12), 0))
			B3Mats.add(p, B3Mats.cyl(0.0, 0.085, 0.3, 6), tip, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3.ONE, false)


## An earth wall `length` long and `h` high, with a slope up its front (the
## side facing `face`), so attackers can scramble up and over.
static func _rampart(b, f: Field, a: float, s: float, length: float, face_dir: Vector3, h := 1.2) -> void:
	var p := f.o + f.ax * a + f.sd * s
	var off := p - f.o
	var st := _custom(b, f, "earthwork", off.dot(f.ax), off.dot(f.sd), f.yaw_dir(face_dir))
	var n := maxi(1, int(round(length / 2.0)))
	var w := length / n
	for i in n:
		var x := -length * 0.5 + w * (i + 0.5)
		_piece(b, st, Vector3(w + 0.02, h, 1.1), Vector3(x, h * 0.5, 0), DIRT.darkened(f.rng.randf_range(0.0, 0.12)), 220.0)
		_slope(b, st, Vector3(w + 0.02, h, 2.4), Vector3(x, 0, 0.55 + 1.2), PI, DIRT.lightened(0.06))
	# a row of sharpened logs along the top
	for i in int(length / 0.9):
		var x2 := -length * 0.5 + 0.45 + i * 0.9
		_piece(b, st, Vector3(0.16, 0.5, 0.16), Vector3(x2, h + 0.2, -0.3), STAKE.darkened(0.2), 40.0)


## A low wall of piled field stones, running across the battle at `a`.
static func _stone_wall(b, f: Field, a: float, s0: float, s1: float) -> void:
	var st := _custom(b, f, "stonewall", a, (s0 + s1) * 0.5, f.across_yaw())
	var L := absf(s1 - s0)
	var n := maxi(1, int(L / 1.6))
	var w := L / n
	for i in n:
		var x := -L * 0.5 + w * (i + 0.5)
		var h := f.rng.randf_range(0.8, 0.95)
		_piece(b, st, Vector3(w - 0.03, h, 0.65), Vector3(x, h * 0.5, 0), STONE.darkened(f.rng.randf_range(0.0, 0.2)), 180.0)
		_piece(b, st, Vector3(w * 0.45, 0.22, 0.5), Vector3(x + f.rng.randf_range(-0.3, 0.3), h + 0.1, 0), STONE.darkened(f.rng.randf_range(0.05, 0.25)), 60.0)


## A wooden rail fence across the battle, with gaps to get through.
static func _fence(b, f: Field, a: float, s0: float, s1: float) -> void:
	var st := _custom(b, f, "fence", a, (s0 + s1) * 0.5, f.across_yaw())
	var L := absf(s1 - s0)
	var n := int(L / 3.0)
	var wood := Color("a07a50")
	for i in n:
		if i % 4 == 3:
			continue        # a gap
		var x := -L * 0.5 + i * 3.0 + 1.5
		_piece(b, st, Vector3(0.18, 1.05, 0.18), Vector3(x - 1.4, 0.52, 0), wood.darkened(0.2), 40.0)
		for y in [0.4, 0.8]:
			_piece(b, st, Vector3(2.9, 0.12, 0.09), Vector3(x, float(y), 0), wood, 30.0, Vector3(0, 0, f.rng.randf_range(-4, 4)))


## Steel beach obstacles ("hedgehogs"): three crossed beams.
static func _hedgehog(b, f: Field, a: float, s: float) -> void:
	var st := _custom(b, f, "hedgehog", a, s, f.rng.randf() * TAU)
	var c := Color("5a5f66")
	_piece(b, st, Vector3(0.14, 1.7, 0.14), Vector3(0, 0.62, 0), c, 120.0, Vector3(35, 0, 45))
	_piece(b, st, Vector3(0.14, 1.7, 0.14), Vector3(0, 0.62, 0), c, 120.0, Vector3(35, 0, -45))
	_piece(b, st, Vector3(0.14, 1.7, 0.14), Vector3(0, 0.62, 0), c, 120.0, Vector3(-55, 0, 0))


## A landing boat at the water's edge with its front ramp down (facing +ax).
static func _boat(b, f: Field, a: float, s: float) -> void:
	var st := _custom(b, f, "boat", a, s, f.yaw(1.0))
	var c := Color("6f7d86")
	_piece(b, st, Vector3(3.2, 0.25, 4.2), Vector3(0, 0.12, -0.6), c.darkened(0.2), 200.0)
	for sx: float in [-1.0, 1.0]:
		_piece(b, st, Vector3(0.18, 1.5, 4.4), Vector3(1.6 * sx, 0.75, -0.6), c, 200.0)
	_piece(b, st, Vector3(3.2, 1.6, 0.2), Vector3(0, 0.8, -2.8), c.darkened(0.1), 200.0)
	_piece(b, st, Vector3(3.0, 0.12, 1.6), Vector3(0, 0.35, 2.2), c.lightened(0.1), 120.0, Vector3(-14, 0, 0))


## A tree for woods and copses (knocked over by big blasts like any other).
static func _tree(b, p: Vector3, rng: RandomNumberGenerator, pine := false) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = B3Defs.L_SCENERY
	sb.collision_mask = 0
	sb.position = p
	sb.rotation.y = rng.randf() * TAU
	var s := rng.randf_range(0.9, 1.3)
	if pine:
		B3Mats.add(sb, B3Mats.cyl(0.15 * s, 0.22 * s, 1.2 * s, 8), B3Mats.mat(Color("6b4426")), Vector3(0, 0.6 * s, 0))
		for i in 3:
			var r := (1.4 - i * 0.35) * s
			B3Mats.add(sb, B3Mats.cyl(0.0, r, 1.5 * s, 10), B3Mats.mat(Color("2f6e4a"), 0.9), Vector3(0, (1.6 + i * 0.85) * s, 0))
			B3Mats.add(sb, B3Mats.cyl(0.0, r * 0.75, 0.6 * s, 10), B3Mats.mat(Color("f4f8ff"), 0.8), Vector3(0, (2.15 + i * 0.85) * s, 0))
	else:
		B3Mats.add(sb, B3Mats.cyl(0.18 * s, 0.26 * s, 1.8 * s, 8), B3Mats.mat(Color("7a4e2c")), Vector3(0, 0.9 * s, 0))
		var leaf := Color("3e9a3a").lerp(Color("6cc24a"), rng.randf())
		B3Mats.add(sb, B3Mats.sphere(1.25 * s, 12), B3Mats.mat(leaf, 0.9), Vector3(0, 2.6 * s, 0))
		B3Mats.add(sb, B3Mats.sphere(0.85 * s, 10), B3Mats.mat(leaf.lightened(0.12), 0.9), Vector3(0.6 * s, 3.2 * s, 0.2 * s))
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 0.3 * s
	c.height = 2.4 * s
	cs.shape = c
	cs.position.y = 1.2 * s
	sb.add_child(cs)
	sb.set_meta("scenery", "pine" if pine else "tree")
	b.world.scenery.add_child(sb)
	if "trees" in b.world:
		b.world.trees.append(sb)


## Flat dark patches of mud (just paint on the ground).
static func _mud(b, f: Field, a0: float, a1: float, s0: float, s1: float, n: int) -> void:
	var m := B3Mats.mat(Color("7a5c3e"), 0.3)
	var m2 := B3Mats.mat(Color("8a6a48"), 0.5)
	for i in n:
		var p := f.ground(f.rng.randf_range(a0, a1), f.rng.randf_range(s0, s1))
		var r := f.rng.randf_range(0.7, 1.6)
		var mi := B3Mats.add(b.world.scenery, B3Mats.cyl(r, r, 0.04, 16), m if i % 3 != 0 else m2, p + Vector3(0, 0.04, 0), Vector3(0, 0, 0), Vector3(1.0, 1.0, f.rng.randf_range(0.5, 1.0)), false)
		mi.rotation.y = f.rng.randf() * TAU


# ---------------------------------------------------------------- battles
## Thermopylae, 480 BC: a Greek phalanx holds the narrowest part of a pass,
## an old stone wall behind it. Persian Immortals and archers come at it.
static func _thermopylae(b, f: Field) -> float:
	var walls_needed := true
	if b.map_id == "pass":
		# the Mountain Pass map runs east-west between cliffs and the sea
		_line_up(f, Vector3.RIGHT)
		var w := _gap_width(b, f, 0.0, 2.5)
		f.o += f.sd * (w.x + w.y) * 0.5
		walls_needed = w.y - w.x > 34.0
	if walls_needed:
		# no pass on this map: cliffs of stone hem the armies in
		for side: float in [-1.0, 1.0]:
			for i in 3:
				b.spawn_struct("wall", f.ground(-28.0 + i * 20.0, side * 10.0), f.along_yaw(), 20.0)
				b.spawn_struct("wall", f.ground(-28.0 + i * 20.0, side * 11.0), f.along_yaw(), 20.0)
	f.clear(-16, 32, -10, 10)
	# the old Phocian wall, with a gap in the middle
	for side: float in [-1.0, 1.0]:
		b.spawn_struct("wall", f.ground(-13.0, side * 5.5), f.across_yaw(), 7.0)
	# Greeks: a phalanx 14 wide and 4 deep
	# (the best-trained soldiers in Greece: a bit tougher than usual)
	for u in f.block("hoplite", "red", -5.0, 0.0, 14, 4, 1.1, 1.25, 1.0, "defend"):
		var h: B3Unit = u
		h.max_hp *= 1.15
		h.hp = h.max_hp
	# Persians: Immortals up front, archers behind
	f.block("immortal", "blue", 9.0, 0.0, 12, 4, 1.15, 1.4, -1.0, "attack")
	f.block("archer", "blue", 18.0, 0.0, 9, 2, 1.4, 1.5, -1.0, "ranged")
	f.o += f.ax * 3.0
	return 26.0


## Alesia, 52 BC: Roman legionaries in a shield wall in front of their fort,
## a field of sharp stakes ahead of them, archers on the towers.
static func _alesia(b, f: Field) -> float:
	f.clear(-24, 26, -20, 20)
	for side: float in [-1.0, 1.0]:
		b.spawn_struct("wall", f.ground(-20.0, side * 10.0), f.across_yaw(), 16.0)
	var towers: Array = []
	for side: float in [-1.0, 1.0]:
		var st: B3Struct = b.spawn_struct("tower", f.ground(-16.0, side * 14.0), f.yaw(1.0))
		towers.append(st)
	_stakes(b, f, -2.0, -15.0, 15.0, 1.0, 3, 1.7)
	# the legion: a solid block of shields
	f.block("legionary", "red", -8.0, 0.0, 14, 3, 1.1, 1.2, 1.0, "defend")
	f.block("archer", "red", -14.0, 0.0, 8, 1, 1.4, 1.2, 1.0, "ranged")
	for st in towers:
		var tw: B3Struct = st
		for k in 3:
			var off := f.sd * (k - 1) * 1.1
			var p: Vector3 = tw.position + off + Vector3(0, 4.68, 0)
			var u: B3Unit = b.spawn_unit("archer", "red", p, "defend", f.yaw(1.0))
			f.units.append(u)
	# the Gauls: a big, wild crowd
	for r in 4:
		for c in 13:
			var a := 14.0 + r * 1.6 + f.rng.randf_range(-0.5, 0.5)
			var s := (c - 6) * 1.35 + f.rng.randf_range(-0.4, 0.4)
			f.unit("gaul", "blue", a, s, -1.0, "attack")
	f.block("archer", "blue", 24.0, 0.0, 6, 1, 2.0, 1.0, -1.0, "ranged")
	f.o += f.ax * 2.0
	return 30.0


## Hastings, 1066: a Saxon shield wall along a hilltop; Norman archers,
## knights on foot and mounted knights come up at it.
static func _hastings(b, f: Field) -> float:
	var hl := _hill(b, 70.0)
	var top: Vector3 = hl[0]
	var down: Vector3 = hl[1]
	_line_up(f, -down)
	f.o = Vector3(top.x, 0, top.z) - f.ax * 13.0
	_keep_inside(b, f, -28, 18, -16, 16)
	f.clear(-28, 18, -16, 16)
	# King Harold's housecarls: tough, picked men
	for u in f.block("saxon", "red", 10.0, 0.0, 16, 3, 1.1, 1.2, -1.0, "defend"):
		var h: B3Unit = u
		h.max_hp *= 1.2
		h.hp = h.max_hp
	f.block("archer", "blue", -8.0, 0.0, 12, 1, 1.4, 1.0, 1.0, "ranged")
	f.block("knight", "blue", -13.0, 0.0, 12, 2, 1.2, 1.3, 1.0, "attack")
	for side: float in [-1.0, 1.0]:
		f.block("horseknight", "blue", -19.0, side * 10.0, 5, 1, 2.0, 2.8, 1.0, "attack")
	f.o += f.ax * -4.0
	return 30.0


## Agincourt, 1415: English men-at-arms in the middle, longbowmen on the
## wings behind stakes, woods on both sides; French knights in the mud.
static func _agincourt(b, f: Field) -> float:
	f.clear(-30, 20, -24, 24)
	for side: float in [-1.0, 1.0]:
		_stakes(b, f, 8.0, side * 5.5, side * 15.0, -1.0, 2, 1.4)
		# the woods of Agincourt and Tramecourt hem the field in
		for i in 9:
			var p := f.ground(-26.0 + i * 5.5 + f.rng.randf_range(-1.5, 1.5), side * (21.0 + f.rng.randf_range(0.0, 4.0)))
			_tree(b, p, f.rng)
	_mud(b, f, -10.0, 6.0, -15.0, 15.0, 40)
	f.block("knight", "red", 10.0, 0.0, 8, 2, 1.15, 1.3, -1.0, "defend")
	for side: float in [-1.0, 1.0]:
		f.block("longbow", "red", 11.5, side * 10.2, 7, 3, 1.15, 1.3, -1.0, "ranged")
	var french: Array = []
	french += f.block("knight", "blue", -12.0, 0.0, 12, 3, 1.15, 1.3, 1.0, "attack")
	for side: float in [-1.0, 1.0]:
		french += f.block("horseknight", "blue", -15.0, side * 12.5, 3, 2, 2.0, 2.8, 1.0, "attack")
	french += f.block("archer", "blue", -23.0, 0.0, 10, 1, 1.6, 1.0, 1.0, "ranged")
	# heavy armour in deep, sticky mud: the French are slow and worn out
	for u in french:
		var fu: B3Unit = u
		fu.speed *= 0.6
		if fu.kind == "knight":
			fu.max_hp *= 0.6
			fu.hp = fu.max_hp
	return 32.0


## Bunker Hill, 1775: militia in an earth fort on the hilltop, a breastwork
## and a rail fence beside it; three lines of redcoats march up.
static func _bunkerhill(b, f: Field) -> float:
	var hl := _hill(b, 70.0)
	var top: Vector3 = hl[0]
	var down: Vector3 = hl[1]
	_line_up(f, -down)
	f.o = Vector3(top.x, 0, top.z) - f.ax * 13.0
	_keep_inside(b, f, -34, 24, -22, 22)
	f.clear(-34, 24, -20, 20)
	# the redoubt: a square of earth walls, open at the back
	var c := 13.0
	_rampart(b, f, c - 5.0, 0.0, 10.0, -f.ax)
	for side: float in [-1.0, 1.0]:
		_rampart(b, f, c, side * 5.0, 10.0, f.sd * side)
		_rampart(b, f, c + 5.0, side * 3.4, 3.2, f.ax)
	# the breastwork running off one side, and a rail fence on the other
	_rampart(b, f, c - 4.0, 11.5, 9.0, -f.ax)
	_fence(b, f, c - 3.0, -8.0, -20.0)
	f.block("minuteman", "blue", c - 3.6, 0.0, 7, 3, 1.15, 1.4, -1.0, "defend")
	f.block("minuteman", "blue", c - 2.6, 11.5, 7, 1, 1.15, 1.0, -1.0, "defend")
	f.block("minuteman", "blue", c - 1.8, -14.0, 9, 1, 1.25, 1.0, -1.0, "defend")
	# three long lines of redcoats, one behind the other
	for r in 3:
		f.block("redcoat", "red", -10.0 - r * 5.0, 0.0, 20, 1, 1.1, 1.0, 1.0, "attack")
	return 32.0


## Waterloo, 1815: British infantry squares in a checkerboard; French
## cavalry ride round them, and columns of infantry come up behind.
static func _waterloo(b, f: Field) -> float:
	f.clear(-36, 26, -24, 30)
	for sq in [Vector2(4, -9), Vector2(4, 9), Vector2(13, 0), Vector2(13, 18)]:
		var v: Vector2 = sq
		f.square("linesman", "red", v.x, v.y, 4, 1.15, "defend")
	# Hougoumont farm, walled, off on the flank
	var farm := f.ground(-6.0, 26.0)
	for i in 4:
		var ang := f.along_yaw() + PI * 0.5 * i
		var dir := Basis(Vector3.UP, ang) * Vector3(0, 0, 5.0)
		b.spawn_struct("wall", farm + dir, ang, 10.0)
	b.spawn_struct("tower", farm, f.yaw(1.0))
	# French: two waves of cavalry, then columns of infantry
	f.block("cavalry", "blue", -12.0, 2.0, 9, 1, 2.2, 3.0, 1.0, "attack")
	f.block("cavalry", "blue", -17.0, 4.0, 8, 1, 2.2, 3.0, 1.0, "attack")
	for s: float in [-14.0, 16.0]:
		f.block("linesman", "blue", -24.0, s, 3, 4, 1.15, 1.2, 1.0, "attack")
	f.o += f.ax * -2.0 + f.sd * 4.0
	return 34.0


## Gettysburg, 1863 (Pickett's Charge): the Union behind a low stone wall
## on the ridge with cannons and a copse of trees; long Confederate lines
## cross the open field and its fences.
static func _gettysburg(b, f: Field) -> float:
	f.clear(-36, 30, -22, 22)
	_stone_wall(b, f, 12.0, -18.0, 4.0)
	_stone_wall(b, f, 15.0, 4.0, 18.0)       # "the Angle": the wall jogs back
	_fence(b, f, -3.0, -20.0, 20.0)
	for i in 6:
		_tree(b, f.ground(29.0 + f.rng.randf_range(-2, 2), 6.0 + f.rng.randf_range(-3, 3)), f.rng)
	f.block("union", "blue", 13.4, -7.0, 18, 1, 1.15, 1.0, -1.0, "defend")
	f.block("union", "blue", 16.4, 11.0, 12, 1, 1.15, 1.0, -1.0, "defend")
	f.block("union", "blue", 19.0, 0.0, 8, 1, 1.4, 1.0, -1.0, "defend")
	for s: float in [-12.0, 0.0, 10.0]:
		f.unit("cannon", "blue", 23.0, s, -1.0)
	f.block("confed", "yellow", -15.0, 0.0, 20, 3, 1.15, 2.4, 1.0, "attack")
	f.o += f.ax * 3.0
	return 36.0


## The Battle of Britain, 1940: RAF fighters climb to meet a wave of German
## planes over the English countryside.
static func _britain(b, f: Field) -> float:
	f.clear(-30, 30, -20, 20)
	if B3Defs.UNITS.has("plane"):
		for i in 7:
			f.unit("plane", "blue", -26.0 - (i % 2) * 4.0, -12.0 + i * 4.0, 1.0)
		for i in 7:
			f.unit("plane", "red", 24.0 + (i % 2) * 5.0, -12.0 + i * 4.0, -1.0)
	else:
		f.block("soldier", "blue", -12.0, 0.0, 8, 2, 1.2, 1.2, 1.0)
		f.block("soldier", "red", 12.0, 0.0, 8, 2, 1.2, 1.2, -1.0)
	# anti-aircraft guns and sandbags round the airfield
	for s: float in [-12.0, 12.0]:
		f.unit("mgnest", "blue", -18.0, s, 1.0)
	return 40.0


## D-Day, Omaha Beach, 1944: landing boats at the water's edge, steel
## obstacles on the sand, bunkers and machine guns on the bluff.
static func _dday(b, f: Field) -> float:
	if b.map_id == "beach":
		# the sea is downhill: the landings come from there
		var sea := _downhill(b, Vector3.ZERO, 40.0)
		_line_up(f, -sea)
		# put the boats just in the water
		var d := 0.0
		while d < 120.0 and float(b.world.height_at(sea.x * d, sea.z * d)) > 0.05:
			d += 1.0
		f.o = sea * (d - 24.0)
	f.clear(-30, 22, -24, 24)
	# up the beach: two bunkers, sandbag lines and MG nests
	for s: float in [-11.0, 11.0]:
		b.spawn_struct("bunker", f.ground(16.0, s), f.yaw(-1.0))
	for s: float in [-20.0, 0.0, 20.0]:
		b.spawn_struct("sandbags", f.ground(9.0, s), f.yaw(-1.0))
	for s: float in [-20.0, -6.0, 6.0, 20.0]:
		f.unit("mgnest", "red", 12.5, s, -1.0)
	f.block("soldier", "red", 13.5, -5.5, 4, 2, 1.4, 1.3, -1.0, "defend")
	f.block("soldier", "red", 13.5, 5.5, 4, 2, 1.4, 1.3, -1.0, "defend")
	f.block("soldier", "red", 12.0, -15.0, 3, 1, 1.4, 1.3, -1.0, "defend")
	f.block("soldier", "red", 12.0, 15.0, 3, 1, 1.4, 1.3, -1.0, "defend")
	for s: float in [-11.0, 11.0]:
		# inside the bunker, not on its roof
		var u: B3Unit = b.spawn_unit("gunner", "red", f.ground(16.2, s), "defend", f.yaw(-1.0))
		f.units.append(u)
	f.unit("sniper", "red", 20.5, -4.0, -1.0, "defend")
	f.unit("sniper", "red", 20.5, 4.0, -1.0, "defend")
	# steel hedgehogs on the sand
	for i in 14:
		_hedgehog(b, f, f.rng.randf_range(-11.0, 3.0), -22.0 + i * 3.3 + f.rng.randf_range(-0.8, 0.8))
	# the landing: five boats, each with its squad on the sand in front
	for i in 5:
		var s := -18.0 + i * 9.0
		_boat(b, f, -25.5, s)
		f.block("gi", "blue", -17.5, s, 3, 3, 1.2, 1.2, 1.0, "attack")
	for s: float in [-13.5, 13.5]:
		f.unit("rocketeer", "blue", -19.5, s, 1.0, "attack")
		f.unit("medic", "blue", -20.5, s + 1.5, 1.0)
	for s: float in [-22.5, 4.5]:
		f.unit("tank", "blue", -16.5, s, 1.0, "attack")
	f.o += f.ax * -6.0
	return 34.0


## The Battle of the Bulge, 1944: Americans dug in at the edge of a snowy
## town; German tanks and soldiers come out of the forest.
static func _bulge(b, f: Field) -> float:
	if b.weather:
		b.weather.set_kind("snow")
	f.clear(-30, 26, -22, 22)
	for i in 5:
		b.spawn_struct("sandbags", f.ground(10.0, -16.0 + i * 8.0), f.yaw(-1.0))
	for s: float in [-12.0, 12.0]:
		b.spawn_struct("bunker", f.ground(24.0, s), f.yaw(-1.0))
	# the forest the attack comes out of
	for i in 16:
		_tree(b, f.ground(-34.0 + f.rng.randf_range(-4, 4), -26.0 + i * 3.4 + f.rng.randf_range(-1, 1)), f.rng, true)
	for i in 8:
		var s := -16.0 + (i % 5) * 8.0
		f.unit("gi", "blue", 12.0 + floori(i / 5.0) * 1.4, s + (i % 2) * 1.2 - 0.6, -1.0, "defend")
	f.block("gi", "blue", 13.0, 0.0, 10, 2, 1.8, 1.4, -1.0, "defend")
	for s: float in [-15.0, -9.0, -3.0, 3.0, 9.0, 15.0]:
		f.unit("rocketeer", "blue", 15.0, s, -1.0, "defend")
	f.unit("mgnest", "blue", 10.5, -4.0, -1.0)
	for s: float in [-10.0, 0.0, 10.0]:
		f.unit("tank", "blue", 18.5, s, -1.0, "defend")
	for s: float in [-11.0, 0.0, 9.0]:
		f.unit("tank", "red", -21.0, s, 1.0, "attack")
	f.block("soldier", "red", -16.0, 0.0, 14, 2, 1.5, 1.6, 1.0, "attack")
	f.block("gunner", "red", -24.0, 0.0, 4, 1, 3.0, 1.0, 1.0, "attack")
	f.o += f.ax * -3.0
	return 34.0
