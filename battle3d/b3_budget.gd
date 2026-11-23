class_name B3Budget
extends RefCounted
## 🪙 Budget battles' rules (🧩 Puzzles, 🌊 Wave Defense), for B3Battle: what
## you may place where, paying for it and getting points back, and who's
## hands-off. Static helpers that take the battle: the numbers themselves
## (budget, spent, build_zone, build_team) stay on B3Battle, where everything
## reads them, and B3Battle passes its can_place, buy, hands_off... on to these.

const POOL_MAX_R := 5.0       # the biggest pool that's still a Pool (see pool_id)
const LAKE_R := 7.0           # 🪙 budget battles: the biggest pool you can buy (a Lake)
const ZONE_SLACK := 1.0       # a building or pool may poke this far out of the glowing area

## Buildings' footprints on the ground (x across, z deep, as spawn_struct
## builds them before turning them by their yaw). A wall is as long as its length.
const FOOT := {"block": Vector2(3, 3), "wall": Vector2(6, 0.6), "ramp": Vector2(2.6, 6), "tower": Vector2(4, 4),
	"bunker": Vector2(5.6, 5.6), "bridge": Vector2(3, 19), "sandbags": Vector2(5, 1.5), "crates": Vector2(3.2, 1.1)}


## Turns on budget battles: `points` to spend, placing only inside `zone`
## (x/z; Rect2() = anywhere) and only for `team` ("" = whatever the Toy Box says).
static func set_budget(b: B3Battle, points: int, zone := Rect2(), team := "") -> void:
	b.budget = points
	b.spent = 0
	b.build_zone = zone
	b.build_team = team
	# the glowing area on the ground where you can build (gone with no zone)
	if b.zone_vis and is_instance_valid(b.zone_vis):
		b.zone_vis.queue_free()
	b.zone_vis = null
	if zone.size != Vector2.ZERO and b.world:
		b.zone_vis = B3Puzzles.zone_visual(b, zone, B3Puzzles.ZONE_COL)
		b.add_child(b.zone_vis)
	b.budget_changed.emit()


static func points_left(b: B3Battle) -> int:
	return b.budget - b.spent if b.budget >= 0 else 1 << 30


## "" if `count` of `id` can go at `pos`, or why not (for a message).
static func can_place(b: B3Battle, id: String, pos: Vector3, count := 1) -> String:
	if b.build_zone.size != Vector2.ZERO and not b.build_zone.has_point(Vector2(pos.x, pos.z)):
		return "🚧 You can only build on your side (the glowing area)."
	# 🌊 Wave Defense: no walls or pools on the 🚩 Fort Keep (fighters may land on its roof)
	var modes := b.modes
	if modes and modes.keep_up and (B3Defs.STRUCTS.has(id) or B3Defs.HAZARDS.has(id)) \
			and Vector2(pos.x - modes.keep_pos.x, pos.z - modes.keep_pos.z).length() < B3Modes.KEEP_R + 2.0:
		return "🚩 That's where the keep stands! Build round it."
	if b.budget >= 0 and B3Defs.cost(id) * count > points_left(b):
		return "🪙 Not enough points for that! You have %d left." % points_left(b)
	return ""


## Pays for `node` (a fighter, building or pool just placed as `id`). The
## price paid stays on it (meta "cost", and in B3Saves snapshots, so ⏮ Reset
## keeps it), and erasing it gives back exactly that.
static func buy(b: B3Battle, node: Node, id: String) -> void:
	if b.budget < 0 or node == null:
		return
	var c := B3Defs.cost(id)
	node.set_meta("cost", c)
	b.spent += c
	b.budget_changed.emit()


## Pays for a stack of crates (spawn_struct("crates") makes 6 props): one
## price for the lot, kept on the first, and they all share meta "stack" so
## erasing any of them before the fight takes (and pays back) the whole stack.
static func buy_stack(b: B3Battle, stack: Array, id: String) -> void:
	if b.budget < 0 or stack.is_empty():
		return
	var sid: int = (stack[0] as Node).get_instance_id()
	for o in stack:
		(o as Node).set_meta("stack", sid)
	buy(b, stack[0] as Node, id)


## 🪙 What a pool of `kind` ("lava" or "acid") with radius `r` is sold as:
## up to 5 m it's a Lava (Acid) Pool, bigger is a Lava Lake (Acid Swamp).
## Pools are priced by their real size, however they were made.
static func pool_id(kind: String, r: float) -> String:
	if r > POOL_MAX_R:
		return "lava_lake" if kind == "lava" else "acid_swamp"
	return kind


