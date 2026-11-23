class_name B3Grid
extends RefCounted
## The fighters' map (speed), for B3Battle (its `grid`).
## Standing fighters sorted into CELL-metre squares, so "who's near here?"
## only looks at a few squares instead of every fighter on the field. It's
## made once per physics step, the first time something asks: fighters only
## move in the physics engine's step after all the scripts, so it stays right
## all step long (ones placed or getting up during the step are added as they
## come). It's only a first sort: callers still check the real distances, and
## knocked-out or knocked-down fighters in it are skipped.
## With only a few fighters on the field, outside the physics step and on a
## friend's copy it isn't made: everyone is simply looked at, in `units` order.
## B3Battle passes its grid_on, units_near, grid_ring... on to this.

const CELL := 6.0
const FAR := 2000.0                # further out than this (about to be removed): always looked at
var battle: B3Battle
var min_n := 64                    # fewer fighters than this: not worth making (tests set 0, as B3Battle.grid_min)
var big_r := 0.0                   # the biggest radius of a fighter in it
var cells := {}                    # square (cell_x * 4096 + cell_z) -> Array[B3Unit]
var _far: Array[B3Unit] = []
var step := -1                     # the physics step it was made (or not made) for
var _on := false                   # it's made for this step
var _num_step := -1                # the physics step everyone was numbered for without it
var _n := 0                        # the next order number (B3Unit.grid_i, the order of `units`)
var _count := 0
var _x0 := 0                       # the squares anyone is in
var _x1 := -1
var _z0 := 0
var _z1 := -1
var _foes_step := -1               # the physics step _side_n was counted for (foes_standing)
var _side_n := {}                  # side ("red", or "wild:wolf" for wild ones) -> fighters standing on it
var _standing_n := 0


func _init(b: B3Battle) -> void:
	battle = b


## True if the map is made and good for this physics step (making it if
## it's worth it: B3Unit._think looks at everyone in one go if not).
func on() -> bool:
	if battle.puppet or not Engine.is_in_physics_frame():
		return false
	var f := Engine.get_physics_frames()
	if step != f:
		step = f
		_on = battle.units.size() >= min_n
		if _on:
			_build()
	return _on


## Every fighter, numbered in order (B3Unit.grid_i), for when there's no map.
func everyone() -> Array[B3Unit]:
	if not on():
		var f := Engine.get_physics_frames() if Engine.is_in_physics_frame() else -1
		if f < 0 or f != _num_step:
			_num_step = f
			_number()
	return battle.units


func _build() -> void:
	cells.clear()
	_far.clear()
	# (_put, written out here: this runs for every fighter every step)
	var i := 0
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var z0 := 1 << 30
	var z1 := -(1 << 30)
	var rmax := 0.0
	var n := 0
	for u in battle.units:
		u.grid_i = i
		i += 1
		if u.down:
			continue
		var p := u.position
		if u.radius > rmax:
			rmax = u.radius
		n += 1
		if absf(p.x) > FAR or absf(p.z) > FAR:
			_far.append(u)
			continue
		var cx := floori(p.x / CELL)
		var cz := floori(p.z / CELL)
		if cx < x0:
			x0 = cx
		if cx > x1:
			x1 = cx
		if cz < z0:
			z0 = cz
		if cz > z1:
			z1 = cz
		var k := cx * 4096 + cz
		var a = cells.get(k)
		if a == null:
			var na: Array[B3Unit] = [u]
			cells[k] = na
		else:
			(a as Array[B3Unit]).append(u)
	_n = i
	_count = n
	big_r = rmax
	_x0 = x0
	_x1 = x1
	_z0 = z0
	_z1 = z1


## Everyone's been cleared away: forget the map (it would otherwise hold on
## to the old fighters, and their size, until the next one is made).
func reset() -> void:
	cells.clear()
	_far.clear()
	big_r = 0.0
	step = -1
	_on = false
	_num_step = -1
	_n = 0
	_count = 0
	_x0 = 0
	_x1 = -1
	_z0 = 0
	_z1 = -1
	_foes_step = -1
	_side_n.clear()
	_standing_n = 0


## Without the map: just numbers everyone in order (B3Unit.grid_i).
func _number() -> void:
	var units := battle.units
	for i in units.size():
		units[i].grid_i = i
	_n = units.size()


