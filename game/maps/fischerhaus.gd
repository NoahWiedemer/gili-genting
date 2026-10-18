extends RefCounted
## Haus des Fischers – riecht nach Fisch, Schweiß und Pilz-Smoothie.

static func def() -> Dictionary:
	return {
		"name": "Haus des Fischers", "music": "village", "env": "interior", "cam_dist": 9.5, "cam_pitch": 42.0, "cam_margin": 3.0,
		"rows": [
			"WWWWWWWWWWWW",
			"WwwwwwwwkxxW",
			"WwwwwwwwwwwW",
			"WwwwwwwwwwwW",
			"WwwwwwccwwwW",
			"WwwwwwccwwwW",
			"WwwwwwwwwwwW",
			"WWWWWwwWWWWW",
		],
		"battle": {"detail": ["driftwood", "shells", "bucket"], "decals": ["g_shells"], "ground": "wood_planks", "props": ["barrel", "crates"], "lights": [[0, 2.5, 1, "ffa050", 2.0]]},
		"spawns": {"door": [5, 6, 0, -1]},
		"entities": [
			{"type": "light", "x": 3, "z": 2, "y": 1.7, "color": "ff9a4a", "energy": 2.4, "range": 5.5, "flicker": true, "shadow": true},
			{"type": "prop", "sprite": "bed", "x": 9, "z": 3, "block": true},
			{"type": "prop", "sprite": "net_rack", "x": 1, "z": 1, "block": true},
			{"type": "prop", "sprite": "stove", "x": 4, "z": 1, "block": true},
			{"type": "prop", "sprite": "wardrobe", "x": 6, "z": 1, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 3, "z": 3, "block": true},
			{"type": "prop", "sprite": "dead_fish", "x": 4, "z": 4},
			{"type": "prop", "sprite": "water_jar", "x": 1, "z": 5},
			{"type": "prop", "sprite": "oil_lamp", "x": 7, "z": 3, "oy": 1.3, "glow": 0.8},
			{"type": "enemy", "id": "f_sleep", "x": 8, "z": 5, "group": ["fisher"], "sleeping": true, "radius": 0.5, "intro": "Wer ... wer weckt mich?! Ein HUHN?!"},
			{"type": "pickup", "id": "pilz_fisch", "x": 2, "z": 2, "item": "k_pilz", "event": "pilz"},
			{"type": "pickup", "id": "karte", "x": 5, "z": 4, "item": "k_karte", "event": "karte"},
			{"type": "chest", "id": "fisch1", "x": 10, "z": 2, "items": {"f_wurm": 1}, "grains": 15},
			{"type": "warp", "x": 5, "z": 7, "w": 2, "d": 1, "to": "dorf", "spawn": "from_fischer"},
		],
	}
