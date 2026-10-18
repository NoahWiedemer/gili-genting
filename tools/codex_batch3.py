#!/usr/bin/env python3
"""Third Codex batch (12 images): battle/world backdrops + detail prop sheets."""
import sys, os, concurrent.futures as cf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import codex_sheets as cs

BD = ("A very wide panoramic (about 2.4:1) 16-bit SNES / Octopath Traveler style pixel art BACKGROUND LAYER for an RPG battle scene, "
      "no characters, no animals, no text, no UI. Composition: the lower 30% is distant landscape near the horizon, everything is far away, "
      "rich atmospheric perspective and lighting, extremely detailed and beautiful. ")
NEW = {
    "bd_beach": BD + "Tropical Indonesian Gili island beach at bright midday: turquoise lagoon, white sand, distant green volcanic Lombok mountains, "
                "small islands with palms, traditional jukung outrigger boats, fluffy cumulus clouds, deep blue sky.",
    "bd_village": BD + "A tropical island village at dusk: thatched bamboo huts, palm silhouettes, warm glowing lanterns and windows, "
                  "a small Balinese-style shrine, smoke from cooking fires, purple-orange sunset sky with clouds.",
    "bd_steppe": BD + "An abandoned dry steppe at harsh noon: cracked earth, collapsing wooden huts of a banished commune, dead twisted trees, "
                 "heat haze, dusty yellow sky, distant rocky hills, a few vultures circling far away.",
    "bd_cliff": BD + "A violent storm at night over the sea seen from a high jagged basalt cliff: huge waves, lightning in dark clouds, "
                "rain curtains, a small lonely lighthouse far away, cold blue light.",
    "bd_farm": BD + "A farm at full moon night: dark fields, a big red barn, grain silos, a grim white slaughterhouse with a chimney and red lit windows, "
               "windmill, fences, huge glowing full moon, dark blue sky with stars, ominous.",
    "bd_slaughter": BD + "Inside a grim industrial slaughterhouse hall seen deep into the distance: rows of hanging meat hooks on rails, white tiles stained red, "
                    "steel tables, conveyor chains, red emergency lights, steam, dark and horrifying but stylized.",
    "sheet_beach": "A wide landscape sprite sheet with exactly 12 separate small environment prop sprites arranged in a 4x3 grid, front view, for a tropical beach: "
                   "1) a traditional Indonesian jukung outrigger fishing boat, 2) a wooden pier segment, 3) a piece of driftwood, 4) a pile of seashells and a starfish, "
                   "5) coconuts lying on the ground, 6) a washed-up plastic bottle and cans (trash), 7) a surfboard stuck in the sand, 8) a beach towel with a cooler box, "
                   "9) a small rock with seaweed, 10) a tiki torch with flame, 11) a hammock between two short posts, 12) a broken sandcastle.",
    "sheet_village": "A wide landscape sprite sheet with exactly 12 separate small environment prop sprites arranged in a 4x3 grid, front view, for an Indonesian island village: "
                     "1) a market stall with colorful fruits under a cloth roof, 2) a laundry line with clothes, 3) a small Balinese stone shrine with offerings, "
                     "4) a cidomo horse cart (no horse), 5) a wooden chicken coop, 6) a banana tree, 7) stacked rice sacks, 8) a bicycle leaning, "
                     "9) clay pots with plants, 10) a hanging paper lantern string on a post, 11) a canang sari offering basket with flowers on the ground, 12) a wooden bench.",
    "sheet_steppe": "A wide landscape sprite sheet with exactly 12 separate small environment prop sprites arranged in a 4x3 grid, front view, for a dry abandoned steppe: "
                    "1) a cow skull, 2) a broken wooden cart wheel, 3) an old rusty plow, 4) a rusty barrel, 5) a termite mound, 6) a broken stone wall piece, "
                    "7) survey stakes with red-white tape, 8) scattered bones, 9) a dried-out well bucket, 10) a weathered signpost, 11) a thorny dry bush, 12) a pile of rocks.",
    "sheet_farm": "A wide landscape sprite sheet with exactly 12 separate small environment prop sprites arranged in a 4x3 grid, front view, for a grim farm with a slaughterhouse: "
                  "1) round hay bales, 2) a water trough, 3) an old rusty tractor, 4) stacked wire chicken cages, 5) milk cans, 6) a wheelbarrow, "
                  "7) a steel slaughter table with stains, 8) a rack of butcher knives, 9) a red warning lamp on a pole, 10) a feed sack pile, 11) a wooden farm sign, 12) a chopping block with an axe.",
    "sheet_flora": "A wide landscape sprite sheet with exactly 12 separate plant sprites arranged in a 4x3 grid, front view, lush tropical: "
                   "1) a hibiscus bush with red flowers, 2) a bougainvillea bush with magenta flowers, 3) a fern, 4) a bamboo cluster, 5) a small banana plant, "
                   "6) a bird of paradise flower plant, 7) a monstera plant, 8) tall reeds, 9) a small flowering shrub with yellow flowers, 10) wild orchids, "
                   "11) a cluster of small mushrooms, 12) a young palm sapling.",
    "sheet_ground": "A square sprite sheet of exactly 16 separate TOP-DOWN (seen from directly above) flat ground decal sprites arranged in a 4x4 grid, for a pixel art RPG: "
                    "1) small white and yellow flower patch, 2) red flower patch, 3) scattered pebbles, 4) fallen leaves, 5) a small puddle, 6) cracks in dry earth, "
                    "7) clover patch, 8) scattered seashells on sand, 9) footprints in sand, 10) small stones, 11) moss patch, 12) scattered straw, "
                    "13) frangipani blossoms on the ground, 14) twigs, 15) a small dark stain, 16) tiny mushrooms patch.",
}
cs.SHEETS.update(NEW)
if __name__ == "__main__":
    names = sys.argv[1:] or list(NEW)
    with cf.ThreadPoolExecutor(max_workers=12) as ex:
        for name, res in ex.map(cs.run, names):
            print(name, res, flush=True)
