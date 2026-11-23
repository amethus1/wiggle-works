class_name NetDelta
extends RefCounted
## 👥 Small snapshots for playing together (2D playground and 3D Battle).
##
## A host's snapshot is split into tables (fighters, toys, barrels...: id ->
## a row of fields) and single values (the battle's state, the players...).
## Every field is first rounded to what goes over the network: a position
## to the centimetre, an angle to 1/65536 of a turn, health to 1/255... (the
## "wire value"). So something standing still is exactly the same in two
## snapshots, and the fields are packed tightly, not as Godot Variants.
##
## Each friend tells the host the number of the last snapshot it got (an
## "ack", with every snapshot). The next one it's sent only has what's
## different from that one: new rows, the fields that changed in old rows,
## and the rows that are gone. A friend that has just joined, hasn't said
## anything for a while or can't make sense of one gets a whole snapshot
## (a "keyframe") instead. Every snapshot is measured against one the friend
## really has, so a lost packet is simply made up for by the next one:
## nothing stays wrong.

# What a field is, and how it goes over the network.
const STR := 1       # text (up to 1 KB)
const POS := 2       # Vector3 to the centimetre (3 × 24 bits)
const VEL := 3       # Vector3 velocity to 2 cm/s (3 × 16 bits)
const ANG := 4       # an angle, all the way round in 65536 steps
const ROT := 5       # a yaw (float, as ANG) or a turned body (Quaternion, as QUAT)
const QUAT := 6      # Quaternion, 4 × 16 bits
const FRAC := 7      # 0..1 in 255 steps
const FIX16 := 8     # to 1/100, ±327
const FIX32 := 9     # to 1/1000, ±2 million
const F32 := 10      # a float, exactly (32 bits)
const U8 := 11
const U16 := 12
const U32 := 13
const INT := 14      # 32 bits, signed
const BOOL := 15
const VAR := 16      # anything else (Godot's own packing)
const POSC := 17     # Vector3 to 25 cm (3 × 16 bits): knocked-out fighters
const V2 := 18       # Vector2 to 1/8 pixel (2 × 24 bits)
const PTS := 19      # PackedVector2Array (a Wiggly's jelly points): the first to 1/8 px, the rest from it
const NUMS := 21     # null, a short Array of numbers (to 1/1000), or anything else (VAR)
const V2S := 22      # a small Vector2 (a direction) to 1/100 (2 × 16 bits)
const POSE := 23     # a 2D ragdoll's parts, already rounded: PackedInt32Array [x, y, angle, half] each (16, 16, 8, 8 bits)
const I64 := 24      # a whole number, any size (64 bits): a random seed
const ONCE := 256    # (added to a kind) sent with a new row only: never looked at again

const HISTORY := 40          # snapshots each side keeps (2 seconds at 20 a second)
const MAX_ROWS := 20000      # more rows than this in one table is junk


# ------------------------------------------------------------ wire values
## The value `v` as it goes over the network (rounded, see the kinds above).
## Only for the host's own values (it trusts itself). (The kinds a fighter
## has most of come first: this runs for every field that changes.)
static func quant(kind: int, v: Variant) -> Variant:
	match kind:
		FIX16:
			return clampi(roundi(float(v) * 100.0), -32768, 32767)
		V2:
			return Vector2i(((v as Vector2) * 8.0).round()).clamp(V2_MIN, V2_MAX)
		F32:
			return float(v)
		STR:
			return String(v).left(200) if (v is String or v is StringName) else ""
		BOOL:
			return bool(v)
		FRAC:
			return clampi(roundi(float(v) * 255.0), 0, 255)
		POS:
			return Vector3i(((v as Vector3) * 100.0).round()).clamp(POS_MIN, POS_MAX)
		ROT:
			if v is Quaternion:
				return _q4(v)
			return posmod(roundi(float(v) * TURN), 65536)
		VEL:
			return Vector3i(((v as Vector3) * 50.0).round()).clamp(S16_MIN, S16_MAX)
		FIX32:
			return clampi(roundi(float(v) * 1000.0), -2147483647, 2147483647)
		U32:
			return int(v) & 0xffffffff
		U8:
			return clampi(int(v), 0, 255)
		ANG:
			return posmod(roundi(float(v) * TURN), 65536)
		QUAT:
			return _q4(v if v is Quaternion else Quaternion.IDENTITY)
		NUMS:
			if v == null:
				return null
			if v is Array and (v as Array).size() <= 64:
				var nums := PackedInt32Array()
				for x in v:
					if not (x is float or x is int or x is bool):
						return copy(v)
					nums.append(clampi(roundi(float(x) * 1000.0), -2147483647, 2147483647))
				return nums
			return copy(v)
		PTS:
			var out := PackedInt32Array()
			var pts: PackedVector2Array = v
			var n := mini(pts.size(), 4096)
			if n == 0:
				return out
			var p0 := Vector2i((pts[0] * 8.0).round()).clamp(V2_MIN, V2_MAX)
			out.append(p0.x)
			out.append(p0.y)
			for i in range(1, n):
				var d := (Vector2i((pts[i] * 8.0).round()) - p0).clamp(Vector2i(-32768, -32768), Vector2i(32767, 32767))
				out.append(p0.x + d.x)
				out.append(p0.y + d.y)
			return out
		V2S:
			return Vector2i(((v as Vector2) * 100.0).round()).clamp(Vector2i(-32768, -32768), Vector2i(32767, 32767))
		POSC:
			return Vector3i(((v as Vector3) * 4.0).round()).clamp(S16_MIN, S16_MAX)
		INT:
			return clampi(int(v), -2147483647, 2147483647)
		I64:
			return int(v)
		U16:
			return clampi(int(v), 0, 65535)
	return copy(v)


