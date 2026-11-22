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
	world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5, pos.y, w, 18)), style, g)
	world.add_platform(World.rect_poly(Rect2(pos.x - w * 0.5 - wall, top, wall, h + 18)), style, g)
	world.add_platform(World.rect_poly(Rect2(pos.x + w * 0.5, top, wall, h + 18)), style, g)
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


static func build(world: World, id: String, pos: Vector2) -> Toy:
	match id:
		"seesaw":
			var pivot := world.spawn_toy("ramp", pos + Vector2(0, 30), 0.0, 0.6)
			var plank := world.spawn_toy("plank", pos + Vector2(0, -6), 0.0, 1.6)
			if pivot and plank:
				pivot.def = pivot.def.duplicate()
				pivot.set_facing(1.0)
				world.add_link("hinge", pivot, plank, pos + Vector2(0, -6), pos + Vector2(0, -6))
			return plank
		"catapult":
			var base := world.spawn_toy("brick", pos + Vector2(0, 30), 0.0, 1.6)
			var motor := world.spawn_toy("motor", pos + Vector2(0, -8))
			var arm := world.spawn_toy("plank", pos + Vector2(60, -8), 0.0, 1.0)
			var sw := world.spawn_toy("switch", pos + Vector2(-70, 40))
			if base and motor and arm and sw:
				world.add_link("hinge", base, motor, motor.global_position, motor.global_position)
				world.add_link("glue", motor, arm, motor.global_position + Vector2(10, 0), motor.global_position + Vector2(10, 0))
				world.add_link("wire", sw, motor, sw.global_position, motor.global_position)
				var cup := world.spawn_toy("beach_ball", pos + Vector2(120, -40), 0.0, 0.7)
				if cup:
					cup.paint = Color("ffd43b")
			return base
		"ferris":
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
						arm.add_collision_exception_with(post)
					world.add_link("glue", hub, arm, pos + Vector2.from_angle(a) * 20.0, pos + Vector2.from_angle(a) * 20.0)
					var seat_p := pos + Vector2.from_angle(a) * 128.0
					var seat := world.spawn_toy("pillow", seat_p + Vector2(0, 18), 0.0, 0.55)
					if seat:
						if post:
							seat.add_collision_exception_with(post)
						world.add_link("hinge", arm, seat, seat_p, seat_p)
			return hub
		"rocket_cart":
			var kart := ride(world, "go_kart", pos)
			if kart == null:
				return null
			var sw := world.spawn_toy("switch", pos + Vector2(10, -30))
			if sw:
				world.add_link("glue", kart, sw, pos + Vector2(10, -14), pos + Vector2(10, -14))
			for sy in [-6.0, 10.0]:
				var r := world.spawn_toy("rocket", pos + Vector2(-78, sy))
				if r:
					world.add_link("glue", kart, r, pos + Vector2(-58, sy), pos + Vector2(-58, sy))
					if sw:
						world.add_link("wire", sw, r, sw.global_position, r.global_position)
			return kart
		"domino":
			var first: Toy = null
			for i in 12:
				var d := world.spawn_toy("plank", pos + Vector2(-260 + i * 46, 0), PI * 0.5, 0.55)
				if d:
					d.paint = Color.from_hsv(float(i) / 12.0, 0.6, 1.0)
					if first == null:
						first = d
			var ball := world.spawn_toy("bowling_ball", pos + Vector2(-340, -60), 0.0, 0.8)
			var ramp := world.spawn_toy("ramp", pos + Vector2(-345, 18), 0.0, 0.8)
			if ramp:
				ramp.set_facing(-1.0)
			return first
		"lamp_show":
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
	return null
