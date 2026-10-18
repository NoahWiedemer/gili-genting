#!/usr/bin/env python3
"""Batch 4 (1 image): class portraits for the player hen."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import codex_sheets as cs
import codex_batch2 as b2
cs.SHEETS["portraits_cls"] = ("Exactly 5 portraits of the SAME white hen heroine (red comb, determined dark eyes) in different RPG class outfits: "
    "1) WARRIOR with a red headband and battle scars, 2) MAGE wearing a tall crooked purple wizard hat with yellow stars, "
    "3) HEALER with a white nurse cap with a red cross and a flower, 4) TANK: huge bulky hen wearing an iron cooking-pot helmet, "
    "5) ASSASSIN: pitch-black feathers, a dark red scarf mask over the beak and a hood, glowing red eyes. " + b2.PORTRAIT)
print(cs.run("portraits_cls"))
