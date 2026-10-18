extends RefCounted
## Epilog: Das Haus der alten Dame – während der Sonnenfinsternis.

static func def() -> Dictionary:
	return {
		"name": "Haus der alten Dame", "music": "cliff", "ambient": "fire_loop", "env": "eclipse", "cam_dist": 9.5, "cam_pitch": 42.0, "cam_margin": 3.0,
		"weather": ["ash"],
		"rows": [
			"WWWWWWWWWWWW",
			"WwwwwwwwwwwW",
			"WwwwwwwwwwwW",
			"WwwwwwwcccwW",
			"WwwwwwwcccwW",
			"WwwwwwwwwwwW",
			"WwwwwwwwwwwW",
			"WWWWWwwWWWWW",
		],
		"on_enter": "epilog_enter",
		"battle": {"ground": "wood_planks", "props": ["barrel"]},
		"spawns": {"start": [5, 6, 0, -1]},
		"entities": [
			{"type": "light", "x": 3, "z": 2, "y": 1.6, "color": "ff5030", "energy": 2.6, "range": 6.0, "flicker": true, "shadow": true},
			{"type": "light", "x": 9, "z": 5, "y": 1.2, "color": "ffa060", "energy": 1.6, "range": 4.0, "flicker": true},
			{"type": "npc", "id": "witch", "sprite": "witch", "x": 8, "z": 4, "event": "witch", "unless": "witch_gone", "flip": true},
			{"type": "npc", "id": "buch", "sprite": "", "x": 4, "z": 2, "event": "buch"},
			{"type": "prop", "id": "spiegel", "sprite": "mirror_stand", "x": 10, "z": 1, "event": "spiegel", "block": true},
			{"type": "prop", "sprite": "altar", "x": 6, "z": 1, "block": true, "lines": [["", "Ein kleiner Altar. Räucherstäbchen, Blumen, ein Schädel. Der Schädel ist nicht von einem Huhn. Beruhigend."]]},
			{"type": "prop", "sprite": "shelf", "x": 1, "z": 1, "block": true},
			{"type": "prop", "sprite": "wardrobe", "x": 2, "z": 1, "block": true},
			{"type": "prop", "sprite": "table_rice", "x": 3, "z": 3, "block": true},
			{"type": "prop", "sprite": "bed", "x": 9, "z": 5, "block": true},
			{"type": "prop", "sprite": "oil_lamp", "x": 5, "z": 3, "oy": 1.3, "glow": 0.9},
		],
	}
