class_name Builders
## Rides made of several parts, and ready-made contraptions.

const WHEEL := {"part": true, "name": "Wheel", "shape": "circle", "r": 18, "mass": 1.0, "bounce": 0.1, "fric": 1.6, "color": Color("2d3436")}
const ENVELOPE := {"part": true, "name": "Balloon", "shape": "circle", "r": 62, "mass": 0.6, "bounce": 0.2, "fric": 0.4, "color": Color("ff6b6b"), "floaty": true}
const SAIL := {"part": true, "name": "Sail", "shape": "box", "w": 8, "h": 90, "mass": 0.4, "bounce": 0.1, "fric": 0.5, "color": Color("f5f6fa"), "floaty": true}


## The definition of a ride part (wheels come in two sizes).
static func part_def(id: String, r := 0.0) -> Dictionary:
	match id:
		"wheel":
			var d := WHEEL.duplicate()
			if r > 0.0:
				d.r = r
				d.mass = 2.4 if r > 25.0 else 0.9
			return d
		"envelope":
			return ENVELOPE
		"sail":
			return SAIL
	# rockets, arrows and bombs in flight (a friend's copy, or a save) aren't toy-box toys
	if Combat.PROJ.has(id):
		return Combat.PROJ[id]
	return Catalog.toy(id)


static func ride(world: World, id: String, pos: Vector2) -> Toy:
	match id:
		"go_kart", "monster_truck":
			var big := id == "monster_truck"
			var body := world.spawn_toy(id, pos)
			if body == null:
				return null
			pos = body.global_position   # it may have been lifted out of the ground: parts go with it
			var wd := WHEEL.duplicate()
			wd.r = 32 if big else 17
			wd.mass = 2.4 if big else 0.9
			var off_x := 48.0 if big else 38.0
			var off_y: float = (body.h * 0.5 + wd.r * 0.55) if big else (body.h * 0.5 + 6.0)
			for sx in [-1.0, 1.0]:
				var whl := world.spawn_toy("wheel", pos + Vector2(sx * off_x, off_y), 0.0, 1.0, wd)
				if whl:
					whl.parent_uid = body.uid
					world.add_link("hinge", body, whl, whl.global_position, whl.global_position)
			return body
		"hot_air":
			var basket := world.spawn_toy("hot_air", pos)
			if basket == null:
				return null
			pos = basket.global_position   # it may have been lifted out of the ground
			var env := world.spawn_toy("envelope", pos + Vector2(0, -150), 0.0, 1.0, ENVELOPE)
			if env:
				env.parent_uid = basket.uid
				env.gravity_scale = 0.0
				for sx in [-1.0, 1.0]:
					world.add_link("rope", basket, env, pos + Vector2(sx * 30.0, -18.0), env.global_position + Vector2(sx * 40.0, 44.0))
			return basket
		"boat":
			var hull := world.spawn_toy("boat", pos)
			if hull == null:
				return null
			pos = hull.global_position   # it may have been lifted out of the ground
			var sail := world.spawn_toy("sail", pos + Vector2(4, -58), 0.0, 1.0, SAIL)
			if sail:
				sail.parent_uid = hull.uid
				world.add_link("glue", hull, sail, pos + Vector2(4, -12), pos + Vector2(4, -12))
			return hull
	return null


## A tub of lava, acid or water: a floor and two walls with liquid inside.
static func tub(world: World, id: String, pos: Vector2) -> Node:
	var d := Catalog.toy(id)
	var w := float(d.get("w", 240))
	var h := float(d.get("h", 120))
	var kind := String(d.tub)
	var style: String = {"lava": "rock", "acid": "steel", "water": "stone"}.get(kind, "stone")
	world.next_group += 1
	var g: int = world.next_group
	# the click is the middle of the tub's floor top
	var top := pos.y - h
	var wall := 16.0
	world._water_hold += 1   # (the water is cut once, below)
	world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y, w, 18)), style, g)
	world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5 - wall, top, wall, h + 18)), style, g)
	world.add_platform(World.rect_poly(Rect2(pos.x + w * 0.5, top, wall, h + 18)), style, g)
	world._water_hold -= 1
	world.add_liquid(Rect2(pos.x - w * 0.5, top + h * 0.25, w, h * 0.75), kind, g)
	world._cut_water()
	world.fx_event("build", {"p": pos})
	return null


