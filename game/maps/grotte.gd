extends RefCounted
## Geheim: Die Gezeitengrotte hinter dem Felsen am Strand.

static func def() -> Dictionary:
	return {
		"name": "Gezeitengrotte", "music": ["cave", "memory"], "ambient": "waves_loop", "env": "dark", "water": true,
		"cam_dist": 10.0, "cam_pitch": 42.0, "cam_margin": 3.0,
		"rows": [
			"CCCCCCCCCCCCCC",
			"CqqqqqCCqqqqqC",
			"Cqq--qqqqq--qC",
			"Cq---qqqq---qC",
			"Cqq--qqqqq-qqC",
			"CqqqqqqqqqqqqC",
			"CqqqqqqqqqqqqC",
			"CqqqqqqqqqqqqC",
			"XXXXXXqqXXXXXX",
		],
		"decor": [{"sprites": ["mushrooms_small", "fern", "seaweed_rock", "shells"], "on": "q", "density": 0.12}],
		"decals": [{"sprites": ["g_moss", "g_puddle", "g_shells"], "on": "q", "density": 0.25}],
		"battle": {"ground": "moss_stone", "props": ["boulder", "crystal"]},
		"spawns": {"start": [6, 7, 0, -1]},
		"entities": [
			{"type": "light", "x": 3, "z": 3, "y": 0.6, "color": "40f0ff", "energy": 2.2, "range": 5.0},
			{"type": "light", "x": 11, "z": 3, "y": 0.6, "color": "40c0ff", "energy": 2.2, "range": 5.0},
			{"type": "stone", "id": "fragment", "x": 7, "z": 2, "event": "grotte_fragment"},
			{"type": "chest", "id": "grotte1", "x": 12, "z": 1, "items": {"l_perle": 1}, "grains": 40},
			{"type": "prop", "sprite": "crystal", "x": 2, "z": 1},
			{"type": "prop", "sprite": "crystal", "x": 9, "z": 5, "glow": 0.6},
			{"type": "warp", "x": 6, "z": 8, "w": 2, "d": 1, "to": "strand", "spawn": "from_grotte"},
		],
	}