const TURN := 65536.0 / TAU
const POS_MIN := Vector3i(-8388607, -8388607, -8388607)
const POS_MAX := Vector3i(8388607, 8388607, 8388607)
const S16_MIN := Vector3i(-32768, -32768, -32768)
const S16_MAX := Vector3i(32767, 32767, 32767)
const V2_MIN := Vector2i(-8388607, -8388607)
const V2_MAX := Vector2i(8388607, 8388607)


## A copy of `v` that later changes to the game's own lists can't reach
## (the host compares each snapshot with older ones it keeps).
static func copy(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).duplicate(true)
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return v


static func _q4(q: Quaternion) -> Vector4i:
	var n := q.normalized()
	if n.w < 0.0:
		n = -n      # the same turn either way: one way of writing it, so it only changes when the turn does
	return Vector4i(roundi(n.x * 32767.0), roundi(n.y * 32767.0), roundi(n.z * 32767.0), roundi(n.w * 32767.0))


## A wire value back as what the game uses (on the friend's computer).
static func real(kind: int, w: Variant) -> Variant:
	match kind:
		FIX16:
			return float(w) / 100.0
		V2:
			return Vector2(w as Vector2i) / 8.0
		FRAC:
			return float(w) / 255.0
		POS:
			return Vector3(w as Vector3i) / 100.0
		ROT:
			if w is Vector4i:
				return _quat(w)
			return float(w) / TURN
		VEL:
			return Vector3(w as Vector3i) / 50.0
		FIX32:
			return float(w) / 1000.0
		ANG:
			return float(w) / TURN
		QUAT:
			return _quat(w)
		NUMS:
			if w is PackedInt32Array:
				var out: Array = []
				for x in (w as PackedInt32Array):
					out.append(x / 1000.0)
				return out
			return w
		PTS:
			var pts := PackedVector2Array()
			var a: PackedInt32Array = w
			for i in range(0, a.size() - 1, 2):
				pts.append(Vector2(a[i], a[i + 1]) / 8.0)
			return pts
		V2S:
			return Vector2(w as Vector2i) / 100.0
		POSC:
			return Vector3(w as Vector3i) / 4.0
	return w


static func _quat(w: Vector4i) -> Quaternion:
	var q := Quaternion(w.x / 32767.0, w.y / 32767.0, w.z / 32767.0, w.w / 32767.0)
	return q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY


