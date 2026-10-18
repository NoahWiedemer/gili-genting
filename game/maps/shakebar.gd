extends RefCounted
## Magic-Shake-Bar – hier werden Pilze zu Smoothies. Und Touristen zu Pflanzen.

static func def() -> Dictionary:
	return {
		"name": "Magic Shakes", "music": "village", "env": "interior", "cam_dist": 10.0, "cam_pitch": 42.0, "cam_margin": 3.0,
		"rows": [
			"BBBBBBBBBBBBBB",
			"BwwwwwwwwwkkxB",
			"BwwwwwwwwwwwwB",
			"BwwwwwcccwwwwB",
			"BwwwwwcccwwwwB",
			"BwwwwwwwwwwwxB",
			"BwwwwwwwwwwwwB",
			"BwwwwwwwwwwwwB",
			"BBBBBBwwBBBBBB",
		],
		"battle": {"detail": ["mushrooms_small", "pots", "orchids"], "decals": ["g_mush", "g_leaves"], "ground": "wood_planks", "props": ["barrel", "crates", "bush"], "lights": [[0, 2.5, 1, "c070ff", 2.0], [3, 2, -1, "50ffb0", 1.5]]},
		"spawns": {"door": [6, 7, 0, -1]},
		"entities": [
			{"type": "light", "x": 3, "z": 3, "y": 1.6, "color": "c060ff", "energy": 2.5, "range": 5.0, "flicker": true},
			{"type": "light", "x": 10, "z": 4, "y": 1.6, "color": "40ffb0", "energy": 2.2, "range": 5.0, "flicker": true},
			{"type": "light", "x": 6, "z": 1, "y": 1.8, "color": "ffb060", "energy": 1.6, "range": 4.0},
			{"type": "prop", "sprite": "bar_counter", "x": 4, "z": 1, "block": true},
			{"type": "prop", "sprite": "bar_counter", "x": 6, "z": 1, "flip": true, "block": true},
			{"type": "prop", "sprite": "blender", "x": 4, "z": 1, "oy": 0.75, "oz": 0.05},
			{"type": "prop", "sprite": "blender", "x": 6, "z": 1, "oy": 0.75, "oz": 0.05},
			{"type": "prop", "sprite": "shelf", "x": 8, "z": 1, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 2, "z": 3, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 11, "z": 3, "block": true},
			{"type": "prop", "sprite": "rug", "x": 7, "z": 6},
			{"type": "prop", "sprite": "mushrooms_small", "x": 1, "z": 6},
			{"type": "prop", "sprite": "oil_lamp", "x": 5, "z": 3, "oy": 1.4, "glow": 1.0},
			{"type": "enemy", "id": "s_stoned1", "x": 4, "z": 5, "group": ["tourist_m", "tourist_f"], "sleeping": true, "radius": 0.5, "intro": "Duuude ... die Farben ... das Huhn hat ein MESSER ..."},
			{"type": "enemy", "id": "s_stoned2", "x": 9, "z": 6, "group": ["tourist_f"], "sleeping": true, "radius": 0.5, "intro": "Ist das ... Teil vom Trip?"},
			{"type": "pickup", "id": "pilz_mixer", "x": 2, "z": 2, "item": "k_pilz", "event": "pilz"},
			{"type": "chest", "id": "shake1", "x": 12, "z": 6, "items": {"f_shake": 1}},
			{"type": "warp", "x": 6, "z": 8, "w": 2, "d": 1, "to": "dorf", "spawn": "from_shake"},
		],
	}
