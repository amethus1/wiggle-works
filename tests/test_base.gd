class_name TestBase
extends Node
## What the headless test suites share: every tests/test_NAME.gd extends it
## (main.gd's --test=NAME runs that one). check() and the summary line at the
## end, waiting a few frames or until something comes true, and for the 3D
## Battle suites a battle `b`: starting a fresh one, letting battle time
## pass, places on its ground, ⚙️ Battle Rules and knock-outs. A suite whose
## helper works differently keeps its own (with the same arguments).
##
## (Nothing here names a 3D Battle class, so the 2D suites don't load 3D Battle.)

var fails := 0
var b = null                      # the 3D battle (start_battle)
var frames_are_steps := false     # frames() waits physics steps instead of drawn frames (the 2D playground suites)


## "ok" or "FAIL" and what was checked (and counts the failures).
func check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


## The summary line tools/run_tests.sh looks for ("test_core: 0 failure(s)"),
## then quits (exit code 1 if anything failed).
func finish() -> void:
	print("%s: %d failure(s)" % [get_script().resource_path.get_file().get_basename(), fails])
	get_tree().quit(1 if fails > 0 else 0)


## Waits `n` drawn frames (or physics steps: frames_are_steps).
func frames(n := 3) -> void:
	for i in n:
		if frames_are_steps:
			await get_tree().physics_frame
		else:
			await get_tree().process_frame


## Presses (or lets go of) key `k`, as if on the keyboard.
func key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


## Every bit of text shown inside `n` (its labels and buttons).
func texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += texts(c)
	return out


## Waits (up to `t` seconds of battle time) until `fn` says yes. The 2D
## suites count physics steps instead (wait_steps_for), and the ones playing
## over the network count real time (wait_real_for).
func wait_for(fn: Callable, t := 3.0) -> bool:
	var end: float = b.time + t
	var guard := 0
	var most := int(t * 60.0 * speed()) + 600
	while not fn.call() and b.time < end and guard < most:
		await get_tree().physics_frame
		guard += 1
	return fn.call()


## Waits up to `sec` seconds of physics steps (120 a second) for `cond`.
func wait_steps_for(cond: Callable, sec: float) -> bool:
	for i in int(sec * 120.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


## Waits up to `secs` real seconds for `cond`.
func wait_real_for(cond: Callable, secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


# ---------------------------------------------------------------- 3D Battle
## The suite's own SPEED: how many times faster than real time its battles
## run (start_battle sets it; sim and wait_for count steps with it).
func speed() -> float:
	return float(get_script().get_script_constant_map().get("SPEED", 1.0))


## Takes the last battle away (and waits for it to go).
func drop_battle() -> void:
	if b and is_instance_valid(b):
		b.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame


## A new battle `b`: `rng_seed` for the random numbers, `opts` for its begin(),
## and SPEED times faster than real time. (Each suite's fresh() says which.)
func start_battle(rng_seed: int, opts: Dictionary) -> void:
	seed(rng_seed)
	b = load("res://battle3d/battle3d.gd").new()
	add_child(b)
	b.begin(opts)
	Engine.physics_ticks_per_second = int(60 * speed())
	Engine.time_scale = speed()


## Waits `t` seconds of battle time.
func sim(t: float) -> void:
	var end: float = b.time + t
	var guard := 0
	var most := int(t * 60.0 * speed()) + 600
	while b.time < end and guard < most:
		await get_tree().physics_frame
		guard += 1


## The spot on the battle's ground at (x, z).
func at(x: float, z: float) -> Vector3:
	return Vector3(x, b.world.height_at(x, z), z)


## Sets a ⚙️ Battle Rule (B3Rules) and puts it to work.
func rule(id: String, v: String) -> void:
	var rules = load("res://battle3d/b3_rules.gd")    # (loaded, not named: see the top)
	rules.set_value(id, v)
	b.apply_rules()


## Knocks fighter `u` out straight away, as if `by` did it.
func ko(u, by = null) -> void:
	if is_instance_valid(u) and not u.dead:
		u.hurt(99999.0, Vector3.UP, 1.0, by, "blast")