# ------------------------------------------------------------------ packing
static func put(o: StreamPeerBuffer, kind: int, w: Variant) -> void:
	match kind:
		FIX16:
			o.put_16(int(w))
		V2:
			var p2: Vector2i = w
			_put24(o, p2.x)
			_put24(o, p2.y)
		F32:
			o.put_float(float(w))
		STR:
			var b := (w as String).to_utf8_buffer()
			o.put_u16(mini(b.size(), 1024))
			o.put_data(b.slice(0, 1024))
		BOOL:
			o.put_u8(1 if w else 0)
		FRAC, U8:
			o.put_u8(int(w))
		POS:
			var p: Vector3i = w
			_put24(o, p.x)
			_put24(o, p.y)
			_put24(o, p.z)
		ROT:
			if w is Vector4i:
				o.put_u8(1)
				_put_q(o, w)
			else:
				o.put_u8(0)
				o.put_u16(int(w))
		POSC, VEL:
			var p: Vector3i = w
			o.put_16(p.x)
			o.put_16(p.y)
			o.put_16(p.z)
		FIX32, INT:
			o.put_32(int(w))
		U32:
			o.put_u32(int(w))
		ANG, U16:
			o.put_u16(int(w))
		QUAT:
			_put_q(o, w)
		I64:
			o.put_64(int(w))
		NUMS:
			if w == null:
				o.put_u8(0)
			elif w is PackedInt32Array:
				var a: PackedInt32Array = w
				o.put_u8(1)
				o.put_u8(a.size())
				for x in a:
					o.put_32(x)
			else:
				o.put_u8(2)
				_put_var(o, w)
		PTS:
			var a: PackedInt32Array = w
			var n := a.size() / 2
			o.put_u16(n)
			if n == 0:
				return
			_put24(o, a[0])
			_put24(o, a[1])
			for i in range(1, n):
				o.put_16(a[i * 2] - a[0])
				o.put_16(a[i * 2 + 1] - a[1])
		V2S:
			var d: Vector2i = w
			o.put_16(d.x)
			o.put_16(d.y)
		POSE:
			var a: PackedInt32Array = w
			var n := mini(a.size() / 4, 255)
			o.put_u8(n)
			for i in n:
				o.put_16(a[i * 4])
				o.put_16(a[i * 4 + 1])
				o.put_u8(a[i * 4 + 2])
				o.put_u8(a[i * 4 + 3])
		_:
			_put_var(o, w)


static func _put24(o: StreamPeerBuffer, v: int) -> void:
	var u := v & 0xffffff
	o.put_u16(u & 0xffff)
	o.put_u8(u >> 16)


static func _put_q(o: StreamPeerBuffer, q: Vector4i) -> void:
	o.put_16(q.x)
	o.put_16(q.y)
	o.put_16(q.z)
	o.put_16(q.w)


static func _put_var(o: StreamPeerBuffer, v: Variant) -> void:
	var b := var_to_bytes(v)
	o.put_u32(b.size())
	o.put_data(b)


static func _put_id(o: StreamPeerBuffer, id: int) -> void:
	var v := maxi(id, 0)
	while v >= 128:
		o.put_u8((v & 127) | 128)
		v = v >> 7
	o.put_u8(v)


## Reads what put() wrote, never past the end: anything short or odd sets
## `bad` (and the whole snapshot is thrown away).
class Reader extends RefCounted:
	var b := StreamPeerBuffer.new()
	var bad := false

	func _init(data: PackedByteArray) -> void:
		b.data_array = data

	func has(n: int) -> bool:
		if bad or n < 0 or b.get_available_bytes() < n:
			bad = true
			return false
		return true

	func u8() -> int:
		return b.get_u8() if has(1) else 0

	func u16() -> int:
		return b.get_u16() if has(2) else 0

	func s16() -> int:
		return b.get_16() if has(2) else 0

	func s24() -> int:
		if not has(3):
			return 0
		var v := b.get_u16() | (b.get_u8() << 16)
		return v - 0x1000000 if v & 0x800000 else v

	func u32() -> int:
		return b.get_u32() if has(4) else 0

	func s32() -> int:
		return b.get_32() if has(4) else 0

	func f32() -> float:
		var f := b.get_float() if has(4) else 0.0
		if not is_finite(f):
			bad = true
			return 0.0
		return f

	func id() -> int:
		var v := 0
		for i in 9:
			var c := u8()
			if bad:
				return 0
			v |= (c & 127) << (i * 7)
			if c < 128:
				return v
		bad = true
		return 0

	func data(n: int) -> PackedByteArray:
		if not has(n):
			return PackedByteArray()
		var r: Array = b.get_data(n)
		return r[1]

	func text(n: int) -> String:
		return data(n).get_string_from_utf8()

	func variant() -> Variant:
		var n := u32()
		if n > 4 * 1024 * 1024:
			bad = true
			return null
		var raw := data(n)
		if bad:
			return null
		return bytes_to_var(raw) if raw.size() >= 4 else null


