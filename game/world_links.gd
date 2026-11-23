class_name WorldLinks
## Links between things, for World: glue, hinges, ropes, springs and wires,
## and the power that flows along the wires. Everything here takes the world;
## all the state stays in World.


static func add_link(world: World, kind: String, a: PhysicsBody2D, b: PhysicsBody2D, pa: Vector2, pb: Vector2) -> Link:
	if a == null or b == null or a == b:
		return null
	var l := Link.new()
	l.setup(kind, a, b, pa, pb)
	l.uid_a = _owner_uid(a)
	l.uid_b = _owner_uid(b)
	if l.uid_a == l.uid_b and l.uid_a != 0:
		return null
	l.build(world.pin_parent)
	world.links.append(l)
	for body in [a, b]:
		if body is FighterPart and body.fighter:
			body.fighter.wake()   # (a knocked-out fighter lying still: the rope or glue can move it now)
	return l


## Toy `a` passes through toy `b` from now on, and goes on doing so after a
## save, an undo or loading (the Spinny Wheel's arms and seats turn in front
## of its post). Kept in `a.extra.nc`: asking the physics for a body's list
## complains about bodies that have gone since.
static func no_collide(a: Toy, b: Toy) -> void:
	a.add_collision_exception_with(b)
	if not a.extra.has("nc"):
		a.extra.nc = []
	if not (a.extra.nc as Array).has(b.uid):
		(a.extra.nc as Array).append(b.uid)


static func _owner_uid(body: PhysicsBody2D) -> int:
	if body is JellyPoint:
		return body.wiggly.uid
	if body is FighterPart:
		return body.fighter.uid
	if body is Toy:
		return body.uid
	return 0


static func links_of(world: World, uid: int) -> Array:
	return world.links.filter(func(l): return l.uid_a == uid or l.uid_b == uid)


static func resolve_body(world: World, uid: int, idx: int, at := Vector2.INF) -> PhysicsBody2D:
	var t = world.things.get(uid)
	if t is Toy:
		return t
	if t is Fighter:
		return t.body_near(at if at != Vector2.INF else t.center())
	if t is Wiggly and not t.points.is_empty():
		return t.points[clampi(idx, 0, t.points.size() - 1)]
	return null


## Every physics step: links stretch and snap, and a Gummy stuck on someone
## slows them down (and sooner or later they shake it off).
static func step(world: World, dt: float) -> void:
	for l in world.links:
		if not l.broken and not l.step(dt):
			world.fx_event("snap", {"p": l.world_b() if is_instance_valid(l.b) else Vector2.ZERO})
			l.destroy()
		elif l.kind == "glue" and l.a is JellyPoint and l.b is FighterPart and l.b.fighter:
			l.b.fighter.goo_t = maxf(l.b.fighter.goo_t, 0.3)   # a Wiggly stuck on: slow going
			if l.a.wiggly.special_t <= 0.0 and randf() < dt * 0.4:
				# Sticky Mode is over: sooner or later they shake the Gummy off
				world.fx_event("snap", {"p": l.world_b()})
				l.destroy()
	if world.links.any(func(l): return l.broken):
		world.links = world.links.filter(func(l): return not l.broken)


## Power flows from active sources through wires to everything connected.
## A switch, button or timer that is off blocks the flow.
static func step_power(world: World) -> void:
	var ts := world.toys()
	for t in ts:
		t.powered = false
	var adj := {}
	for l in world.links:
		if l.kind != "wire" or l.broken:
			l.signal_on = false
			continue
		if not adj.has(l.uid_a):
			adj[l.uid_a] = []
		adj[l.uid_a].append(l.uid_b)
		if not adj.has(l.uid_b):
			adj[l.uid_b] = []
		adj[l.uid_b].append(l.uid_a)
	var queue: Array = []
	for t in ts:
		if ToyLogic.emits(t):
			queue.append(t.uid)
	var seen := {}
	while not queue.is_empty():
		var u: int = queue.pop_back()
		if seen.has(u):
			continue
		seen[u] = true
		var t = world.things.get(u)
		if t is Toy and not ToyLogic.emits(t):
			t.powered = true
			if ToyLogic.is_source(t):
				continue   # an "off" switch/button/timer stops the power here
		for v in adj.get(u, []):
			if not seen.has(v):
				queue.append(v)
	for l in world.links:
		if l.kind == "wire":
			l.signal_on = seen.has(l.uid_a) and seen.has(l.uid_b)
