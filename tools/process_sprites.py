#!/usr/bin/env python3
"""Cut the Codex sprite sheets into individual, real pixel-art sprites for Godot.
Removes background, splits by connected components, downsamples to a target pixel height,
quantizes the palette and writes PNGs into game/assets/sprites/.
"""
import os, numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "art_src", "raw")
OUT = os.path.join(ROOT, "game", "assets", "sprites")
os.makedirs(OUT, exist_ok=True)

# sheet -> (names in reading order, target heights, row count)
SHEETS = {
    "sheet_classes": (["cls_krieger", "cls_magier", "cls_heiler", "cls_tank", "cls_assassine", "wanderer"],
                      [38, 50, 40, 56, 37, 38]),
    "sheet_companions": (["jimmy", "vian", "nugget", "paprika"], [58, 40, 42, 46]),
    "sheet_humans": (["tourist_m", "tourist_f", "farmer", "fisher", "guard", "bookie"], [74, 76, 72, 72, 78, 74]),
    "sheet_bosses": (["butcher", "wolf", "fox", "macaque", "crab", "dog"], [118, 82, 40, 40, 28, 42]),
    "sheet_npcs": (["cow", "calf", "mushroom", "ladybug", "shark", "grasshopper", "gecko", "turtle", "witch"],
                   [60, 38, 34, 36, 26, 30, 46, 38, 74]),
    "sheet_nature": (["palm", "jungle_tree", "bush", "frangipani", "boulder", "dead_tree", "dry_shrub", "tall_grass"],
                     [176, 150, 44, 46, 40, 132, 32, 30]),
    "sheet_props": (["chest", "chest_open", "well", "crystal", "scarecrow", "fence", "barrel", "crates",
                     "lantern", "umbrella", "powerbox", "meathook"],
                    [26, 30, 52, 44, 70, 30, 34, 46, 48, 70, 54, 58]),
    "hen_base": (["cls_base"], [38]),
    "sheet_story": (["bauer", "warung_woman", "backpacker", "dead_chicken", "chick", "hen_sleep"], [76, 68, 76, 18, 22, 26]),
    "sheet_beach": (["jukung", "pier", "driftwood", "shells", "coconuts", "trash", "surfboard", "towel", "seaweed_rock", "tiki", "hammock", "sandcastle"],
                    [40, 40, 16, 14, 16, 16, 50, 20, 22, 56, 38, 22]),
    "sheet_village": (["stall", "laundry", "shrine", "cidomo", "coop", "banana_tree", "rice_sacks", "bicycle", "pots", "lantern_string", "canang", "bench"],
                      [70, 54, 62, 52, 42, 92, 28, 30, 26, 78, 12, 22]),
    "sheet_steppe": (["skull", "wheel", "plow", "rusty_barrel", "termite", "wall_piece", "stakes", "bones", "bucket", "signpost", "thorn_bush", "rock_pile"],
                     [16, 26, 26, 32, 40, 34, 34, 12, 18, 52, 30, 22]),
    "sheet_farm": (["haybale", "trough", "tractor", "cages", "milkcans", "wheelbarrow", "slaughter_table", "knife_rack", "red_lamp", "feed_sacks", "farm_sign", "chopping_block"],
                   [34, 22, 62, 56, 26, 26, 34, 40, 70, 26, 50, 28]),
    "sheet_flora": (["hibiscus", "bougainvillea", "fern", "bamboo", "banana_small", "bird_paradise", "monstera", "reeds", "yellow_shrub", "orchids", "mushrooms_small", "sapling"],
                    [44, 50, 30, 110, 58, 40, 40, 44, 34, 28, 14, 50]),
    "portraits_a": (["p_ania", "p_jimmy", "p_vian", "p_nugget", "p_paprika"], [64, 64, 64, 64, 64]),
    "sheet_interior": (["bed", "table_rice", "shelf", "bar_counter", "oil_lamp", "rug", "stove", "blender", "net_rack", "wardrobe", "altar", "mirror_stand"],
                       [40, 28, 64, 42, 30, 18, 40, 30, 56, 64, 46, 60]),
    "sheet_misc": (["campfire", "notice_board", "firewood", "water_jar", "bird_cage", "coconut_barrow", "suitcase", "scooter", "trash_bags", "dead_fish", "dock_post", "weathervane"],
                   [30, 44, 22, 26, 40, 26, 24, 34, 28, 12, 30, 60]),
    "portraits_cls": (["p_cls_krieger", "p_cls_magier", "p_cls_heiler", "p_cls_tank", "p_cls_assassine"], [64, 64, 64, 64, 64]),
    "portraits_b": (["p_shark", "p_grasshopper", "p_witch", "p_butcher", "p_bauer"], [64, 64, 64, 64, 64]),
}
ITEMS = ["w_zahnstocher", "w_fischgraete", "w_korkenzieher", "w_machete", "w_hackbeil",
         "a_kokoshelm", "a_kronkorken", "a_plastiktuete", "a_sarong", "c_haizahn",
         "f_mango", "f_kokos", "f_nasigoreng", "f_koerner", "f_wurm",
         "f_sambal", "f_shake", "c_kronkorken", "k_kristall", "k_buch"]


