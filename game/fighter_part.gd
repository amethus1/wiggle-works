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
		var car := false
		if fighter and fighter.world and fighter.world.cars_on > 0:
			# a driving car keeps bumping whatever it pushes, even slowly (see Fighter._bump)
			var c = s.get_contact_collider_object(i)
			car = c is Toy and c.driving()
		if _prev.has(oid) and not car:
			continue
		var other = s.get_contact_collider_object(i)
		if other is FighterPart and other.fighter == fighter:
			continue
		var nrm := s.get_contact_local_normal(i)   # points from the other thing to us
		var ov := s.get_contact_collider_velocity_at_position(i)
		var rel := s.get_contact_local_velocity_at_position(i) - ov
		var closing := -rel.dot(nrm)
		if fighter and (closing > 120.0 or car) and fighter.world:
			# also pass on how fast the other thing itself was coming at us
			fighter.world.queue_impact("fighter", self, other, closing, s.get_contact_local_position(i), nrm * maxf(0.0, ov.dot(nrm)))
	_prev = seen
