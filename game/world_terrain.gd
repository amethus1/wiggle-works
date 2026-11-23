class_name WorldTerrain
## The playground's platforms and pools, for World: platforms you build (and
## blasts cracking and breaking them), pools of water, lava and acid cut to the
## shape of the ground, and water floating things. Everything here takes the
## world; all the state stays in World.

## How much blasting a platform you built takes before it breaks: wood least,
## concrete most, and big ones more than small ones.
const PLATFORM_HP := {"wood": 160.0, "stone": 320.0, "metal": 420.0, "steel": 420.0, "concrete": 520.0, "rock": 520.0}


## Water areas are rectangles; cut away the ground so only the pond shows.
static func cut_water(world: World) -> void:
	if world._water_hold > 0:
		return   # (whoever is adding platforms cuts it once they're all there)
	world.water_version += 1
	world.water_shapes.clear()
	for wi in world.water.size():
		var rect: Rect2 = world.water[wi]
		var pieces: Array = [PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])]
		for g in world.terrain.get_children():
			# ground from the last world (or a removed platform) is still here until
			# the end of the frame: it mustn't cut holes in the new water
			if not (g is Ground) or g.is_queued_for_deletion():
				continue
			var next: Array = []
			for pc in pieces:
				for out in Geometry2D.clip_polygons(pc, g.poly):
					# clockwise pieces are holes (ground sunk completely in the water)
					if not Geometry2D.is_polygon_clockwise(out):
						next.append(out)
			pieces = next
		for pc in pieces:
			var x0 := INF
			var x1 := -INF
			for v in pc:
				if absf(v.y - rect.position.y) < 1.0:
					x0 = minf(x0, v.x)
					x1 = maxf(x1, v.x)
			world.water_shapes.append({"poly": pc, "top": rect.position.y, "x0": x0, "x1": x1, "kind": world.liquid_kinds[wi] if wi < world.liquid_kinds.size() else "water"})


## Adds a pool of water, lava or acid (its top edge is the surface).
static func add_liquid(world: World, r: Rect2, kind: String, group := 0) -> void:
	world.water.append(r)
	world.liquid_kinds.append(kind)
	world.liquid_groups.append(group)


static func add_platform(world: World, poly: PackedVector2Array, style: String, group := 0) -> Ground:
	if group == 0:
		world.next_group += 1
		group = world.next_group
	var g := Ground.new()
	g.setup(poly, Worlds.platform_style(style), group)
	g.set_meta("group", group)
	world.terrain.add_child(g)
	var hp := _platform_hp(poly, style)
	world.platforms.append({"poly": poly, "style": style, "group": group, "node": g, "hp": hp, "max": hp})
	cut_water(world)
	world.wake_resting()   # (one built right on top of a knocked-out fighter pushes it out)
	return g


static func _platform_hp(poly: PackedVector2Array, style: String) -> float:
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	return float(PLATFORM_HP.get(style, 300.0)) * clampf(absf(area) * 0.5 / 5000.0, 0.6, 2.5)


## Can blasts break this platform? Only ones you built (the world's own forts,
## catwalks and islands stay), and not the walls of a tub (the lava would go
## everywhere).
static func platform_breakable(world: World, pl: Dictionary) -> bool:
	return int(pl.group) > 0 and not world.liquid_groups.has(int(pl.group))


## An explosion at `p` cracks the platforms you built nearby, and breaks them
## once they've taken enough (see Combat.blast).
static func damage_platforms(world: World, p: Vector2, rad: float, dmg: float) -> void:
	if world.puppet:
		return
	var broke: Array = []
	for pl in world.platforms:
		if not platform_breakable(world, pl):
			continue
		var poly: PackedVector2Array = pl.poly
		var d := 0.0
		var near := p
		if not Geometry2D.is_point_in_polygon(p, poly):
			d = INF
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				if p.distance_to(q) < d:
					d = p.distance_to(q)
					near = q
		if d > rad:
			continue
		pl.hp = float(pl.get("hp", 100.0)) - dmg * 2.2 * (1.0 - d / rad)
		if pl.hp <= 0.0:
			broke.append(pl)
		elif is_instance_valid(pl.node):
			var before: int = pl.node.cracks
			(pl.node as Ground).set_damage(1.0 - float(pl.hp) / maxf(1.0, float(pl.get("max", 100.0))))
			if pl.node.cracks != before:
				world.fx_event("plat_crack", {"p": near, "c": (pl.node as Ground).style.get("fill", Color.GRAY)})
	for pl in broke:
		_break_platform(world, pl)