def load_rgba(name):
    im = Image.open(os.path.join(RAW, name + ".png")).convert("RGBA")
    a = np.array(im).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # magenta key (for RGB sheets) -> transparent
    mag = (r > 170) & (b > 170) & (g < 110)
    a[..., 3][mag] = 0
    # de-fringe: pinkish semi-magenta edge pixels
    fringe = (r > 150) & (b > 120) & (g < r * 0.6) & (b > g * 1.5)
    a[..., 3][fringe] = 0
    return a


def components(alpha, thresh, dilate, min_area):
    mask = alpha > thresh
    big = ndimage.binary_dilation(mask, iterations=dilate)
    lab, n = ndimage.label(big)
    objs = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        sub = (lab[sl] == i + 1) & mask[sl]
        if sub.sum() < min_area:
            continue
        objs.append((sl, i + 1))
    return lab, mask, objs


def order(objs, rows_tol):
    cents = [((sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2, sl, lid) for sl, lid in objs]
    cents.sort(key=lambda c: c[0])
    rows, cur = [], []
    for c in cents:
        if cur and c[0] - cur[-1][0] > rows_tol:
            rows.append(cur); cur = []
        cur.append(c)
    if cur:
        rows.append(cur)
    out = []
    for r in rows:
        out += sorted(r, key=lambda c: c[1])
    return out


def pixelize(rgba, target_h, colors=40, max_w=None):
    h, w = rgba.shape[:2]
    s = target_h / h
    if max_w and w * s > max_w:
        s = max_w / w
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    # premultiplied box downsample
    pm = rgba.copy()
    pm[..., :3] *= pm[..., 3:4] / 255.0
    im = Image.fromarray(np.clip(pm, 0, 255).astype(np.uint8), "RGBA").resize((nw, nh), Image.BOX)
    d = np.array(im).astype(np.float32)
    al = d[..., 3]
    keep = al > 110
    rgb = np.zeros_like(d[..., :3])
    rgb[keep] = d[..., :3][keep] / (al[keep, None] / 255.0)
    rgb = np.clip(rgb, 0, 255)
    # quantize visible colors
    img = Image.fromarray(rgb.astype(np.uint8), "RGB")
    q = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.zeros((nh, nw, 4), np.uint8)
    out[..., :3] = np.array(q)
    out[..., 3] = np.where(keep, 255, 0)
    # remove isolated single pixels
    m = out[..., 3] > 0
    nb = ndimage.convolve(m.astype(int), np.ones((3, 3), int), mode="constant") - m
    out[..., 3][(m) & (nb == 0)] = 0
    return out


def save(arr, name):
    # pad: 1px transparent border so outlines never clip
    a = np.pad(arr, ((1, 1), (1, 1), (0, 0)))
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, name + ".png"))


def process_columns(sheet, names, heights):
    a = load_rgba(sheet)
    n = len(names)
    W = a.shape[1]
    for i, (name, th) in enumerate(zip(names, heights)):
        x0, x1 = int(W * i / n), int(W * (i + 1) / n)
        crop = a[:, x0:x1].copy()
        crop[..., 3] = np.where(crop[..., 3] > 128, 255, 0)
        ys, xs = np.nonzero(crop[..., 3])
        crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        save(pixelize(crop, th, colors=48), name)
        print(f"{sheet}: {name} (columns)")


def process_sheet(sheet, names, heights):
    if sheet.startswith("portraits"):
        return process_columns(sheet, names, heights)
    a = load_rgba(sheet)
    thresh = 200 if sheet in ("sheet_npcs", "sheet_props") else 128
    lab, mask, objs = components(a[..., 3], thresh, dilate=2 if sheet == "sheet_nature" else 10, min_area=1500)
    objs = order(objs, rows_tol=a.shape[0] * 0.18)
    if len(objs) != len(names):
        print(f"!! {sheet}: found {len(objs)} components, expected {len(names)}")
    for (cy, cx, sl, lid), name, th in zip(objs, names, heights):
        crop = a[sl].copy()
        sub = (lab[sl] == lid) & mask[sl]
        crop[..., 3] = np.where(sub, np.where(crop[..., 3] > thresh, 255, 0), 0)
        ys, xs = np.nonzero(crop[..., 3])
        crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        save(pixelize(crop, th, colors=48 if name.startswith('p_') else 40), name)
        print(f"{sheet}: {name} -> {th}px")


