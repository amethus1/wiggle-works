class_name B3Ctl
extends RefCounted
## The controls of one fighter or vehicle that a person is playing. On this
## computer B3Tools fills it from the keyboard and mouse; a friend's comes in
## over the network (B3Net). B3Player.control() reads it every physics step.

var move := Vector3.ZERO     # wanted direction on the ground, world space, length 0..1 (WASD turned by the view)
var steer := Vector2.ZERO    # the raw keys: x = D(+1) / A(-1), y = W(+1) / S(-1)
var lift := 0.0              # Space (+1) / Shift (-1) held: climb or dive in helicopters and planes
var aim := Vector3.ZERO      # the point being aimed at (ground under the mouse, or what the crosshair is on)
var look_yaw := 0.0          # first-person view direction, same convention as B3Unit.facing: atan2(x, z)
var look_pitch := 0.0        # radians, positive looks up
var fire := false            # attack button held (left mouse / F)
var fire2 := false           # second weapon held (right mouse)
var jump := false            # Space pressed (cleared once used)
var fp := false              # looking out of the fighter's eyes (first person)
var windup := ""             # the wind-up a click started (sniper aim, bow, spell), until its shot goes off (B3Player)
var peer := 0                # 0 = this computer, otherwise the friend's network id
var who := ""                # the player's name (shown above friends' fighters)
var color := Color.WHITE


func look_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(sin(look_yaw) * cp, sin(look_pitch), cos(look_yaw) * cp)


func clear_buttons() -> void:
	move = Vector3.ZERO
	steer = Vector2.ZERO
	lift = 0.0
	fire = false
	fire2 = false
	jump = false
	windup = ""


## Packed for the network: friends send this to the host about 30 times a second.
func pack() -> Array:
	return [move.x, move.z, steer.x, steer.y, lift, aim, look_yaw, look_pitch, int(fire) | (int(fire2) << 1) | (int(jump) << 2) | (int(fp) << 3)]


func unpack(a: Array) -> void:
	if a.size() < 9:
		return
	move = Vector3(float(a[0]), 0, float(a[1])).limit_length(1.0)
	steer = Vector2(clampf(float(a[2]), -1, 1), clampf(float(a[3]), -1, 1))
	lift = clampf(float(a[4]), -1, 1)
	if a[5] is Vector3:
		aim = a[5]
	look_yaw = float(a[6])
	look_pitch = clampf(float(a[7]), -1.5, 1.5)
	var bits := int(a[8])
	fire = bits & 1 != 0
	fire2 = bits & 2 != 0
	if bits & 4 != 0:
		jump = true      # stays set until the fighter uses it
	fp = bits & 8 != 0