## The next value of `kind` from `r` (as a wire value).
static func take(r: Reader, kind: int) -> Variant:
	match kind:
		FIX16:
			return r.s16()
		V2:
			return Vector2i(r.s24(), r.s24())
		F32:
			return r.f32()
		STR:
			return r.text(r.u16())
		BOOL:
			return r.u8() != 0
		FRAC, U8:
			return r.u8()
		POS:
			return Vector3i(r.s24(), r.s24(), r.s24())
		ROT:
			if r.u8() == 1:
				return Vector4i(r.s16(), r.s16(), r.s16(), r.s16())
			return r.u16()
		POSC, VEL:
			return Vector3i(r.s16(), r.s16(), r.s16())
		FIX32, INT:
			return r.s32()
		U32:
			return r.u32()
		ANG, U16:
			return r.u16()
		QUAT:
			return Vector4i(r.s16(), r.s16(), r.s16(), r.s16())
		I64:
			return r.b.get_64() if r.has(8) else 0
		NUMS:
			match r.u8():
				0:
					return null
				1:
					var n := r.u8()
					var a := PackedInt32Array()
					for i in n:
						a.append(r.s32())
					return a
				2:
					return r.variant()
			r.bad = true
			return null
		PTS:
			var n := r.u16()
			var a := PackedInt32Array()
			if n == 0:
				return a
			var x0 := r.s24()
			var y0 := r.s24()
			if not r.has((n - 1) * 4):
				return a
			a.append(x0)
			a.append(y0)
			for i in range(1, n):
				a.append(x0 + r.s16())
				a.append(y0 + r.s16())
			return a
		V2S:
			return Vector2i(r.s16(), r.s16())
		POSE:
			var n := r.u8()
			var a := PackedInt32Array()
			if not r.has(n * 6):
				return a
			for i in n:
				a.append(r.s16())
				a.append(r.s16())
				a.append(r.u8())
				a.append(r.u8())
			return a
	return r.variant()


# ------------------------------------------------------------------ tables
## A table's rows from a list of entries [id, field, field...]: id -> the
## fields as wire values. With last time's entries and rows (`raw`, `last`),
## only the fields that changed are worked out again.
static func rows(list: Array, schema: PackedInt32Array, raw := {}, last := {}) -> Dictionary:
	var out := {}
	var nf := schema.size()
	for e: Array in list:
		var id := int(e[0])
		var pe: Variant = raw.get(id)
		var row: Array
		if pe != null and (pe as Array).size() == e.size() and last.has(id):
			var pa: Array = pe
			if pa == e:
				row = last[id]
			else:
				row = (last[id] as Array).duplicate()
				for f in nf:
					var a: Variant = e[f + 1]
					var b: Variant = pa[f + 1]
					if typeof(a) != typeof(b) or a != b:
						row[f] = quant(schema[f] & 0xff, a)
		else:
			row = []
			row.resize(nf)
			for f in nf:
				row[f] = quant(schema[f] & 0xff, e[f + 1] if e.size() > f + 1 else null)
		out[id] = row
	return out


## A row back as an entry [id, field, field...] the game can use.
static func entry(id: int, row: Array, schema: PackedInt32Array) -> Array:
	var nf := schema.size()
	var e: Array = [id]
	e.resize(nf + 1)
	for f in nf:
		e[f + 1] = real(schema[f] & 0xff, row[f])
	return e


## Writes what changed from table `base` to `cur`: changed and new rows
## (just the changed fields; new rows whole), then the ids that are gone.
static func put_table(o: StreamPeerBuffer, schema: PackedInt32Array, base: Dictionary, cur: Dictionary) -> void:
	var nf := schema.size()
	var full := (1 << nf) - 1
	var ids := PackedInt64Array()
	var masks := PackedInt64Array()
	for id in cur:
		var row: Array = cur[id]
		var old: Variant = base.get(id)
		if old == null:
			ids.append(id)
			masks.append(full)
			continue
		var orow: Array = old
		if row == orow:
			continue
		var mask := 0
		for f in nf:
			if schema[f] & ONCE == 0:
				var a: Variant = row[f]
				var b: Variant = orow[f]
				if typeof(a) != typeof(b) or a != b:
					mask |= 1 << f
		if mask != 0:
			ids.append(id)
			masks.append(mask)
	# rows in id order, each id written as how far it is from the one before
	# (ids made one after another are close together, so that's short)
	var order := PackedInt64Array()
	order.resize(ids.size())
	var by_id := {}
	for i in ids.size():
		by_id[ids[i]] = masks[i]
		order[i] = ids[i]
	order.sort()
	o.put_u32(order.size())
	var prev := 0
	for id in order:
		var mask: int = by_id[id]
		_put_id(o, id - prev)
		prev = id
		_put_mask(o, nf, mask)
		var row: Array = cur[id]
		for f in nf:
			if mask & (1 << f):
				put(o, schema[f] & 0xff, row[f])
	var gone := PackedInt64Array()
	if base.size() + ids.size() > cur.size():
		for id in base:
			if not cur.has(id):
				gone.append(id)
	gone.sort()
	o.put_u32(gone.size())
	prev = 0
	for id in gone:
		_put_id(o, id - prev)
		prev = id


