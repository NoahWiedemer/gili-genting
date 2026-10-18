extends RefCounted
## Der weiße Raum. Eine Heuschrecke singt ihr Todeslied.

static func def() -> Dictionary:
	var rows := []
	for z in 18:
		var r := ""
		for x in 26:
			r += "V" if (x == 0 or z == 0 or x == 25 or z == 17) else "v"
		rows.append(r)
	return {
		"name": "", "music": "void", "env": "void", "dof": true,
		"weather": ["void"],
		"rows": rows,
		"on_enter": "void_enter",
		"battle": {"ground": "white_void", "props": ["dead_tree"]},
		"spawns": {"start": [6, 9, 1, 0]},
		"entities": [
			{"type": "npc", "id": "grasshopper", "sprite": "grasshopper", "x": 15, "z": 9, "event": "heuschrecke", "flip": true, "ants": true},
		],
	}