## A platform blown to bits: whatever stood on it falls.
static func _break_platform(world: World, pl: Dictionary) -> void:
	world.platforms.erase(pl)
	var poly: PackedVector2Array = pl.poly
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	var col: Color = Worlds.platform_style(String(pl.style)).get("fill", Color.GRAY)
	if is_instance_valid(pl.node):
		pl.node.queue_free()
	world.fx_event("plat_break", {"p": box.get_center(), "w": box.size.x, "h": box.size.y, "c": col})
	world._cut_water.call_deferred()
	world.wake_resting()


static func platform_at(world: World, p: Vector2) -> int:
	for pl in world.platforms:
		if Geometry2D.is_point_in_polygon(p, pl.poly):
			return int(pl.group)
	return 0


## Removes every platform (and tub liquid) in a group.
static func remove_platform_group(world: World, group: int) -> void:
	if group == 0:
		return
	var keep: Array = []
	for pl in world.platforms:
		if int(pl.group) == group:
			if is_instance_valid(pl.node):
				pl.node.queue_free()
				world.fx_event("crumble", {"p": _poly_center(pl.poly)})
		else:
			keep.append(pl)
	world.platforms = keep
	for i in range(world.water.size() - 1, -1, -1):
		if i < world.liquid_groups.size() and int(world.liquid_groups[i]) == group:
			world.water.remove_at(i)
			world.liquid_kinds.remove_at(i)
			world.liquid_groups.remove_at(i)
	world._cut_water.call_deferred()
	world.wake_resting()   # knocked-out fighters lying on it fall


## Takes away every platform and pit the players built (the world's own stay).
static func clear_placed(world: World) -> void:
	var groups := {}
	# placed things have groups above 0; the world's own forts and catwalks are below 0
	for pl in world.platforms:
		if int(pl.group) > 0:
			groups[int(pl.group)] = true
	for i in world.liquid_groups.size():
		if int(world.liquid_groups[i]) > 0:
			groups[int(world.liquid_groups[i])] = true
	for g in groups:
		remove_platform_group(world, g)


static func _poly_center(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / maxf(1.0, poly.size())


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func step_water(world: World, dt: float) -> void:
	if world.water.is_empty():
		return
	var g: float = Catalog.gravity_def(world.gravity_id).g.length()
	g = maxf(g, 300.0)
	for t in world.all_things():
		if t is Toy:
			if t.freeze:
				continue
			var he: Vector2 = t.half_extents()
			var r: Rect2 = world.in_water(t.global_position + Vector2(0, he.y))
			if r.size == Vector2.ZERO:
				t.extra.erase("in_water")
				continue
			var sub := clampf((t.global_position.y + he.y - r.position.y) / (he.y * 2.0), 0.0, 1.0)
			var lift := 1.9 if t.def.get("floaty", false) else 0.55
			t.linear_velocity += Vector2(0, -g * lift * sub * dt)
			t.linear_velocity *= maxf(0.0, 1.0 - 2.4 * sub * dt)
			t.angular_velocity *= maxf(0.0, 1.0 - 2.0 * sub * dt)
			t.wet = 1.0
			if not t.extra.has("in_water"):
				t.extra.in_water = true
				if t.linear_velocity.length() > 160.0:
					world.fx_event("splash", {"p": Vector2(t.global_position.x, r.position.y), "s": he.length() / 30.0})
		elif t is Wiggly:
			if t.frozen_t > 0.0 or t.points.is_empty():
				continue
			var under := 0
			var surface := 0.0
			for p in t.points:
				var r: Rect2 = world.in_water(p.global_position)
				if r.size != Vector2.ZERO:
					under += 1
					surface = r.position.y
					var lift := 0.55 if t.kind == "boulder" else 1.7
					p.linear_velocity += Vector2(0, -g * lift * dt)
					p.linear_velocity *= maxf(0.0, 1.0 - 2.0 * dt)
			if under > 0:
				t.wet = 1.0
				if not t.has_meta("in_water"):
					t.set_meta("in_water", true)
					Settings.award("splash")
					if t.com_vel.length() > 140.0:
						world.fx_event("splash", {"p": Vector2(t.com.x, surface), "s": t.size * 1.2})
			elif t.has_meta("in_water"):
				t.remove_meta("in_water")
