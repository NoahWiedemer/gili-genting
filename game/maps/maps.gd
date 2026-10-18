class_name Maps
extends RefCounted
## Registry of all map definitions.

static func get_def(id: String) -> Dictionary:
	var path := "res://maps/%s.gd" % id
	var s = load(path)
	return s.def()