func _put(u: B3Unit) -> void:
	var p := u.position
	if u.radius > big_r:
		big_r = u.radius
	_count += 1
	if absf(p.x) > FAR or absf(p.z) > FAR:
		_far.append(u)
		return
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	if cx < _x0:
		_x0 = cx
	if cx > _x1:
		_x1 = cx
	if cz < _z0:
		_z0 = cz
	if cz > _z1:
		_z1 = cz
	var k := cx * 4096 + cz
	var a = cells.get(k)
	if a == null:
		var na: Array[B3Unit] = [u]
		cells[k] = na
	else:
		(a as Array[B3Unit]).append(u)


## A fighter placed (or getting up) in the middle of a physics step goes on
## the map too, if it's already been made for this step.
func add(u: B3Unit, new_unit: bool) -> void:
	if step != Engine.get_physics_frames() or not Engine.is_in_physics_frame() or battle.puppet:
		return
	if new_unit:
		u.grid_i = _n      # (or numbered with everyone, if that's still to come)
		_n += 1
	if _on:
		_put(u)
	_foes_step = -1


## False only if nobody standing could be `u`'s enemy (B3Unit.is_enemy) this
## physics step: then there's no point searching the whole field for one (a
## battle that's been won, or one side alone on the field).
func foes_standing(u: B3Unit) -> bool:
	if not on():
		return true
	if _foes_step != step:
		_foes_step = step
		_side_n.clear()
		_standing_n = 0
		for o in battle.units:
			if not o.down:
				var side: String = o.team if o.team != "wild" else "wild:" + o.kind
				_side_n[side] = int(_side_n.get(side, 0)) + 1
				_standing_n += 1
	var mine: String = u.team if u.team != "wild" else "wild:" + u.kind
	return _standing_n > int(_side_n.get(mine, 0))


## Someone changed sides in the middle of a step: count again.
func foes_changed() -> void:
	_foes_step = -1


## Every fighter that could be within `r` metres of `p` (across the ground:
## x and z), in no particular order. Check the real distance, and skip the
## knocked-down (`down`) and knocked-out (`dead`) ones. `r` grows by
## `biggest` times the biggest fighter's radius (1.0 for "touching": my
## reach plus their radius). It may be `units` itself: don't add or remove
## fighters while going through it (collect who to hit first).
func near(p: Vector3, r: float, biggest := 0.0) -> Array[B3Unit]:
	if not on():
		return everyone()
	r += biggest * big_r
	var out: Array[B3Unit] = []
	var x0 := maxi(floori((p.x - r) / CELL), _x0)
	var x1 := mini(floori((p.x + r) / CELL), _x1)
	var z0 := maxi(floori((p.z - r) / CELL), _z0)
	var z1 := mini(floori((p.z + r) / CELL), _z1)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var a = cells.get(cx * 4096 + cz)
			if a != null:
				out.append_array(a)
	if not _far.is_empty():
		out.append_array(_far)
	return out


## For searching outwards from `p` square by square (see B3Unit._think):
## the fighters in the squares `ring` steps out (0: the square `p` is in).
## Everyone in ring r is at least (r - 1) * CELL metres away. Past
## rings(p) there's nobody. Searching out that far would mean looking at
## more squares than there are fighters, so past ring_cap() it's better
## to just look at everyone (`units`).
func ring(p: Vector3, ring_i: int) -> Array[B3Unit]:
	var out: Array[B3Unit] = []
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	if ring_i == 0:
		var a = cells.get(cx * 4096 + cz)
		if a != null:
			out.append_array(a)
		if not _far.is_empty():
			out.append_array(_far)
		return out
	# the top and bottom rows, then the two sides between them
	for zz in [cz - ring_i, cz + ring_i]:
		var z: int = zz
		if z < _z0 or z > _z1:
			continue
		for x in range(maxi(cx - ring_i, _x0), mini(cx + ring_i, _x1) + 1):
			var a = cells.get(x * 4096 + z)
			if a != null:
				out.append_array(a)
	for xx in [cx - ring_i, cx + ring_i]:
		var x: int = xx
		if x < _x0 or x > _x1:
			continue
		for z in range(maxi(cz - ring_i + 1, _z0), mini(cz + ring_i - 1, _z1) + 1):
			var a = cells.get(x * 4096 + z)
			if a != null:
				out.append_array(a)
	return out


## How many rings out from `p` anyone could be (-1: nobody, or no map now).
func rings(p: Vector3) -> int:
	if not on():
		return -1
	if _count == 0:
		return -1
	if _x1 < _x0:
		return 0      # (only far-off ones, in ring 0)
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	return maxi(maxi(cx - _x0, _x1 - cx), maxi(cz - _z0, _z1 - cz))


func ring_cap() -> int:
	return int(sqrt(float(_count)) * 0.5) + 1