def process_items():
    a = load_rgba("sheet_items")
    lab, mask, objs = components(a[..., 3], 128, dilate=14, min_area=800)
    objs = order(objs, rows_tol=a.shape[0] * 0.12)
    print("items found", len(objs))
    os.makedirs(os.path.join(OUT, "items"), exist_ok=True)
    for (cy, cx, sl, lid), name in zip(objs, ITEMS):
        crop = a[sl].copy()
        sub = (lab[sl] == lid) & mask[sl]
        crop[..., 3] = np.where(sub, crop[..., 3], 0)
        ys, xs = np.nonzero(crop[..., 3] > 128)
        crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        px = pixelize(crop, 22, colors=24, max_w=22)
        canvas = np.zeros((24, 24, 4), np.uint8)
        h, w = px.shape[:2]
        oy, ox = (24 - h) // 2, (24 - w) // 2
        canvas[oy:oy + h, ox:ox + w] = px
        Image.fromarray(canvas, "RGBA").save(os.path.join(OUT, "items", name + ".png"))


def process_title():
    os.makedirs(os.path.join(ROOT, "game", "assets", "ui"), exist_ok=True)
    for src, dst in [("title_art", "title_bg"), ("ill_hall", "ill_hall"), ("ill_pact", "ill_pact"), ("ill_cliff", "ill_cliff"),
                     ("ill_void", "ill_void"), ("ill_revolution", "ill_revolution"), ("ill_ending", "ill_ending"), ("ill_mirror", "ill_mirror")]:
        fp = os.path.join(RAW, src + ".png")
        if not os.path.exists(fp):
            continue
        im = Image.open(fp).convert("RGB")
        # crop to 16:9 then reduce to true 640x360 pixel art
        w, h = im.size
        th = int(w * 9 / 16)
        if th <= h:
            im = im.crop((0, (h - th) // 2, w, (h - th) // 2 + th))
        im = im.resize((640, 360), Image.LANCZOS)
        im = im.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        im.save(os.path.join(ROOT, "game", "assets", "ui", dst + ".png"))


GROUND = ["g_flowers_w", "g_flowers_r", "g_pebbles", "g_leaves", "g_puddle", "g_cracks", "g_clover", "g_shells",
          "g_footprints", "g_stones", "g_moss", "g_straw", "g_frangi", "g_twigs", "g_stain", "g_mush"]


def process_ground():
    if not os.path.exists(os.path.join(RAW, "sheet_ground.png")):
        return
    a = load_rgba("sheet_ground")
    lab, mask, objs = components(a[..., 3], 128, dilate=12, min_area=600)
    objs = order(objs, rows_tol=a.shape[0] * 0.12)
    print("ground found", len(objs))
    for (cy, cx, sl, lid), name in zip(objs, GROUND):
        crop = a[sl].copy()
        sub = (lab[sl] == lid) & mask[sl]
        crop[..., 3] = np.where(sub, crop[..., 3], 0)
        ys, xs = np.nonzero(crop[..., 3] > 128)
        crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        save(pixelize(crop, 26, colors=20, max_w=30), name)


def process_backdrops():
    os.makedirs(os.path.join(ROOT, "game", "assets", "backdrops"), exist_ok=True)
    for n in ["bd_beach", "bd_village", "bd_steppe", "bd_cliff", "bd_farm", "bd_slaughter"]:
        fp = os.path.join(RAW, n + ".png")
        if not os.path.exists(fp):
            continue
        im = Image.open(fp).convert("RGB")
        w, h = im.size
        nw = 960
        im = im.resize((nw, int(h * nw / w)), Image.LANCZOS)
        im = im.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        im.save(os.path.join(ROOT, "game", "assets", "backdrops", n + ".png"))
        print("backdrop", n, im.size)


def contact_sheet():
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".png"))
    ims = [Image.open(os.path.join(OUT, f)) for f in files]
    W = 1400
    x = y = rowh = 0
    pos = []
    for im in ims:
        w, h = im.size[0] * 3, im.size[1] * 3
        if x + w > W:
            x = 0; y += rowh + 6; rowh = 0
        pos.append((x, y)); x += w + 6; rowh = max(rowh, h)
    sheet = Image.new("RGBA", (W, y + rowh + 6), (40, 70, 80, 255))
    for im, (px, py) in zip(ims, pos):
        big = im.resize((im.size[0] * 3, im.size[1] * 3), Image.NEAREST)
        sheet.alpha_composite(big, (px, py))
    sheet.save(os.path.join(ROOT, "art_src", "sprites_contact.png"))


if __name__ == "__main__":
    for sheet, (names, heights) in SHEETS.items():
        if os.path.exists(os.path.join(RAW, sheet + ".png")):
            process_sheet(sheet, names, heights)
    process_ground()
    process_backdrops()
    process_items()
    process_title()
    contact_sheet()