static func _put_mask(o: StreamPeerBuffer, nf: int, mask: int) -> void:
	if nf <= 8:
		o.put_u8(mask)
	elif nf <= 16:
		o.put_u16(mask)
	else:
		o.put_u32(mask)


static func _take_mask(r: Reader, nf: int) -> int:
	if nf <= 8:
		return r.u8()
	if nf <= 16:
		return r.u16()
	return r.u32()


## Reads put_table(): `base` with the changes made (a new table; `base`
## itself isn't touched). The rows read and their fields go in `changed`
## (id -> mask), the ids taken away in `gone`. Check r.bad afterwards.
static func take_table(r: Reader, schema: PackedInt32Array, base: Dictionary, changed := {}, gone: Array = []) -> Dictionary:
	var nf := schema.size()
	var full := (1 << nf) - 1
	var out := base.duplicate()
	var n := r.u32()
	if n > MAX_ROWS:
		r.bad = true
		return out
	var id := 0
	for k in n:
		id += r.id()
		var mask := _take_mask(r, nf)
		if r.bad or mask & ~full != 0:
			r.bad = true
			return out
		var old: Variant = out.get(id)
		var row: Array
		if old == null:
			if mask != full:
				r.bad = true      # a change to a row we don't have
				return out
			row = []
			row.resize(nf)
		else:
			row = (old as Array).duplicate()
		for f in nf:
			if mask & (1 << f):
				row[f] = take(r, schema[f] & 0xff)
		if r.bad:
			return out
		out[id] = row
		changed[id] = mask if old != null else full
	var g := r.u32()
	if g > MAX_ROWS:
		r.bad = true
		return out
	id = 0
	for k in g:
		id += r.id()
		if out.has(id):
			out.erase(id)
			gone.append(id)
	return out


# ------------------------------------------------------------------ host
## The host's side: keeps the last snapshots it made and packs each friend
## what changed since the last one that friend got.
class Sender extends RefCounted:
	var tables: Array = []       # [[name, schema], ...] in order
	var msg := "snap"
	var n := 0                   # this snapshot's number
	var hist := {}               # number -> {"t": {name: rows}, "g": {name: value}}
	var keyframes := 0           # whole snapshots sent (for tests)
	var _cache := {}             # base number -> this snapshot packed against it
	var _raw := {}               # name -> {id: last entry}: fields that didn't change aren't rounded again

	func _init(t: Array, m := "snap") -> void:
		tables = t
		msg = m

	## Adds this tick's snapshot: `lists` has each table's entries [id,
	## field, field...], `g` the single values.
	func push(lists: Dictionary, g: Dictionary) -> void:
		var t := {}
		var last: Dictionary = (hist[n].t as Dictionary) if hist.has(n) else {}
		for tp: Array in tables:
			var name: String = tp[0]
			var list: Array = lists.get(name, [])
			t[name] = NetDelta.rows(list, tp[1], _raw.get(name, {}), last.get(name, {}))
			var raw := {}
			for e: Array in list:
				raw[int(e[0])] = e
			_raw[name] = raw
		var gs := {}
		for k in g:
			gs[k] = NetDelta.copy(g[k])
		n += 1
		hist[n] = {"t": t, "g": gs}
		hist.erase(n - NetDelta.HISTORY)
		_cache.clear()

	## This snapshot for a friend whose last one is number `ack` (-1 if none,
	## or one we no longer have: then they get all of it).
	func packet(ack: int) -> PackedByteArray:
		var b := ack if ack > 0 and ack < n and hist.has(ack) else -1
		if _cache.has(b):
			return _cache[b]
		if b < 0:
			keyframes += 1
		var cur: Dictionary = hist[n]
		var base: Dictionary = hist[b] if b > 0 else {"t": {}, "g": {}}
		var o := StreamPeerBuffer.new()
		for tp: Array in tables:
			NetDelta.put_table(o, tp[1], (base.t as Dictionary).get(tp[0], {}), (cur.t as Dictionary).get(tp[0], {}))
		var g := {}
		var bg: Dictionary = base.g
		for k in cur.g:
			var v: Variant = cur.g[k]
			if not bg.has(k) or typeof(bg[k]) != typeof(v) or bg[k] != v:
				g[k] = v
		var pkt := NetCommon.encode({"m": msg, "n": n, "b": b, "g": g, "t": o.data_array})
		_cache[b] = pkt
		return pkt


