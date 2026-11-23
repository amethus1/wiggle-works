class_name FighterStatus
## What toys and Wiggly powers do to a fighter when they hit, for Fighter: an
## ice block, a bubble, a zap, goo, a shove, a Bloop's bounce and Twinkle's
## warp. (What goes on every physics step while they last stays in Fighter,
## where it runs quicker: wind, magnets, tractor beams, fire and steam, and
## counting it all down.) Everything here takes the fighter; all the state
## stays in Fighter.


## Thrown by a toy, a Wiggly or a ground pound: `dv` is how fast it throws us.
## Fast enough and we fall over (heavy beasts barely budge); `dmg` hurts a bit.
static func shove(f: Fighter, dv: Vector2, dmg := 0.0, from = null) -> void:
	if f.puppet:
		return
	if f.frozen_t > 0.0:
		if dv.length() < 300.0:
			return
		thaw(f, true)
	if dmg > 0.0:
		f.hurt(dmg, Vector2.ZERO, from)
	if f.state == "stand" and is_instance_valid(f.body):
		if dv.length() >= f.knock_speed():
			f.ragdoll(dv, true)
		else:
			f.body.linear_velocity += dv * 0.5
	else:
		f._soft = true
		FighterRagdoll.wake(f)
		for p in f.all_bodies():
			p.linear_velocity += dv * 0.8


## Frosty or a Freeze Bomb: an ice block, right where we are (even in mid-air).
static func set_frozen(f: Fighter, sec: float) -> void:
	if f.puppet or not f.alive() or sec <= 0.0:
		return
	if f.bubble_t > 0.0:
		pop_bubble(f, false)
	f.frozen_t = minf(sec, Fighter.MAX_FREEZE)
	f.burning = 0.0
	f.stun_t = 0.0
	f.swing = 0.0
	f.hit_t = 0.0
	f.charge_t = 0.0
	f.move = 0.0
	for b in f.all_bodies():
		b.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		b.freeze = true
	f.mood = "frozen"
	f._show_status()


## The ice melts (or gets smashed): we drop out with a crack.
static func thaw(f: Fighter, smash := false) -> void:
	var was := f.frozen_t > 0.0
	f.frozen_t = 0.0
	for b in f.all_bodies():
		if b.freeze:
			b.freeze = false
	if not was:
		return
	if f.alive():
		f.mood = "calm"
	f._show_status()
	f.world.fx_event("ice_pop", {"p": f.center(), "r": f.radius(), "smash": smash})


## Caught in a bubble: floats up, helpless, until it pops.
static func set_bubble(f: Fighter, sec: float) -> void:
	if f.puppet or f.state != "stand" or not f.alive() or f.frozen_t > 0.0 or not is_instance_valid(f.body):
		return
	f.bubble_t = sec
	f.body.gravity_scale = 0.0
	f.body.linear_velocity = Vector2(f.body.linear_velocity.x * 0.3, minf(f.body.linear_velocity.y * 0.1, -40.0))
	f.swing = 0.0
	f.hit_t = 0.0
	f.charge_t = 0.0
	f.mood = "scared"
	f._show_status()


## Pop! `fall`: tumble down as a ragdoll and get back up after.
static func pop_bubble(f: Fighter, fall := true) -> void:
	if f.bubble_t <= 0.0:
		return
	f.bubble_t = 0.0
	if is_instance_valid(f.body):
		f.body.gravity_scale = 0.0 if f.def.get("flies", false) else 1.0
	if f.alive():
		f.mood = "calm"
	f._show_status()
	f.world.fx_event("pop_bubble", {"p": f.center(), "r": f.radius() * 1.3})
	if fall and f.state == "stand":
		f.ragdoll(Vector2(0, -60), true)   # a long way down: a soft landing


## Zappy: a shock that stuns us for a moment. Wet fighters and ones in metal
## armor get it worse.
static func zap(f: Fighter, power := 1.0) -> void:
	if f.puppet or not f.alive() or f.frozen_t > 0.0:
		return
	var k := 1.0 + (0.8 if f.wet > 0.2 else 0.0) + 0.3 * minf(2.0, f.metal())
	f.stun_t = maxf(f.stun_t, 0.9 + 0.5 * k)
	f.swing = 0.0
	f.hit_t = 0.0
	f.charge_t = 0.0
	f.flash = 1.0
	if f.bubble_t > 0.0:
		pop_bubble(f)
	if f.state == "stand" and is_instance_valid(f.body):
		f.body.linear_velocity.y = minf(f.body.linear_velocity.y, -140.0)   # a little jolt
	f.hurt(9.0 * k * power)
	if f.alive():
		f.mood = "zapped"
		f._show_status()


## Gummy or a Glue Bomb: sticky and slow for a while.
static func stick(f: Fighter, sec: float) -> void:
	if f.puppet or not f.alive():
		return
	f.goo_t = maxf(f.goo_t, sec)
	f.charge_t = 0.0
	f._show_status()


## Bounced up off a Bloop (a living trampoline): `v` is how fast. False if
## we've only just bounced.
static func bounce(f: Fighter, v: Vector2) -> bool:
	if f.puppet or f.frozen_t > 0.0 or f.world.vision_time - f._bounce_t < 0.3:
		return false
	f._bounce_t = f.world.vision_time
	if f.state == "stand" and is_instance_valid(f.body):
		f.body.linear_velocity = Vector2(f.body.linear_velocity.x, 0.0) + v
	else:
		f._soft = true
		FighterRagdoll.wake(f)
		for b in f.all_bodies():
			b.linear_velocity = Vector2(b.linear_velocity.x, 0.0) * 0.8 + v
	return true


## Twinkle's warp: pops out at `to` (as a tumbling ragdoll that lands softly).
static func warp_to(f: Fighter, to: Vector2) -> void:
	if f.puppet:
		return
	if f.state == "stand":
		f.ragdoll(Vector2.ZERO, true)
	f._soft = true
	FighterRagdoll.wake(f)
	var by := to - f.center()
	for b in f.all_bodies():
		b.global_position += by
		b.linear_velocity = Vector2(randf_range(-40.0, 40.0), -60.0)
		b.angular_velocity = 0.0
