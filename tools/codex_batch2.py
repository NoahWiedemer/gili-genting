#!/usr/bin/env python3
"""Second Codex batch (10 images): portraits, story illustrations, extra sprites."""
import sys, os, concurrent.futures as cf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import codex_sheets as cs

PORTRAIT = ("16-bit SNES-era pixel art RPG dialogue portraits (bust shots, head and shoulders, facing slightly right), "
            "in the style of Final Fantasy VI portraits, crisp hard square pixels, limited palette, dark outline, "
            "each portrait clearly separated by wide empty space, all the same size, arranged in one neat row, "
            "on a flat solid pure magenta (#FF00FF) background, no frames, no text, no labels.")
ILLU = ("A widescreen 16:9 pixel art story illustration in 16-bit SNES / Octopath Traveler style, fill the whole image, "
        "rich dramatic lighting, melancholic dark-humor tone, no text, no letters. ")
NEW = {
    "portraits_a": "Exactly 5 portraits: 1) a determined white hen with red comb and intense dark eyes (heroine), "
                   "2) a giant muscular golden-brown rooster with a scar over one eye but gentle eyes, "
                   "3) a very old grey hen with one cloudy white blind eye and a purple knitted shawl, "
                   "4) a scruffy black-and-white speckled hen with bald patches and crazy wide eyes, "
                   "5) a dramatic red-orange hen with a monocle and a tiny red fez. " + PORTRAIT,
    "portraits_b": "Exactly 5 portraits: 1) a small dead white shark floating belly-up with X eyes but talking, "
                   "2) a green grasshopper with a sad wise face, 3) a calm old island witch woman with long white hair and flowers, "
                   "4) a huge bald butcher with a bloody face and cruel grin, 5) an old Indonesian farmer with a grey mustache and conical straw hat, stern. " + PORTRAIT,
    "ill_hall": ILLU + "Inside a vast dark industrial chicken factory hall: endless rows of tiny filthy wire cages stacked high, "
                "thousands of dim chicken silhouettes, a single tiny barred window at the top letting in one beam of cold sunlight with dust, oppressive, hellish.",
    "ill_pact": ILLU + "A tiny wet chick hatching from a cracked eggshell in a farmyard nest at sunrise, the very first golden sunbeam falling on it, "
                "behind it the huge looming shadow of a farmer holding a pocket watch, ominous yet tender.",
    "ill_cliff": ILLU + "The 'Cliff of the Hopeless' on a tropical island at night in a violent storm: a jagged dark sea cliff, huge waves smashing the rocks, "
                 "lightning, rain, a small lone white hen standing at the very edge with closed eyes and wind-blown feathers, a dead ragged chicken lying behind her.",
    "ill_void": ILLU + "An endless pure white empty void. In the center, tiny, a green grasshopper lying on its back being devoured by a line of black ants, "
                "singing with a blissful face, musical notes floating up; a white hen stands above it with a drop of red blood on the white floor. Minimalist, surreal.",
    "ill_revolution": ILLU + "A full moon night over a tropical island village with the power cut and all windows dark. Hundreds of chicken silhouettes with glowing red eyes "
                      "pour over the rooftops and through open windows, a big rooster and an old hen leading them, a white hen on a rooftop in front raising a cleaver. Ominous.",
    "ill_ending": ILLU + "A cheerful family birthday table in a small house: a cake with 7 candles, colorful balloons, and in the center a big plate of chicken wings with french fries. "
                  "Warm light, but in the window reflection a faint ghostly white hen is watching. Unsettling dark humor.",
    "ill_mirror": ILLU + "During a solar eclipse, inside an old witch's wooden house full of herbs and books, a frightened young woman with messy hair stares into a cracked mirror; "
                  "in the mirror her reflection is a white hen. Red eclipse light through the window, chaos and screaming crowds outside.",
    "sheet_story": "A wide landscape sprite sheet with exactly 6 separate sprites in one row, all facing RIGHT in three-quarter view: "
                   "1) BAUER MADE: an old stern Indonesian farmer with grey mustache, conical straw hat and a long rusty slaughter knife, "
                   "2) a friendly old Indonesian woman street-food seller with a headscarf and a ladle, "
                   "3) a sunburned drunk backpacker with dreadlocks holding a mushroom shake, "
                   "4) a dead ragged pale chicken lying on its side, eyes closed, "
                   "5) a small yellow chick with huge eyes, "
                   "6) a white hen sitting and sleeping peacefully with eyes closed. " + cs.STYLE,
}
cs.SHEETS.update(NEW)
if __name__ == "__main__":
    with cf.ThreadPoolExecutor(max_workers=10) as ex:
        for name, res in ex.map(cs.run, list(NEW)):
            print(name, res, flush=True)
