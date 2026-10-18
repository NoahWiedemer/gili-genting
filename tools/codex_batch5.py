#!/usr/bin/env python3
"""Batch 5 (2 images): interior furniture + misc props."""
import sys, os, concurrent.futures as cf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import codex_sheets as cs
NEW = {
    "sheet_interior": "A wide landscape sprite sheet with exactly 12 separate interior furniture sprites arranged in a 4x3 grid, front view, for tropical island huts: "
        "1) a bamboo bed with a batik blanket, 2) a wooden table with bowls of rice, 3) a bamboo shelf with jars and pots, 4) a bar counter with bottles, "
        "5) a hanging oil lamp glowing, 6) a woven rug rolled, 7) a kitchen stove with a clay pot and fire, 8) a blender full of colorful shake (mushroom smoothie bar), "
        "9) a fishing net hanging on a wall rack with floats, 10) an old wooden wardrobe, 11) a small altar with candles and incense, 12) a cracked standing mirror in a wooden frame.",
    "sheet_misc": "A wide landscape sprite sheet with exactly 12 separate small prop sprites arranged in a 4x3 grid, front view: "
        "1) a campfire with logs and a ring of stones, burning, 2) a wooden notice board with papers, 3) a stack of firewood, 4) a clay water jar, "
        "5) a hanging bird cage with a sad chicken inside, 6) a wooden wheelbarrow full of coconuts, 7) a tourist suitcase with stickers, 8) a broken scooter, "
        "9) a pile of plastic trash bags, 10) a dead fish on the ground, 11) a small wooden boat dock post with rope, 12) a rooster weathervane on a pole.",
}
cs.SHEETS.update(NEW)
with cf.ThreadPoolExecutor(max_workers=2) as ex:
    for name, res in ex.map(cs.run, list(NEW)):
        print(name, res, flush=True)
