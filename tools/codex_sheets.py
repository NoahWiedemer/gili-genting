#!/usr/bin/env python3
"""Generate the (max 9) remaining Codex images as sprite sheets, in parallel.
Usage: python3 tools/codex_sheets.py [name ...]
"""
import subprocess, sys, os, concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_src", "raw")

STYLE = ("16-bit SNES-era pixel art RPG sprites in the style of Final Fantasy VI and Octopath Traveler, "
         "crisp hard square pixels, limited palette, bold dark outline, every sprite full body, "
         "all sprites the same pixel scale, each sprite clearly SEPARATED from the others by wide empty space "
         "(no overlapping, no touching), arranged in a neat grid, on a flat solid pure magenta (#FF00FF) background, "
         "no text, no labels, no shadows, no ground, no border. Slightly dark, gritty, black-humor tone.")

SHEETS = {
    "sheet_classes": "A wide landscape sprite sheet with exactly 6 separate hen chicken sprites in one row, all facing RIGHT in three-quarter view, same base white hen with red comb but each with a different RPG class look: "
        "1) WARRIOR hen with a red headband and a small rusty cleaver held under its wing, "
        "2) MAGE hen wearing a tall crooked purple wizard hat with yellow stars, "
        "3) HEALER hen with a white nurse cap with red cross and a tiny herb satchel, "
        "4) TANK hen that is huge and muscular, much bigger and bulkier than the others, wearing an iron cooking-pot as helmet, "
        "5) ASSASSIN hen with pitch-black feathers, a dark red scarf mask and glowing red eyes, "
        "6) a sick, ragged, pale, half-plucked wandering chicken with a tiny bindle stick. ",
    "sheet_companions": "A wide landscape sprite sheet with exactly 4 separate chicken sprites in one row, all facing RIGHT in three-quarter view: "
        "1) JIMMY, a giant, extremely muscular rooster with golden-brown plumage, a scar over one eye, gentle eyes, "
        "2) VIAN, a very old wise grey hen with one cloudy white blind eye, wrinkled, wearing a knitted shawl, leaning on a twig cane, "
        "3) NUGGET, a scruffy young speckled black-and-white hen with plucked bald patches and a battery-cage leg band, crazy wide eyes, "
        "4) MADAME PAPRIKA, a dramatic red-orange hen with a monocle and a tiny fez hat, theatrical pose. ",
    "sheet_humans": "A wide landscape sprite sheet with exactly 6 separate human enemy sprites in one row, all facing RIGHT in three-quarter view, caricatured and slightly grotesque: "
        "1) sunburned fat male tourist in a hawaiian shirt with a camera around neck and flip-flops, "
        "2) female influencer tourist with sunhat, sunglasses and a selfie stick, "
        "3) skinny local farmer with straw conical hat and a pitchfork, "
        "4) fisherman with a fishing net and a machete, "
        "5) beefy resort security guard with sunglasses and a baton, "
        "6) sleazy cockfight bookie with gold chains, a cigarette and a fistful of money. ",
    "sheet_bosses": "A wide landscape sprite sheet with exactly 6 separate sprites in one row, all facing RIGHT in three-quarter view: "
        "1) THE BUTCHER boss: a huge hulking butcher with a bloody white apron, rubber boots, a giant meat cleaver, menacing, twice as tall as the others, "
        "2) THE WOLF boss: a greedy real-estate investor in a white suit wearing a grey wolf fur pelt with the wolf head as a hood, grinning with sharp gritted teeth, holding blueprints, "
        "3) a sly red fox, "
        "4) a thieving grey macaque monkey holding a stolen banana, "
        "5) an angry red beach crab with raised claws, "
        "6) a mean scrawny guard dog with a spiked collar. ",
    "sheet_npcs": "A wide landscape sprite sheet with exactly 9 separate sprites arranged in a 3x3 grid, all facing RIGHT where applicable: "
        "1) a sad skinny brown-and-white cow, 2) a tiny cute calf, 3) a cute red-capped mushroom character with a face and little arms, "
        "4) a ladybug character standing upright with big eyes, 5) a small DEAD white shark floating belly-up with X eyes, "
        "6) a green grasshopper character, 7) a tokay gecko merchant with a tiny backpack of goods, "
        "8) an old wise sea turtle, 9) an old island witch woman with long white hair, flowers and a calm smile. ",
    "sheet_nature": "A wide landscape sprite sheet with exactly 8 separate environment prop sprites for a tropical island game, front view, arranged in a row/grid: "
        "1) a tall coconut palm tree with coconuts, 2) a dense tropical jungle tree, 3) a round green tropical bush, "
        "4) a frangipani bush with white-yellow flowers, 5) a grey mossy boulder, 6) a dead bare twisted tree for a dry steppe, "
        "7) a dry yellow shrub, 8) a clump of tall grass. ",
    "sheet_props": "A wide landscape sprite sheet with exactly 12 separate small prop sprites arranged in a 4x3 grid, front view: "
        "1) closed wooden treasure chest with brass, 2) the same chest opened and empty, 3) an ancient mossy round stone well with vines, "
        "4) a glowing cyan magic memory crystal growing from a small rock, 5) a creepy scarecrow, 6) a short wooden fence segment, "
        "7) a wooden barrel, 8) stacked wooden crates, 9) a stone lantern with a warm flame, 10) a beach umbrella with a deck chair, "
        "11) a grey electrical power box with a lightning warning sign and cables, 12) a bloody meat hook hanging from a chain. ",
    "sheet_items": "A square sprite sheet of exactly 20 separate RPG inventory item icons arranged in a 5x4 grid, each icon on its own, front view: "
        "row 1 weapons: rusty toothpick dagger, fish bone sword, corkscrew, broken machete, giant butcher cleaver; "
        "row 2 armor: coconut shell helmet, bottle-cap armor vest, plastic bag cape, sarong cloak, shark tooth necklace; "
        "row 3 food: mango, coconut drink with straw, plate of nasi goreng, handful of grains, wriggling worm; "
        "row 4 misc: chili sambal jar, magic mushroom shake glass, bintang-style beer bottle cap, glowing memory crystal shard, old leather spell book. ",
    "title_art": "A widescreen 16:9 pixel art title screen illustration (no magenta background for this one, fill the whole image) in 16-bit SNES / Octopath Traveler style: "
        "a tropical island at dusk with turquoise sea and palm silhouettes, a huge blood-red setting sun, and on a cliff in the foreground the silhouette of a small chicken "
        "holding a giant butcher cleaver, looking towards a farm with a glowing slaughterhouse in the distance. Dark humor, ominous yet beautiful, rich lighting, no text.",
}

def run(name):
    prompt = SHEETS[name]
    if name.startswith("sheet_") and STYLE not in prompt:
        prompt += STYLE
    out = os.path.join(RAW, name + ".png")
    if os.path.exists(out):
        return name, "exists"
    instr = (f"Use your image generation tool to create exactly ONE image with this description: {prompt}\n"
             f"Then copy the resulting image file to {out} . Do nothing else, generate only one image.")
    p = subprocess.run(["codex", "exec", "-m", "gpt-5.6-luna", "-c", "model_reasoning_effort=low",
                        "--skip-git-repo-check", "--sandbox", "workspace-write", "-C", RAW, instr],
                       capture_output=True, text=True, timeout=900)
    return name, "ok" if os.path.exists(out) else ("FAILED\n" + p.stdout[-800:] + p.stderr[-800:])

if __name__ == "__main__":
    names = sys.argv[1:] or list(SHEETS)
    with cf.ThreadPoolExecutor(max_workers=9) as ex:
        for name, res in ex.map(run, names):
            print(name, res, flush=True)
