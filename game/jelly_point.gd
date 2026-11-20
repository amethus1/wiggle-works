class_name JellyPoint
extends RigidBody2D
## One of the small bodies around the edge of a Wiggly's jelly.

var wiggly = null
var index := 0
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
		if other is JellyPoint and other.wiggly == wiggly:
			continue
		var rel := s.get_contact_local_velocity_at_position(i) - s.get_contact_collider_velocity_at_position(i)
		var closing := -rel.dot(s.get_contact_local_normal(i))
		if wiggly and closing > 60.0 and wiggly.world:
			wiggly.world.queue_impact("jelly", self, other, closing, s.get_contact_local_position(i))
	_prev = seen
