extends RefCounted
## Die Strandbar – Bambushütte mit Magic-Mushroom-Shakes.

static func def() -> Dictionary:
	return {
		"name": "Strandbar \"Happy Chicken\"",
		"music": "village", "env": "interior", "cam_dist": 9.5, "cam_pitch": 42.0, "cam_margin": 3.0,
		"rows": [
			"BBBBBBBBBBBB",
			"BwwwwwwwwwwB",
			"BwwwwwwwwwwB",
			"BwwwwwwwwwwB",
			"BwwwwcccwwwB",
			"BwwwwcccwkwB",
			"BwwwwwwwwwwB",
			"BwwwwwwwwwwB",
			"BBBBBwwBBBBB",
		],
		"battle": {"detail": ["coconuts", "pots", "rice_sacks"], "decals": ["g_leaves"], "ground": "wood_planks", "props": ["barrel", "crates"], "lights": [[0, 2.5, 1, "ffa050", 2.0]]},
		"spawns": {"door": [5, 7, 0, -1]},
		"entities": [
			{"type": "light", "x": 3, "z": 3, "y": 1.6, "color": "ffaa55", "energy": 2.2, "range": 5.0, "flicker": true, "shadow": true},
			{"type": "light", "x": 8, "z": 5, "y": 1.6, "color": "ff7a40", "energy": 1.8, "range": 5.0, "flicker": true},
			{"type": "prop", "sprite": "bar_counter", "x": 3, "z": 1, "block": true},
			{"type": "prop", "sprite": "bar_counter", "x": 7, "z": 1, "flip": true, "block": true},
			{"type": "prop", "sprite": "blender", "x": 7, "z": 1, "oy": 0.75, "oz": 0.05},
			{"type": "prop", "sprite": "shelf", "x": 1, "z": 1, "block": true},
			{"type": "prop", "sprite": "shelf", "x": 9, "z": 1, "flip": true, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 2, "z": 3, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 8, "z": 3, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 2, "z": 6, "block": true},
			{"type": "prop", "sprite": "oil_lamp", "x": 5, "z": 1, "oy": 1.2, "glow": 0.8},
			{"type": "prop", "sprite": "coconut_barrow", "x": 9, "z": 6},
			{"type": "prop", "sprite": "suitcase", "x": 10, "z": 6},
			{"type": "npc", "id": "kevin", "sprite": "backpacker", "x": 7, "z": 4, "event": "kevin", "flip": true},
			{"type": "npc", "id": "barwoman", "sprite": "warung_woman", "x": 5, "z": 1, "event": "barwoman"},
			{"type": "chest", "id": "bar1", "x": 10, "z": 2, "items": {"f_kokos": 1}},
			{"type": "warp", "x": 5, "z": 8, "w": 2, "d": 1, "to": "strand", "spawn": "from_bar"},
		],
	}
