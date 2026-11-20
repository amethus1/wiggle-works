class_name B3Piece
extends StaticBody3D
## One solid block of a structure (B3Struct). Shots chip it, blasts break it
## into physics chunks.

var structure = null
var size := Vector3.ONE
var hp := 100.0
var col := Color.WHITE
var whole := false
var wedge := false


func world_aabb() -> AABB:
	var h := size * 0.5
	var b := AABB(-h, size)
	if wedge:
		b = AABB(Vector3(-h.x, 0, -h.z), size)
	return global_transform * b