## A ready-made platform shape centred where you click.
static func platform_preset(world: World, id: String, pos: Vector2) -> Node:
	var d := Catalog.platform_def(id)
	var w := float(d.w)
	var h := float(d.h)
	world.next_group += 1
	var g: int = world.next_group
	match id:
		"tower":
			world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.3, pos.y - h * 0.5, w * 0.6, h)), "stone", g)
			world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y - h * 0.5 - 16, w, 16)), "wood", g)
			world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y - h * 0.5 - 46, 10, 30)), "wood", g)
			world.add_platform(World.rect_poly(Rect2(pos.x + w * 0.5 - 10, pos.y - h * 0.5 - 46, 10, 30)), "wood", g)
		"bunker":
			world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, 22)), "concrete", g)
			world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y - h * 0.5, 22, h)), "concrete", g)
			world.add_platform(World.rect_poly(Rect2(pos.x + w * 0.5 - 22, pos.y - h * 0.5, 22, h * 0.45)), "concrete", g)
		_:
			world.add_platform(World.rect_poly(Rect2(pos - Vector2(w, h) * 0.5, Vector2(w, h))), String(d.style), g)
	world.fx_event("build", {"p": pos})
	return null


## Moves a contraption's spot up until every one of its parts is clear of the
## ground, so it comes out in one piece. (Each toy is lifted out of the ground
## on its own: the parts of a build put down near the ground went up by
## different amounts, and the joints between them tore it apart.)
## `parts`: [toy id (or a part's def), offset, rotation, scale] for each part.
static func _clear_spot(world: World, pos: Vector2, parts: Array) -> Vector2:
	var pts := PackedVector2Array()
	for e in parts:
		var d: Dictionary = e[0] if e[0] is Dictionary else Catalog.toy(String(e[0]))
		var off: Vector2 = e[1]
		var rot: float = e[2]
		var s: float = e[3]
		if String(d.get("shape", "box")) == "circle":
			var r := float(d.get("r", 12.0)) * s - 1.0
			pts.append(off)
			for k in 8:
				pts.append(off + Vector2.from_angle(TAU * k / 8.0) * r)
		else:
			var he := Vector2(float(d.get("w", 24.0)), float(d.get("h", 24.0))) * 0.5 * s - Vector2(1.0, 1.0)
			for k in 9:
				var q := Vector2(float(k % 3) - 1.0, floorf(k / 3.0) - 1.0)
				pts.append(off + (q * he).rotated(rot))
	var p := pos
	for step in 80:
		var clear := true
		for q in pts:
			if world.in_ground(p + q):
				clear = false
				break
		if clear:
			return p
		p.y -= 12.0
	return pos


## Where the ground (or a platform) is right under `p` (y), or `p.y` + `most`
## if there's nothing that close.
static func _ground_y(world: World, p: Vector2, most := 900.0) -> float:
	var q := PhysicsRayQueryParameters2D.create(p, p + Vector2(0, most), Toy.LAYER_GROUND)
	var hit := world.get_world_2d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else p.y + most


## A toy nailed down into the ground right below `x`, with just its top `show`
## px sticking out (traps: a pressure plate or a mine set into the ground, so
## people walk right onto it instead of bumping into its side).
static func _nailed_on_ground(world: World, id: String, x: float, from_y: float, show := 5.0) -> Toy:
	var d := Catalog.toy(id)
	var gy := _ground_y(world, Vector2(x, from_y - 60.0))
	var t := world.spawn_toy(id, Vector2(x, gy - show + float(d.get("h", 20.0)) * 0.5), 0.0, 1.0, d)
	if t:
		t.nailed = true
		t.update_freeze()
	return t