# ------------------------------------------------------------------ friend
## A friend's side: rebuilds each whole snapshot from the host's packet and
## the earlier one it's measured against, and keeps the game's own entries
## of it up to date (only the fields that changed, when it can).
class Receiver extends RefCounted:
	var tables: Array = []
	var hist := {}
	var last := 0                # the newest snapshot we have
	var need_full := false       # we got one we couldn't use: ask for all of it
	var got := 0                 # snapshots rebuilt (for tests)
	var ents := {}               # name -> {id: entry [id, field...]} of the newest snapshot
	var singles := {}            # ...and its single values

	func _init(t: Array) -> void:
		tables = t

	## Takes the host's packet `d`. True if it made a new whole snapshot
	## (see snapshot()); false if it's junk, old, or measured against one we
	## don't have (then need_full is set).
	func take(d: Dictionary) -> bool:
		var nv: Variant = d.get("n")
		var bv: Variant = d.get("b")
		var tv: Variant = d.get("t")
		var gv: Variant = d.get("g")
		if not (nv is int and bv is int and tv is PackedByteArray and gv is Dictionary):
			return false
		var n := int(nv)
		var b := int(bv)
		if n <= last and b >= 0:
			return false      # an old one, after a newer one
		var base: Dictionary = {"t": {}, "g": {}}
		if b >= 0:
			if not hist.has(b):
				need_full = true
				return false
			base = hist[b]
		var r := NetDelta.Reader.new(tv)
		var t := {}
		var changes := {}
		var gones := {}
		for tp: Array in tables:
			var ch := {}
			var gn: Array = []
			t[tp[0]] = NetDelta.take_table(r, tp[1], (base.t as Dictionary).get(tp[0], {}), ch, gn)
			if r.bad:
				need_full = true
				return false
			changes[tp[0]] = ch
			gones[tp[0]] = gn
		var g: Dictionary = (base.g as Dictionary).duplicate()
		for k in gv:
			if k is String:
				g[k] = gv[k]
		# the game's entries: just what changed if this was measured against
		# the newest we had, otherwise all of them again
		var step := b == last and b > 0
		for tp: Array in tables:
			var name: String = tp[0]
			var schema: PackedInt32Array = tp[1]
			var rows: Dictionary = t[name]
			if not step or not ents.has(name):
				var all := {}
				for id in rows:
					all[id] = NetDelta.entry(int(id), rows[id], schema)
				ents[name] = all
				continue
			var es: Dictionary = ents[name]
			var ch: Dictionary = changes[name]
			for id in ch:
				var mask: int = ch[id]
				var old: Variant = es.get(id)
				if old == null or mask == (1 << schema.size()) - 1:
					es[id] = NetDelta.entry(int(id), rows[id], schema)
				else:
					var e: Array = (old as Array).duplicate()
					var row: Array = rows[id]
					for f in schema.size():
						if mask & (1 << f):
							e[f + 1] = NetDelta.real(schema[f] & 0xff, row[f])
					es[id] = e
			for id in gones[name]:
				es.erase(id)
		singles = g
		var s := {"t": t, "g": g}
		hist[n] = s
		for k in hist.keys():
			if int(k) <= n - NetDelta.HISTORY:
				hist.erase(k)
		last = n
		need_full = false
		got += 1
		return true

	## The newest whole snapshot as the host made it: {table: [entry...], single: value}.
	func snapshot() -> Dictionary:
		var out := {}
		for tp: Array in tables:
			out[tp[0]] = (ents.get(tp[0], {}) as Dictionary).values()
		for k in singles:
			out[k] = singles[k]
		return out
