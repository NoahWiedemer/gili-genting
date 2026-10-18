extends RefCounted
## Das Schlachthaus. Hier endet es. So oder so.

static func def() -> Dictionary:
	return {
		"name": "Schlachthaus", "music": "", "ambient": "night_loop", "env": "slaughter", "cam_dist": 10.5, "cam_pitch": 40.0, "cam_margin": 3.0,
		"rows": [
			"NNNNNNNNNNNNNNNN",
			"NtttjtttjtttjttN",
			"NtttttttttttttAN",
			"NtAAttttttttttAN",
			"NttttttjtttttttN",
			"NttttttttttttttN",
			"NtttjttttttjtttN",
			"NttttttttttttttN",
			"NNNNNNNttNNNNNNN",
		],
		"battle": {"ground": "tile_floor", "props": ["meathook", "knife_rack", "cages"], "backdrop": "bd_slaughter", "horizon": 0.6,
			"detail": ["slaughter_table", "knife_rack", "meathook", "milkcans"], "decals": ["g_stain", "g_puddle"], "lights": [[-3, 2.5, -1, "ff2020", 3.0], [3, 2.5, -1, "ff4040", 2.0]]},
		"spawns": {"door": [7, 7, 0, -1]},
		"entities": [
			{"type": "light", "x": 4, "z": 2, "y": 2.2, "color": "ff2a20", "energy": 3.0, "range": 7.0, "flicker": true, "shadow": true},
			{"type": "light", "x": 11, "z": 3, "y": 2.2, "color": "ff3a30", "energy": 2.5, "range": 7.0, "flicker": true},
			{"type": "light", "x": 7, "z": 5, "y": 2.4, "color": "c0d0ff", "energy": 0.8, "range": 5.0},
			{"type": "npc", "id": "bauer", "sprite": "bauer", "x": 6, "z": 3, "event": "finale", "unless": "bauer_dead"},
			{"type": "npc", "id": "butcher", "sprite": "butcher", "x": 9, "z": 2, "event": "finale", "unless": "butcher_dead", "flip": true},
			{"type": "trigger", "id": "finale_t", "x": 3, "z": 4, "w": 10, "d": 2, "event": "finale", "unless": "bauer_dead", "once": false},
			{"type": "warp", "x": 7, "z": 8, "w": 2, "d": 1, "to": "hof", "spawn": "from_schlacht", "unless": "butcher_dead"},
		],
	}
