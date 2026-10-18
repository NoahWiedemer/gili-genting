class_name Dof
extends RefCounted
## HD-2D tilt-shift depth of field: a sharp band around the focus distance,
## soft blur for everything far away (top of screen) and very close (bottom of screen).

static func make(focus: float, near_gap := 3.0, far_gap := 2.2, amount := 0.11) -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	if not Game.settings.get("dof", true):
		return a
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = focus + far_gap
	a.dof_blur_far_transition = 5.5
	a.dof_blur_near_enabled = true
	a.dof_blur_near_distance = max(0.5, focus - near_gap)
	a.dof_blur_near_transition = 2.2
	a.dof_blur_amount = amount
	return a
