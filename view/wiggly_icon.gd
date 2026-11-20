class_name WigglyIcon
extends RefCounted
## Just enough of a Wiggly to draw one as a picture (toy box, menus).

var kind := "bloop"
var def := {}
var size := 1.0
var pts := PackedVector2Array()
var com := Vector2.ZERO
var com_vel := Vector2.ZERO
var angle := 0.0
var t := 0.0
var paint := Color(0, 0, 0, 0)
var mood := "happy"
var look := Vector2(0.6, 0.3)
var blink_t := 1.0
var frozen_t := 0.0
var bubble_t := 0.0
var electric := 0.0
var special_t := 0.0


func shown_color() -> Color:
	return paint if paint.a > 0.0 else def.color


func radius() -> float:
	return Wiggly.BASE_R * size