## 🪙 Budget battles: how big a pool at `at` can be, at most `r`: no bigger
## than a Lake, and only just over the edge of your side.
static func pool_room(b: B3Battle, at: Vector3, r: float) -> float:
	if b.budget < 0:
		return r
	r = minf(r, LAKE_R)
	var zone := b.build_zone
	if zone.size != Vector2.ZERO:
		var edge := minf(minf(at.x - zone.position.x, zone.end.x - at.x), minf(at.z - zone.position.y, zone.end.y - at.z))
		r = minf(r, maxf(1.5, edge + ZONE_SLACK))
	return r


## `p` moved onto your side (the glowing area), if there is one.
static func zone_clamp(b: B3Battle, p: Vector3) -> Vector3:
	var zone := b.build_zone
	if zone.size == Vector2.ZERO:
		return p
	var x := clampf(p.x, zone.position.x, zone.end.x)
	var z := clampf(p.z, zone.position.y, zone.end.y)
	return Vector3(x, b.world.height_at(x, z), z)


## 🚧 True if building `id` at `at`, turned by `yaw` (a wall `length` long),
## fits on your side (the glowing area, give or take ZONE_SLACK). Always
## true when there's no zone.
static func fits_zone(b: B3Battle, id: String, at: Vector3, yaw: float, length := 0.0) -> bool:
	if b.build_zone.size == Vector2.ZERO:
		return true
	var f: Vector2 = FOOT.get(id, Vector2(3, 3))
	if id == "wall" and length > 0.5:
		f.x = clampf(length, 2.0, 24.0)
	var zone := b.build_zone.grow(ZONE_SLACK)
	var rot := Basis(Vector3.UP, yaw)
	for c in [Vector3(-f.x, 0, -f.y), Vector3(f.x, 0, -f.y), Vector3(f.x, 0, f.y), Vector3(-f.x, 0, f.y)]:
		var w: Vector3 = at + rot * ((c as Vector3) * 0.5)
		if not zone.has_point(Vector2(w.x, w.z)):
			return false
	return true


## 🛡️ True for things nobody may change: a 🧩 puzzle's own army, buildings
## and pools (B3Puzzles.keeps) and 🌊 Wave Defense's attackers (B3Modes.keeps).
## The Eraser, the Inspector's buttons, 🎮 Play as, ✋ Grab and 🚀 Launch
## leave them alone (see hands_off).
static func protected(b: B3Battle, n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if b.puzzle and b.puzzle.keeps(n):
		return true
	return b.modes != null and b.modes.has_method("keeps") and bool(b.modes.call("keeps", n))


## Why `what` ("erase", "team", "mood", "launch", "heal", "play" or "grab")
## can't be done to `n` right now (a message), or "" if it can. Protected
## things (see protected) can't be touched at all. In a 🧩 puzzle your own
## army plays fair too: it stays red, there's no free 💚 healing or 🚀
## launching, and ✋ you can only move it about your side before ▶ Fight!
## (B3Tools keeps it in the glowing area).
static func hands_off(b: B3Battle, n: Node, what: String) -> String:
	var puzzle := b.puzzle
	if protected(b, n):
		var theirs := puzzle != null and puzzle.keeps(n)
		if what == "play":
			return "🎮 You can only play your own army in a puzzle." if theirs else "🎮 You can only play your own side."
		return "🧩 The puzzle's army stays just as it is. Beat it in battle!" if theirs else "🛡️ Hands off! Beat them in battle."
	if puzzle == null:
		return ""
	match what:
		"team":
			return "🧩 Your army stays red in a puzzle."
		"heal":
			return "💚 No free healing in a puzzle. Bring a medic!"
		"launch":
			return "🚀 No launching in a puzzle. Win it in battle!"
		"grab":
			if b.fighting:
				return "✋ No grabbing once the fight's on. Your army's on its own!"
	return ""


## Erasing something you bought before the fight gives its points back.
static func refund(b: B3Battle, node: Node) -> void:
	if b.budget < 0 or node == null or not is_instance_valid(node) or not node.has_meta("cost"):
		return
	if b.fighting and not (b.modes and b.modes.can_refund(node)):
		return      # (🌊 in a break between waves, what you bought since the last one still can)
	b.spent = maxi(0, b.spent - int(node.get_meta("cost")))
	node.remove_meta("cost")
	b.budget_changed.emit()


## After clearing: what's still standing is what's still paid for.
static func recount_spent(b: B3Battle) -> void:
	if b.budget < 0:
		return
	var n := 0
	for arr: Array in [b.units, b.structs, b.hazards, b.props]:
		for o in arr:
			if is_instance_valid(o) and (o as Node).has_meta("cost"):
				n += int((o as Node).get_meta("cost"))
	b.spent = n
	b.budget_changed.emit()