static func build(world: World, id: String, pos: Vector2) -> Toy:
	match id:
		"seesaw":
			# a plank hinged on top of an A-shaped stand: two ramps back to back,
			# nailed down on the ground. (It used to hang in the air above one
			# lopsided ramp that nothing held down.)
			pos.y = _ground_y(world, pos + Vector2(0, -60)) - 41.0
			pos = _clear_spot(world, pos, [["ramp", Vector2(-30, 24), 0.0, 0.5], ["ramp", Vector2(30, 24), 0.0, 0.5], ["plank", Vector2(0, -4), 0.0, 1.6]])
			var left := world.spawn_toy("ramp", pos + Vector2(-30, 24), 0.0, 0.5)
			var right := world.spawn_toy("ramp", pos + Vector2(30, 24), 0.0, 0.5)
			var plank := world.spawn_toy("plank", pos + Vector2(0, -4), 0.0, 1.6)
			if left == null or right == null or plank == null:
				return plank
			left.set_facing(1.0)     # (each rises toward the middle: the peak is under the plank)
			right.set_facing(-1.0)
			for r in [left, right]:
				r.nailed = true
				r.update_freeze()
			world.add_link("hinge", left, plank, pos + Vector2(0, 5), pos + Vector2(0, 5))
			return plank
		"catapult":
			# Flip the switch: a big motor wheel swings the arm up and over and the
			# ball in its cup goes flying. (A Motor Wheel turns itself, and only
			# drags along what's glued to it: the old catapult's small motor
			# couldn't lift its long arm, so nothing ever flew.) The base and the
			# rest under the arm are nailed down on the ground.
			var gy := _ground_y(world, pos + Vector2(0, -60))
			pos = Vector2(pos.x, gy - 76.0)    # the wheel's middle
			var plan := [["brick", Vector2(0, 56), 0.0, 1.6], ["motor", Vector2.ZERO, 0.0, 2.5], ["plank", Vector2(-55, 0), 0.0, 0.8],
				["wood_block", Vector2(-108, -13), 0.0, 0.4], ["wood_block", Vector2(-95, 57), 0.0, 1.0], ["switch", Vector2(-160, 60), 0.0, 1.0]]
			pos = _clear_spot(world, pos, plan)
			var base := world.spawn_toy("brick", pos + Vector2(0, 56), 0.0, 1.6)
			var motor := world.spawn_toy("motor", pos, 0.0, 2.5)
			var arm := world.spawn_toy("plank", pos + Vector2(-55, 0), 0.0, 0.8)
			var lip := world.spawn_toy("wood_block", pos + Vector2(-108, -13), 0.0, 0.4)
			var rest := world.spawn_toy("wood_block", pos + Vector2(-95, 57))
			var sw := world.spawn_toy("switch", pos + Vector2(-160, 60))
			if base == null or motor == null or arm == null or sw == null:
				return base
			for n in [base, rest]:
				if n:
					n.nailed = true
					n.update_freeze()
			motor.set_facing(1.0)   # clockwise: the arm's far end comes up and over
			world.add_link("hinge", base, motor, pos, pos)
			world.add_link("glue", motor, arm, pos + Vector2(-30, 0), pos + Vector2(-30, 0))
			if lip:
				world.add_link("glue", arm, lip, pos + Vector2(-108, -6), pos + Vector2(-108, -6))
			world.add_link("wire", sw, motor, sw.global_position, motor.global_position)
			var ball := world.spawn_toy("beach_ball", pos + Vector2(-83, -24), 0.0, 0.6)
			if ball:
				ball.paint = Color("ffd43b")
			return base
		"ferris":
			var arms: Array = []
			for i in 4:
				var a := TAU * i / 4.0
				arms.append(["plank", Vector2.from_angle(a) * 70.0, a, 0.8])
				arms.append(["pillow", Vector2.from_angle(a) * 128.0 + Vector2(0, 18), 0.0, 0.55])
			pos = _clear_spot(world, pos, [["motor", Vector2.ZERO, 0.0, 1.5], ["metal_beam", Vector2(0, 110), PI * 0.5, 1.2]] + arms)
			var hub := world.spawn_toy("motor", pos, 0.0, 1.5)
			if hub == null:
				return null
			hub.nailed = false
			hub.on = true
			var post := world.spawn_toy("metal_beam", pos + Vector2(0, 110), PI * 0.5, 1.2)
			if post:
				post.nailed = true
				post.update_freeze()
				world.add_link("hinge", post, hub, pos, pos)
			for i in 4:
				var a := TAU * i / 4.0
				var arm_c := pos + Vector2.from_angle(a) * 70.0
				var arm := world.spawn_toy("plank", arm_c, a, 0.8)
				if arm:
					# the wheel turns in front of its post, not into it
					if post:
						world.no_collide(arm, post)
					world.add_link("glue", hub, arm, pos + Vector2.from_angle(a) * 20.0, pos + Vector2.from_angle(a) * 20.0)
					var seat_p := pos + Vector2.from_angle(a) * 128.0
					var seat := world.spawn_toy("pillow", seat_p + Vector2(0, 18), 0.0, 0.55)
					if seat:
						if post:
							world.no_collide(seat, post)
						world.add_link("hinge", arm, seat, seat_p, seat_p)
			return hub
		"rocket_cart":
			# two rockets side by side on the back (they used to overlap and shove
			# each other about, so the cart drove off on its own), and the switch
			# on top. Every part is placed from where the kart really ended up.
			var wd := WHEEL.duplicate()
			wd.r = 17
			pos = _clear_spot(world, pos, [["go_kart", Vector2.ZERO, 0.0, 1.0], [wd, Vector2(-38, 17), 0.0, 1.0], [wd, Vector2(38, 17), 0.0, 1.0],
				["rocket", Vector2(-84, -12), 0.0, 1.0], ["rocket", Vector2(-84, 12), 0.0, 1.0], ["switch", Vector2(10, -27), 0.0, 1.0]])
			var kart := ride(world, "go_kart", pos)
			if kart == null:
				return null
			pos = kart.global_position
			var sw := world.spawn_toy("switch", pos + Vector2(10, -27))
			if sw:
				world.add_link("glue", kart, sw, pos + Vector2(10, -12), pos + Vector2(10, -12))
				# (the switch drives the kart too: parked, its wheels brake against the rockets)
				world.add_link("wire", sw, kart, sw.global_position, kart.global_position)
			for sy in [-12.0, 12.0]:
				var r := world.spawn_toy("rocket", pos + Vector2(-84, sy))
				if r:
					world.add_link("glue", kart, r, pos + Vector2(-60, sy), pos + Vector2(-60, sy))
					if sw:
						world.add_link("wire", sw, r, sw.global_position, r.global_position)
			return kart
		"domino":
			var plan: Array = [["bowling_ball", Vector2(-340, -60), 0.0, 0.8], ["ramp", Vector2(-345, 18), 0.0, 0.8]]
			for i in 12:
				plan.append(["plank", Vector2(-260 + i * 46, 0), PI * 0.5, 0.55])
			pos = _clear_spot(world, pos, plan)
			var first: Toy = null
			for i in 12:
				var d := world.spawn_toy("plank", pos + Vector2(-260 + i * 46, 0), PI * 0.5, 0.55)
				if d:
					d.paint = Color.from_hsv(float(i) / 12.0, 0.6, 1.0)
					if first == null:
						first = d
			world.spawn_toy("bowling_ball", pos + Vector2(-340, -60), 0.0, 0.8)
			var ramp := world.spawn_toy("ramp", pos + Vector2(-345, 18), 0.0, 0.8)
			if ramp:
				ramp.set_facing(-1.0)
			return first
		"lamp_show":
			pos = _clear_spot(world, pos, [["metal_beam", Vector2(0, 20), 0.0, 1.4], ["timer", Vector2(-140, -10), 0.0, 1.0],
				["lamp", Vector2(-50, -12), 0.0, 1.0], ["lamp", Vector2(20, -12), 0.0, 1.0], ["lamp", Vector2(90, -12), 0.0, 1.0]])
			var beam := world.spawn_toy("metal_beam", pos + Vector2(0, 20), 0.0, 1.4)
			var timer := world.spawn_toy("timer", pos + Vector2(-140, -10))
			if beam == null or timer == null:
				return null
			world.add_link("glue", beam, timer, timer.global_position + Vector2(0, 18), timer.global_position + Vector2(0, 18))
			for i in 3:
				var lp := world.spawn_toy("lamp", pos + Vector2(-50 + i * 70, -12))
				if lp:
					lp.paint = Catalog.PAINT[[0, 3, 5][i]]
					world.add_link("glue", beam, lp, lp.global_position + Vector2(0, 18), lp.global_position + Vector2(0, 18))
					world.add_link("wire", timer, lp, timer.global_position, lp.global_position)
			return timer
		# 🔌 Battle Trap Builds: ready-made wired traps, to show what wires can do
		"trap_minefield":
			# a pressure plate wired to a row of landmines: step on the plate (or
			# any mine) and the whole field goes up
			var plate := _nailed_on_ground(world, "button", pos.x - 170.0, pos.y)
			if plate == null:
				return null
			plate.paint = Color("ffd43b")
			for i in 3:
				var mine := _nailed_on_ground(world, "landmine", pos.x - 50.0 + i * 100.0, pos.y)
				if mine:
					world.add_link("wire", plate, mine, plate.global_position, mine.global_position)
			world.fx_event("build", {"p": plate.global_position})
			return plate
		"disarm_gate":
			# a magnet hanging over two pressure plates: walk under it and it
			# yanks your sword or gun away (wooden bows, spears and clubs are safe)
			var plates: Array = []
			for i in 2:
				var pl := _nailed_on_ground(world, "button", pos.x - 30.0 + i * 60.0, pos.y)
				if pl:
					pl.paint = Color("74b9ff")
					plates.append(pl)
			if plates.is_empty():
				return null
			var mag := world.spawn_toy("magnet", Vector2(pos.x, (plates[0] as Toy).global_position.y - 170.0))
			if mag:
				mag.nailed = true
				mag.update_freeze()
				for pl in plates:
					world.add_link("wire", pl, mag, (pl as Toy).global_position, mag.global_position)
			return plates[0]
		"ufo_abductor":
			# a hover saucer over a pressure plate: step on it and the saucer
			# beams you up (the beam stays on a moment after you leave the plate)
			var plate := _nailed_on_ground(world, "button", pos.x, pos.y)
			if plate == null:
				return null
			plate.paint = Color("2ed573")
			var ufo := world.spawn_toy("saucer", Vector2(pos.x, plate.global_position.y - 250.0))
			if ufo:
				ufo.nailed = true
				ufo.update_freeze()
				world.add_link("wire", plate, ufo, plate.global_position, ufo.global_position)
			return plate
	return null
