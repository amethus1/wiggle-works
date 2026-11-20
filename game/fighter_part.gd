class_name FighterPart
extends RigidBody2D
## A physics body that belongs to a Fighter: its standing body, or one piece
## of its ragdoll (head, torso, arm, leg, tail…).

var fighter = null
var part := "body"
var half := Vector2(6, 10)   # half size (box parts), or radius in x (round parts)
var round_part := false
var _prev := {}


func _integrate_forces(s: PhysicsDirectBodyState2D) -> void:
	var n := s.get_contact_count()
	if n == 0:
		_prev.clear()
		return
	var seen := {}
	for i in n:
		var oid := s.get_contact_collider_id(i)
		seen[oid] = true
		if _prev.has(oid):
			continue
		var other = s.get_contact_collider_object(i)
		if other is FighterPart and other.fighter == fighter:
			continue
		var rel := s.get_contact_local_velocity_at_position(i) - s.get_contact_collider_velocity_at_position(i)
		var closing := -rel.dot(s.get_contact_local_normal(i))
		if fighter and closing > 120.0 and fighter.world:
			fighter.world.queue_impact("fighter", self, other, closing, s.get_contact_local_position(i))
	_prev = seen
