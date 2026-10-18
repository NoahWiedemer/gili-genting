extends RefCounted
## Geheim: Der Keller unter dem alten Dorfbrunnen. Hier hat einmal eine junge Hexe geübt.

static func def() -> Dictionary:
	return {
		"name": "Keller unter dem Brunnen", "music": ["cellar", "cliff"], "env": "interior", "cam_dist": 9.5, "cam_pitch": 42.0, "cam_margin": 3.0,
		"weather": ["ash"],
		"rows": [
			"NNNNNNNNNNNN",
			"NnnnnnnnnnnN",
			"NnnnnnnnnnnN",
			"NnnnnqqqnnnN",
			"NnnnnqqqnnnN",
			"NnnnnnnnnnnN",
			"NnnnnnnnnnnN",
			"NNNNNnnNNNNN",
		],
		"decals": [{"sprites": ["g_stain", "g_cracks", "g_moss"], "on": "nq", "density": 0.2}],
		"battle": {"ground": "concrete", "props": ["shelf", "barrel"]},
		"spawns": {"start": [5, 6, 0, -1]},
		"entities": [
			{"type": "light", "x": 6, "z": 2, "y": 1.2, "color": "ff6a30", "energy": 2.4, "range": 5.5, "flicker": true, "shadow": true},
			{"type": "light", "x": 2, "z": 4, "y": 1.0, "color": "b060ff", "energy": 1.4, "range": 4.0, "flicker": true},
			{"type": "prop", "sprite": "altar", "x": 6, "z": 1, "block": true, "lines": [["", "Ein Altar mit niedergebrannten Kerzen. Daneben: eine Sonnenfinsternis-Tabelle. Die nächste ist ... bald."]]},
			{"type": "prop", "sprite": "shelf", "x": 2, "z": 1, "block": true},
			{"type": "prop", "sprite": "shelf", "x": 9, "z": 1, "block": true, "flip": true},
			{"type": "prop", "sprite": "water_jar", "x": 1, "z": 5},
			{"type": "npc", "id": "tagebuch", "sprite": "", "x": 4, "z": 3, "event": "hexen_tagebuch"},
			{"type": "chest", "id": "keller1", "x": 10, "z": 3, "items": {"c_hexenkette": 1}},
			{"type": "warp", "x": 5, "z": 7, "w": 2, "d": 1, "to": "dorf", "spawn": "from_keller"},
		],
	}
