extends Node
## Static game data: classes, skill trees, skills, items, enemies, companions.

const PPU := 40.0 # sprite pixels per world unit

# ------------------------------------------------------------------ CLASSES
const CLASSES := {
	"krieger": {
		"name": "Krieger", "sprite": "cls_krieger", "color": Color(0.85, 0.25, 0.2),
		"desc": "Hackt zuerst, gackert später. Hohe Angriffskraft, solide Verteidigung.",
		"base": {"hp": 64, "mp": 14, "atk": 13, "def": 9, "mag": 5, "res": 6, "spd": 9},
		"grow": {"hp": 10.0, "mp": 2.0, "atk": 2.4, "def": 1.5, "mag": 0.6, "res": 1.0, "spd": 0.9},
		"start": "schnabelhieb",
		"branches": [
			{"name": "Klinge", "skills": ["hackbeil_wirbel", "augenpicker", "schlachtfest"]},
			{"name": "Wut", "skills": ["huehnerwut", "kampfschrei", "blutrausch"]},
			{"name": "Zähigkeit", "skills": ["dicke_federn", "konter_haltung", "letztes_gegacker"]},
		],
	},
	"magier": {
		"name": "Magier", "sprite": "cls_magier", "color": Color(0.55, 0.35, 0.9),
		"desc": "Trägt einen Hut, der mehr weiß als er. Starke Zauber, wenig Federn.",
		"base": {"hp": 48, "mp": 28, "atk": 6, "def": 5, "mag": 14, "res": 10, "spd": 8},
		"grow": {"hp": 7.0, "mp": 4.0, "atk": 0.8, "def": 0.9, "mag": 2.6, "res": 1.6, "spd": 0.8},
		"start": "funkenflug",
		"branches": [
			{"name": "Feuer", "skills": ["grillfeuer", "brathaehnchen_rache", "inferno"]},
			{"name": "Wetter", "skills": ["hagelkorn", "monsunregen", "gewitterhahn"]},
			{"name": "Geist", "skills": ["drittes_auge", "mana_ei", "zauberbrut"]},
		],
	},
	"heiler": {
		"name": "Heiler", "sprite": "cls_heiler", "color": Color(0.35, 0.85, 0.45),
		"desc": "Flickt Federn und Seelen. Kennt auch die andere Seite der Kräuter.",
		"base": {"hp": 54, "mp": 26, "atk": 7, "def": 7, "mag": 12, "res": 11, "spd": 8},
		"grow": {"hp": 8.0, "mp": 3.6, "atk": 0.9, "def": 1.1, "mag": 2.2, "res": 1.8, "spd": 0.8},
		"start": "kraeuterpicken",
		"branches": [
			{"name": "Heilung", "skills": ["wurmsuppe", "auferstehung", "glucken_segen"]},
			{"name": "Schutz", "skills": ["federkleid", "laeuterung", "nestbau"]},
			{"name": "Gift", "skills": ["fingerhut", "menge_gift", "giftmischerin"]},
		],
	},
	"tank": {
		"name": "Tank", "sprite": "cls_tank", "color": Color(0.75, 0.7, 0.55),
		"desc": "Mehr Huhn als Huhn. Zieht Schläge an wie ein Grill die Touristen.",
		"base": {"hp": 82, "mp": 12, "atk": 10, "def": 13, "mag": 4, "res": 8, "spd": 6},
		"grow": {"hp": 14.0, "mp": 1.6, "atk": 1.7, "def": 2.3, "mag": 0.4, "res": 1.3, "spd": 0.6},
		"start": "spott_gackern",
		"branches": [
			{"name": "Bollwerk", "skills": ["bollwerk", "schutzfluegel", "unverwuestlich"]},
			{"name": "Wucht", "skills": ["bauchklatscher", "erdbeben", "hahnenkampf"]},
			{"name": "Großes Herz", "skills": ["grosses_herz", "sanfter_riese", "dornenfedern"]},
		],
	},
	"assassine": {
		"name": "Assassine", "sprite": "cls_assassine", "color": Color(0.3, 0.3, 0.35),
		"desc": "Schwarzes Gefieder, schwärzere Absichten. Schnell, kritisch, giftig.",
		"base": {"hp": 50, "mp": 16, "atk": 12, "def": 6, "mag": 6, "res": 6, "spd": 14},
		"grow": {"hp": 8.0, "mp": 2.2, "atk": 2.2, "def": 0.9, "mag": 0.7, "res": 0.9, "spd": 1.5},
		"start": "schattenstich",
		"branches": [
			{"name": "Klinge", "skills": ["kehlenschnitt", "doppelstich", "exekution"]},
			{"name": "Schatten", "skills": ["rauchbombe", "schattenschritt", "im_schatten"]},
			{"name": "Gift", "skills": ["giftfeder", "nervengift", "flinke_krallen"]},
		],
	},
}

# ------------------------------------------------------------------ SKILLS
# kind: phys | mag | heal | revive | buff | debuff | status | passive | special
# target: enemy | enemies | ally | allies | self | ko_ally | random_enemies
const SKILLS := {
	# --- Krieger
	"schnabelhieb": {"name": "Schnabelhieb", "mp": 2, "kind": "phys", "target": "enemy", "power": 1.5, "fx": "fx_peck", "sfx": "peck",
		"desc": "Ein kräftiger Hieb mit dem Schnabel."},
	"hackbeil_wirbel": {"name": "Hackbeil-Wirbel", "mp": 6, "kind": "phys", "target": "enemies", "power": 0.95, "fx": "fx_slash", "sfx": "slash",
		"desc": "Dreht sich mit Klinge im Kreis. Trifft alle Gegner."},
	"augenpicker": {"name": "Augenpicker", "mp": 8, "kind": "phys", "target": "enemy", "power": 2.0, "fx": "fx_blood", "sfx": "peck",
		"status": {"id": "blind", "turns": 3, "chance": 0.8}, "desc": "Zielt auf die Augen. Wie im Buch. Blendet."},
	"schlachtfest": {"name": "Schlachtfest", "mp": 16, "kind": "phys", "target": "enemy", "power": 3.6, "crit_bonus": 0.25, "fx": "fx_slash", "sfx": "hit_crit",
		"desc": "Heute wird zurückgeschlachtet. Gewaltiger Einzelschaden."},
	"huehnerwut": {"name": "Hühnerwut", "kind": "passive", "passive": {"atk": 0.15}, "desc": "Passiv: +15% Angriff."},
	"kampfschrei": {"name": "Kampfschrei", "mp": 8, "kind": "buff", "target": "allies", "buff": {"id": "atk_up", "turns": 3}, "fx": "fx_buff", "sfx": "cluck_angry",
		"desc": "Ein Gackern, das Knochen erzittern lässt. Team-Angriff hoch."},
	"blutrausch": {"name": "Blutrausch", "kind": "passive", "passive": {"lifesteal": 0.12}, "desc": "Passiv: heilt 12% des verursachten Schadens."},
	"dicke_federn": {"name": "Dicke Federn", "kind": "passive", "passive": {"hp": 0.12}, "desc": "Passiv: +12% max. HP."},
	"konter_haltung": {"name": "Konter-Haltung", "mp": 6, "kind": "buff", "target": "self", "buff": {"id": "konter", "turns": 3}, "fx": "fx_shield", "sfx": "shield",
		"desc": "Schlägt bei jedem Treffer zurück. 3 Runden."},
	"letztes_gegacker": {"name": "Letztes Gegacker", "kind": "passive", "passive": {"endure": 1.0}, "desc": "Passiv: überlebt einmal pro Kampf einen tödlichen Treffer mit 1 HP."},
	# --- Magier
	"funkenflug": {"name": "Funkenflug", "mp": 4, "kind": "mag", "target": "enemy", "power": 1.45, "elem": "feuer", "fx": "fx_fire", "sfx": "magic_fire",
		"desc": "Ein kleiner Feuerball. Riecht nach Grillabend."},
	"grillfeuer": {"name": "Grillfeuer", "mp": 9, "kind": "mag", "target": "enemies", "power": 1.05, "elem": "feuer", "fx": "fx_fire", "sfx": "magic_fire",
		"desc": "Jetzt wird zurückgegrillt. Feuer auf alle Gegner."},
	"brathaehnchen_rache": {"name": "Brathähnchen-Rache", "mp": 14, "kind": "mag", "target": "enemy", "power": 3.0, "elem": "feuer", "fx": "fx_fire", "sfx": "magic_fire",
		"status": {"id": "blutung", "turns": 3, "chance": 0.7}, "desc": "Für jeden Broiler dieser Welt. Riesiger Feuerschaden + Brand."},
	"inferno": {"name": "Inferno", "mp": 22, "kind": "mag", "target": "enemies", "power": 2.2, "elem": "feuer", "fx": "fx_fire", "sfx": "thunder",
		"desc": "Ein Scheiterhaufen für alle."},
	"hagelkorn": {"name": "Hagelkorn", "mp": 6, "kind": "mag", "target": "enemy", "power": 1.6, "elem": "eis", "fx": "fx_ice", "sfx": "magic_ice",
		"status": {"id": "langsam", "turns": 2, "chance": 0.6}, "desc": "Ein Korn, aber aus Eis. Verlangsamt."},
	"monsunregen": {"name": "Monsunregen", "mp": 12, "kind": "mag", "target": "enemies", "power": 1.35, "elem": "eis", "fx": "fx_ice", "sfx": "magic_ice",
		"desc": "Vian sagt, sie hätte es geschmeckt. Eis auf alle."},
	"gewitterhahn": {"name": "Gewitterhahn", "mp": 20, "kind": "mag", "target": "enemies", "power": 2.4, "elem": "blitz", "fx": "fx_lightning", "sfx": "thunder",
		"status": {"id": "betaeubt", "turns": 1, "chance": 0.3}, "desc": "Blitze aus dem Kamm. Kann betäuben."},
	"drittes_auge": {"name": "Drittes Auge", "kind": "passive", "passive": {"mag": 0.2}, "desc": "Passiv: +20% Magie."},
	"mana_ei": {"name": "Mana-Ei", "mp": 0, "kind": "special", "target": "ally", "effect": "mana_ei", "fx": "fx_egg", "sfx": "magic_heal",
		"desc": "Legt ein Ei voller Mana. Ein Verbündeter erhält 35% MP. Kostet 10% eigene HP."},
	"zauberbrut": {"name": "Zauberbrut", "kind": "passive", "passive": {"mp": 0.25, "mp_cost": -0.2}, "desc": "Passiv: +25% max. MP, Zauber kosten 20% weniger."},
	# --- Heiler
	"kraeuterpicken": {"name": "Kräuterpicken", "mp": 4, "kind": "heal", "target": "ally", "power": 1.3, "fx": "fx_heal", "sfx": "magic_heal",
		"desc": "Heilt einen Verbündeten mit gepickten Kräutern."},
	"wurmsuppe": {"name": "Wurmsuppe", "mp": 9, "kind": "heal", "target": "allies", "power": 0.95, "fx": "fx_heal", "sfx": "magic_heal",
		"desc": "Heilt das ganze Team. Schmeckt wie es klingt."},
	"auferstehung": {"name": "Aus dem Ei", "mp": 14, "kind": "revive", "target": "ko_ally", "power": 0.5, "fx": "fx_egg", "sfx": "level_up",
		"desc": "Belebt ein K.O.-Huhn mit 50% HP wieder. Das Ei war zuerst da."},
	"glucken_segen": {"name": "Glucken-Segen", "mp": 24, "kind": "heal", "target": "allies", "power": 2.6, "fx": "fx_heal", "sfx": "level_up",
		"buff": {"id": "regen", "turns": 3}, "desc": "Volle Heilung für alle + Regeneration."},
	"federkleid": {"name": "Federkleid", "mp": 5, "kind": "buff", "target": "ally", "buff": {"id": "def_up", "turns": 3}, "fx": "fx_shield", "sfx": "shield",
		"desc": "Verdoppelt das Gefieder eines Verbündeten. Verteidigung hoch."},
	"laeuterung": {"name": "Läuterung", "mp": 6, "kind": "special", "target": "allies", "effect": "cleanse", "fx": "fx_heal", "sfx": "magic_heal",
		"desc": "Entfernt alle negativen Zustände vom Team."},
	"nestbau": {"name": "Heiliger Nestbau", "mp": 12, "kind": "buff", "target": "allies", "buff": {"id": "regen", "turns": 4}, "fx": "fx_heal", "sfx": "buff",
		"desc": "Baut ein Nest der Geborgenheit. Team regeneriert 4 Runden."},
	"fingerhut": {"name": "Fingerhut", "mp": 5, "kind": "status", "target": "enemy", "status": {"id": "gift", "turns": 4, "chance": 0.95}, "fx": "fx_poison", "sfx": "poison",
		"desc": "Ein Kräutlein, falsch dosiert. Vergiftet."},
	"menge_gift": {"name": "Die Menge macht das Gift", "mp": 12, "kind": "mag", "target": "enemies", "power": 0.8, "fx": "fx_poison", "sfx": "poison",
		"status": {"id": "gift", "turns": 4, "chance": 0.85}, "desc": "Die Heuschrecke hatte recht. Vergiftet alle Gegner."},
	"giftmischerin": {"name": "Giftmischerin", "kind": "passive", "passive": {"poison_mult": 1.0}, "desc": "Passiv: Gift verursacht doppelten Schaden."},
	# --- Tank
	"spott_gackern": {"name": "Spott-Gackern", "mp": 3, "kind": "buff", "target": "self", "buff": {"id": "spott", "turns": 3}, "fx": "fx_buff", "sfx": "cluck_angry",
		"desc": "Beleidigt die Mutter jedes Gegners. Alle greifen dich an."},
	"bollwerk": {"name": "Bollwerk", "kind": "passive", "passive": {"def": 0.2}, "desc": "Passiv: +20% Verteidigung."},
	"schutzfluegel": {"name": "Schutzflügel", "mp": 5, "kind": "buff", "target": "ally", "buff": {"id": "beschuetzt", "turns": 3}, "fx": "fx_shield", "sfx": "shield",
		"desc": "Nimmt die Treffer eines Verbündeten auf sich."},
	"unverwuestlich": {"name": "Unverwüstlich", "mp": 12, "kind": "buff", "target": "self", "buff": {"id": "unverwuestlich", "turns": 3}, "fx": "fx_shield", "sfx": "shield",
		"desc": "Verteidigung massiv hoch und Regeneration."},
	"bauchklatscher": {"name": "Bauchklatscher", "mp": 6, "kind": "phys", "target": "enemy", "power": 1.4, "use_def": true, "fx": "fx_hit", "sfx": "hit_crit",
		"status": {"id": "betaeubt", "turns": 1, "chance": 0.35}, "desc": "Schaden basiert auf Verteidigung. Kann betäuben."},
	"erdbeben": {"name": "Erdbeben-Stampfer", "mp": 12, "kind": "phys", "target": "enemies", "power": 1.25, "use_def": true, "fx": "fx_hit", "sfx": "thunder",
		"status": {"id": "betaeubt", "turns": 1, "chance": 0.2}, "desc": "Stampft so fest, dass die Insel wackelt."},
	"hahnenkampf": {"name": "Hahnenkampf", "mp": 18, "kind": "phys", "target": "random_enemies", "hits": 5, "power": 0.85, "fx": "fx_claw", "sfx": "slash",
		"desc": "5 wilde Treffer auf zufällige Gegner. Die Arena war gestern."},
	"grosses_herz": {"name": "Großes Herz", "kind": "passive", "passive": {"hp": 0.2}, "desc": "Passiv: +20% max. HP."},
	"sanfter_riese": {"name": "Sanfter Riese", "mp": 6, "kind": "heal", "target": "self", "power": 0.0, "pct": 0.35, "fx": "fx_heal", "sfx": "magic_heal",
		"desc": "Heilt sich selbst um 35% der max. HP."},
	"dornenfedern": {"name": "Dornenfedern", "kind": "passive", "passive": {"thorns": 0.3}, "desc": "Passiv: wirft 30% des Nahkampfschadens zurück."},
	# --- Assassine
	"schattenstich": {"name": "Schattenstich", "mp": 3, "kind": "phys", "target": "enemy", "power": 1.35, "crit_bonus": 0.25, "fx": "fx_dark", "sfx": "slash",
		"desc": "Ein Stich aus dem Nichts. Hohe Krit-Chance."},
	"kehlenschnitt": {"name": "Kehlenschnitt", "mp": 6, "kind": "phys", "target": "enemy", "power": 1.8, "fx": "fx_blood", "sfx": "slash",
		"status": {"id": "blutung", "turns": 3, "chance": 0.9}, "desc": "Lässt bluten. Schwarzer Humor, roter Boden."},
	"doppelstich": {"name": "Doppelstich", "mp": 8, "kind": "phys", "target": "enemy", "hits": 2, "power": 1.15, "fx": "fx_slash", "sfx": "slash",
		"desc": "Zweimal. Sicher ist sicher."},
	"exekution": {"name": "Exekution", "mp": 15, "kind": "phys", "target": "enemy", "power": 1.6, "execute": 0.35, "fx": "fx_blood", "sfx": "hit_crit",
		"desc": "Unter 35% HP: vierfacher Schaden. Schlachtzeit für Menschen."},
	"rauchbombe": {"name": "Rauchbombe", "mp": 6, "kind": "status", "target": "enemies", "status": {"id": "blind", "turns": 2, "chance": 0.75}, "fx": "fx_dark", "sfx": "whoosh",
		"desc": "Blendet alle Gegner."},
	"schattenschritt": {"name": "Schattenschritt", "mp": 4, "kind": "buff", "target": "self", "buff": {"id": "sicherer_krit", "turns": 2}, "fx": "fx_dark", "sfx": "buff",
		"desc": "Der nächste Angriff ist garantiert kritisch."},
	"im_schatten": {"name": "Im Schatten", "kind": "passive", "passive": {"crit": 0.15}, "desc": "Passiv: +15% Krit-Chance."},
	"giftfeder": {"name": "Giftfeder", "mp": 5, "kind": "phys", "target": "enemy", "power": 1.0, "fx": "fx_poison", "sfx": "poison",
		"status": {"id": "gift", "turns": 4, "chance": 0.9}, "desc": "Eine Feder, in Gift getränkt."},
	"nervengift": {"name": "Nervengift", "mp": 9, "kind": "phys", "target": "enemy", "power": 1.0, "fx": "fx_poison", "sfx": "poison",
		"status": {"id": "betaeubt", "turns": 1, "chance": 0.75}, "desc": "Lähmt den Gegner eine Runde."},
	"flinke_krallen": {"name": "Flinke Krallen", "kind": "passive", "passive": {"spd": 0.2}, "desc": "Passiv: +20% Tempo."},
	# --- Ultimate after the epiphany
	"revolution": {"name": "Der Zeiger schlägt", "mp": 0, "kind": "phys", "target": "enemies", "power": 2.8, "fx": "fx_blood", "sfx": "thunder", "once": true,
		"desc": "Einmal pro Kampf. Die Revolution beginnt jetzt."},

	# --- Enemy skills
	"e_zwick": {"name": "Zwicken", "kind": "phys", "target": "enemy", "power": 1.1, "fx": "fx_claw", "sfx": "peck"},
	"e_rempler": {"name": "Bierbauch-Rempler", "kind": "phys", "target": "enemy", "power": 1.3, "fx": "fx_hit", "sfx": "hit"},
	"e_sonnencreme": {"name": "Sonnencreme-Spritzer", "kind": "status", "target": "enemy", "status": {"id": "blind", "turns": 2, "chance": 0.7}, "fx": "fx_poison", "sfx": "poison"},
	"e_selfie": {"name": "Selfie-Blitz", "kind": "mag", "target": "enemies", "power": 0.6, "fx": "fx_lightning", "sfx": "magic_ice",
		"status": {"id": "blind", "turns": 1, "chance": 0.35}},
	"e_story": {"name": "Story posten", "kind": "buff", "target": "allies", "buff": {"id": "atk_up", "turns": 2}, "fx": "fx_buff", "sfx": "buff"},
	"e_klauen": {"name": "Klauen", "kind": "special", "target": "enemy", "effect": "steal", "power": 0.7, "fx": "fx_claw", "sfx": "coin"},
	"e_banane": {"name": "Bananenwurf", "kind": "phys", "target": "enemy", "power": 1.2, "fx": "fx_hit", "sfx": "hit"},
	"e_schlagstock": {"name": "Schlagstock", "kind": "phys", "target": "enemy", "power": 1.35, "fx": "fx_hit", "sfx": "hit_crit",
		"status": {"id": "betaeubt", "turns": 1, "chance": 0.25}},
	"e_mistgabel": {"name": "Mistgabel-Stich", "kind": "phys", "target": "enemy", "power": 1.35, "fx": "fx_claw", "sfx": "slash",
		"status": {"id": "blutung", "turns": 3, "chance": 0.4}},
	"e_netz": {"name": "Netzwurf", "kind": "status", "target": "enemy", "status": {"id": "betaeubt", "turns": 1, "chance": 0.6}, "fx": "fx_shield", "sfx": "whoosh"},
	"e_machete": {"name": "Machetenhieb", "kind": "phys", "target": "enemy", "power": 1.5, "fx": "fx_slash", "sfx": "slash"},
	"e_biss": {"name": "Biss", "kind": "phys", "target": "enemy", "power": 1.25, "fx": "fx_blood", "sfx": "hit",
		"status": {"id": "blutung", "turns": 3, "chance": 0.45}},
	"e_bellen": {"name": "Bellen", "kind": "debuff", "target": "enemies", "buff": {"id": "def_down", "turns": 3}, "fx": "fx_debuff", "sfx": "debuff"},
	"e_wettschein": {"name": "Wettschein", "kind": "debuff", "target": "enemy", "buff": {"id": "atk_down", "turns": 3}, "fx": "fx_debuff", "sfx": "debuff"},
	"e_bestechung": {"name": "Bestechung", "kind": "special", "target": "enemy", "effect": "steal", "power": 1.0, "fx": "fx_claw", "sfx": "coin"},
	"e_goldkette": {"name": "Goldketten-Peitsche", "kind": "phys", "target": "enemies", "power": 0.95, "fx": "fx_slash", "sfx": "slash"},
	"e_knirschen": {"name": "Zähneknirschen", "kind": "debuff", "target": "enemies", "buff": {"id": "atk_down", "turns": 3}, "fx": "fx_dark", "sfx": "debuff"},
	"e_abriss": {"name": "Abrissbirne", "kind": "phys", "target": "enemies", "power": 1.2, "fx": "fx_hit", "sfx": "thunder"},
	"e_wolfsbiss": {"name": "Wolfsbiss", "kind": "phys", "target": "enemy", "power": 1.7, "fx": "fx_blood", "sfx": "hit_crit",
		"status": {"id": "blutung", "turns": 3, "chance": 0.6}},
	"e_bauantrag": {"name": "Bauantrag", "kind": "special", "target": "self", "effect": "summon", "summon": "guard", "fx": "fx_buff", "sfx": "buff"},
	"e_haken": {"name": "Fleischerhaken", "kind": "phys", "target": "enemy", "power": 1.6, "fx": "fx_blood", "sfx": "slash",
		"status": {"id": "blutung", "turns": 3, "chance": 0.8}},
	"e_hackbeil": {"name": "Hackbeil-Schwung", "kind": "phys", "target": "enemies", "power": 1.15, "fx": "fx_slash", "sfx": "slash"},
	"e_rupfen": {"name": "Rupfen", "kind": "debuff", "target": "enemy", "buff": {"id": "def_down", "turns": 3}, "fx": "fx_claw", "sfx": "debuff"},
	"e_schlachtzeit_laden": {"name": "Wetzt das Beil ...", "kind": "special", "target": "self", "effect": "charge", "fx": "fx_buff", "sfx": "buff"},
	"e_schlachtzeit": {"name": "SCHLACHTZEIT", "kind": "phys", "target": "enemies", "power": 2.4, "fx": "fx_blood", "sfx": "thunder"},
	"e_sicheln": {"name": "Sichel-Schwung", "kind": "phys", "target": "enemies", "power": 1.0, "fx": "fx_slash", "sfx": "slash"},
	"e_hilfe": {"name": "Ruft den Schlachter", "kind": "buff", "target": "allies", "buff": {"id": "atk_up", "turns": 3}, "fx": "fx_buff", "sfx": "cluck_angry"},
}

# ------------------------------------------------------------------ STATUS
const STATUS := {
	"gift": {"name": "Gift", "icon": "☠", "color": Color(0.7, 0.3, 0.9), "bad": true},
	"blutung": {"name": "Blutung", "icon": "♥", "color": Color(0.9, 0.15, 0.15), "bad": true},
	"betaeubt": {"name": "Betäubt", "icon": "★", "color": Color(1, 0.9, 0.3), "bad": true},
	"blind": {"name": "Blind", "icon": "◆", "color": Color(0.5, 0.5, 0.55), "bad": true},
	"langsam": {"name": "Langsam", "icon": "▼", "color": Color(0.4, 0.7, 1), "bad": true},
	"atk_down": {"name": "Angr. ▼", "icon": "▼", "color": Color(0.5, 0.6, 1), "bad": true},
	"def_down": {"name": "Vert. ▼", "icon": "▼", "color": Color(0.5, 0.6, 1), "bad": true},
	"atk_up": {"name": "Angr. ▲", "icon": "▲", "color": Color(1, 0.55, 0.2), "bad": false},
	"def_up": {"name": "Vert. ▲", "icon": "▲", "color": Color(0.4, 0.8, 1), "bad": false},
	"spd_up": {"name": "Tempo ▲", "icon": "▲", "color": Color(0.4, 1, 0.6), "bad": false},
	"regen": {"name": "Regen", "icon": "✚", "color": Color(0.4, 1, 0.5), "bad": false},
	"spott": {"name": "Spott", "icon": "!", "color": Color(1, 0.4, 0.3), "bad": false},
	"beschuetzt": {"name": "Beschützt", "icon": "◆", "color": Color(0.7, 0.85, 1), "bad": false},
	"konter": {"name": "Konter", "icon": "⚔", "color": Color(1, 0.8, 0.4), "bad": false},
	"unverwuestlich": {"name": "Unverwüstl.", "icon": "◆", "color": Color(1, 0.85, 0.3), "bad": false},
	"sicherer_krit": {"name": "Fokus", "icon": "✦", "color": Color(1, 1, 0.5), "bad": false},
	"verteidigt": {"name": "Abwehr", "icon": "◆", "color": Color(0.7, 0.85, 1), "bad": false},
	"geladen": {"name": "Lädt auf!", "icon": "!", "color": Color(1, 0.2, 0.2), "bad": false},
}

# ------------------------------------------------------------------ COMPANIONS
const COMPANIONS := {
	"jimmy": {"name": "Jimmy", "class": "tank", "sprite": "jimmy",
		"bio": "Ein Hahn wie ein Kleiderschrank. Würde keiner Mücke ein Haar krümmen – bis er von den Hallen hörte."},
	"vian": {"name": "Vian", "class": "heiler", "sprite": "vian",
		"bio": "Uralt, auf einem Auge blind. Schmeckt das Wetter und riecht Gefahr. Ihre Schlachtzeit ist lange vorbei."},
	"nugget": {"name": "Nugget", "class": "assassine", "sprite": "nugget",
		"bio": "Aus einer Legebatterie geflohen. Trägt noch ihren Fußring. Redet manchmal mit ihm."},
	"paprika": {"name": "Madame Paprika", "class": "magier", "sprite": "paprika",
		"bio": "Behauptet, sie sei in einem früheren Leben ein Zauberer in Wien gewesen. Niemand widerspricht."},
}

# ------------------------------------------------------------------ ITEMS
# type: weapon | armor | charm | food | key
const ITEMS := {
	"w_zahnstocher": {"name": "Rostiger Zahnstocher", "type": "weapon", "stats": {"atk": 3}, "price": 10,
		"desc": "Aus einem Strand-Cocktail. Hat schon Oliven getötet."},
	"w_fischgraete": {"name": "Fischgräten-Säbel", "type": "weapon", "stats": {"atk": 7, "spd": 1}, "price": 60,
		"desc": "Der Fisch hätte es so gewollt. Vermutlich."},
	"w_korkenzieher": {"name": "Korkenzieher", "type": "weapon", "stats": {"atk": 11, "crit": 5}, "price": 140,
		"desc": "Für Weinflaschen. Und Augen."},
	"w_machete": {"name": "Abgebrochene Machete", "type": "weapon", "stats": {"atk": 16}, "price": 260,
		"desc": "Ein Fischer brauchte sie nicht mehr."},
	"w_hackbeil": {"name": "Schlachterbeil", "type": "weapon", "stats": {"atk": 27, "crit": 5}, "price": 999,
		"desc": "Fühlt sich in einem Flügel erstaunlich richtig an."},
	"a_plastiktuete": {"name": "Plastiktüten-Cape", "type": "armor", "stats": {"def": 2, "res": 3}, "price": 15,
		"desc": "Hat die Insel überlebt. Wird uns alle überleben."},
	"a_kokoshelm": {"name": "Kokosnuss-Helm", "type": "armor", "stats": {"def": 6}, "price": 70,
		"desc": "Hart, rund, riecht nach Urlaub."},
	"a_sarong": {"name": "Touristen-Sarong", "type": "armor", "stats": {"def": 5, "res": 7, "mag": 3}, "price": 120,
		"desc": "\"I ♥ Gili\". Der Vorbesitzer liebte Gili nicht lange."},
	"a_kronkorken": {"name": "Kronkorken-Panzer", "type": "armor", "stats": {"def": 12, "res": 4}, "price": 240,
		"desc": "Aus hunderten Bierdeckeln vom Strand. Recycling!"},
	"c_haizahn": {"name": "Haifischzahn", "type": "charm", "stats": {"atk": 6, "mag": 6, "crit": 10}, "price": 0,
		"desc": "\"Mach deine Augen zu und fühl's.\" – ein toter Hai"},
	"c_kronkorken": {"name": "Glücks-Kronkorken", "type": "charm", "stats": {"spd": 3, "crit": 5}, "price": 90,
		"desc": "Mit Stern. Bringt Glück, behauptet der Gecko."},
	"c_splitter": {"name": "Erinnerungssplitter", "type": "charm", "icon": "k_kristall", "stats": {"mag": 7, "mp": 12}, "price": 0,
		"desc": "Summt leise. Manchmal flüstert er in deiner Stimme."},
	"c_pilzsporen": {"name": "Morchels Sporen", "type": "charm", "icon": "f_shake", "stats": {"mag": 5, "res": 6, "hp": 15}, "price": 0,
		"desc": "Ein Geschenk von Herrn Morchel. Bitte nicht inhalieren."},
	"c_punkte": {"name": "Glückspunkte", "type": "charm", "icon": "c_kronkorken", "stats": {"crit": 12, "spd": 2}, "price": 0,
		"desc": "Lieselottes siebter Punkt. Sie hatte nur sechs gebraucht."},
	"f_mango": {"name": "Mango", "type": "food", "effect": {"hp": 45}, "price": 12,
		"desc": "Heilt 45 HP. Saftig, süß, gestohlen."},
	"f_kokos": {"name": "Kokoswasser", "type": "food", "effect": {"mp": 22}, "price": 18,
		"desc": "Stellt 22 MP wieder her. Mit Strohhalm, wie die Touristen."},
	"f_wurm": {"name": "Zappelwurm", "type": "food", "effect": {"hp": 30, "buff": "spd_up", "battles": 2}, "price": 15,
		"desc": "Heilt 30 HP. Buff: Tempo ▲ für 2 Kämpfe. Er zappelt noch."},
	"f_nasigoreng": {"name": "Nasi Goreng", "type": "food", "effect": {"hp": 140, "buff": "atk_up", "battles": 2}, "price": 55,
		"desc": "Heilt 140 HP. Buff: Angriff ▲ für 2 Kämpfe. Ohne Huhn, bestellt."},
	"f_sambal": {"name": "Sambal-Glas", "type": "food", "effect": {"buff": "atk_up", "battles": 3, "team": true}, "price": 40,
		"desc": "Team-Buff: Angriff ▲ für 3 Kämpfe. Scharf. Schärfer. Gerächt."},
	"f_shake": {"name": "Magic-Mushroom-Shake", "type": "food", "effect": {"revive": 0.35}, "price": 60,
		"desc": "Belebt ein K.O.-Huhn mit 35% HP. Nebenwirkung: Farben."},
	"f_koerner": {"name": "Goldkörner", "type": "food", "effect": {"hp": 20, "mp": 10}, "price": 8,
		"desc": "Heilt 20 HP und 10 MP. Die Währung, die man essen kann."},
	"k_kristall": {"name": "Erinnerungsstein", "type": "key", "desc": "Ein Splitter deiner Vergangenheit."},
	"k_buch": {"name": "Buch der Hexe", "type": "key", "desc": "Alt, abgenutzt. Riecht nach Rauch."},
	"k_plastik": {"name": "Plastikmüll", "type": "key", "icon": "a_plastiktuete", "desc": "Für Opa Kura. Er sammelt, was ihr wegwerft."},
	"k_kalb": {"name": "Klößchens Glocke", "type": "key", "icon": "c_kronkorken", "desc": "Kleine Kuhglocke. Klingt traurig."},
	"k_pilz": {"name": "Pilzfreund", "type": "key", "icon": "f_shake", "desc": "Ein verängstigter kleiner Pilz in deinem Gefieder."},
	"k_punkt": {"name": "Marienkäfer-Punkt", "type": "key", "icon": "c_kronkorken", "desc": "Ein schwarzer Punkt. Gehört einer Dame."},
	"k_karte": {"name": "Zerknitterte Schatzkarte", "type": "key", "icon": "k_buch",
		"desc": "\"Drei Schritte südlich vom gehörnten Schädel, im Schatten des toten Baums.\" Darunter: ein Kreuz in der Steppe."},
	"l_perle": {"name": "Schwarze Perle", "type": "loot", "icon": "k_kristall", "price": 240, "desc": "Aus der Gezeitengrotte. Toké zahlt gut dafür."},
	"l_goldzahn": {"name": "Goldzahn", "type": "loot", "icon": "c_kronkorken", "price": 300, "desc": "Gehörte mal einem Touristen. Er braucht ihn nicht mehr."},
	"c_hexenkette": {"name": "Kette der jungen Hexe", "type": "charm", "icon": "c_haizahn", "stats": {"mag": 8, "res": 8, "hp": 20}, "price": 0,
		"desc": "Muscheln, Knochen, ein Hühnerknöchelchen. Sie summt, wenn die Sonne verschwindet."},
}

## Toké's stock grows with the story. [flag needed, items]. Korkenzieher, Machete & Glücks-Kronkorken exist only here.
const SHOP_TIERS := [
	["", ["f_mango", "f_kokos", "f_koerner", "a_plastiktuete", "c_kronkorken"]],
	["arena_done", ["f_wurm", "f_shake", "a_kokoshelm", "w_fischgraete"]],
	["steppe_intro", ["f_nasigoreng", "a_sarong", "w_korkenzieher"]],
	["revolution", ["f_sambal", "a_kronkorken", "w_machete"]],
]

func shop_stock() -> Array:
	var out: Array = []
	for t in SHOP_TIERS:
		if t[0] == "" or Game.flag(t[0]):
			out += t[1]
	return out

func sell_price(id: String) -> int:
	var p: int = ITEMS[id].get("price", 0)
	if ITEMS[id]["type"] == "key" or p <= 0:
		return 0
	return maxi(1, p / 2)

# ------------------------------------------------------------------ ENEMIES
const ENEMIES := {
	"crab": {"name": "Wütende Krabbe", "sprite": "crab", "hp": 26, "atk": 7, "def": 4, "mag": 2, "res": 3, "spd": 5,
		"xp": 7, "grains": 3, "skills": ["e_zwick"], "drops": [["f_mango", 0.12]],
		"quips": ["*klack klack*", "Seitwärts in den Tod!"], "death": "*blubb*"},
	"tourist_m": {"name": "Sonnenbrand-Tourist", "sprite": "tourist_m", "hp": 40, "atk": 8, "def": 4, "mag": 3, "res": 3, "spd": 3,
		"xp": 11, "grains": 14, "skills": ["e_rempler", "e_sonnencreme"], "drops": [["f_kokos", 0.15]],
		"quips": ["Ich hab All-Inclusive gebucht!", "Schatz, das Huhn guckt komisch!", "Ist das hier Bio?"],
		"death": "Das ... gibt eine ... schlechte Bewertung ..."},
	"tourist_f": {"name": "Influencerin", "sprite": "tourist_f", "hp": 34, "atk": 6, "def": 4, "mag": 8, "res": 6, "spd": 7,
		"xp": 12, "grains": 16, "skills": ["e_selfie", "e_story", "e_rempler"], "drops": [["f_kokos", 0.15]],
		"quips": ["OMG, ein Killer-Huhn! Content!", "Link in Bio!", "Das wird viral!"],
		"death": "Vergesst nicht ... zu liken ..."},
	"macaque": {"name": "Diebischer Makake", "sprite": "macaque", "hp": 32, "atk": 10, "def": 5, "mag": 3, "res": 4, "spd": 18,
		"xp": 13, "grains": 10, "skills": ["e_klauen", "e_banane"], "drops": [["f_mango", 0.25]],
		"quips": ["Uuh uuh! Meins!", "*klaut dir fast eine Feder*"], "death": "*kreisch*"},
	"guard": {"name": "Resort-Security", "sprite": "guard", "hp": 80, "atk": 14, "def": 10, "mag": 3, "res": 5, "spd": 12,
		"xp": 22, "grains": 25, "skills": ["e_schlagstock", "e_rempler"], "drops": [["f_kokos", 0.2]],
		"quips": ["Hühner haben hier keinen Zutritt!", "Zeig mal dein Armband."], "death": "Ich ... hatte ... noch zwei Wochen ... bis zur Rente ..."},
	"farmer": {"name": "Reisbauer", "sprite": "farmer", "hp": 72, "atk": 17, "def": 7, "mag": 3, "res": 5, "spd": 8,
		"xp": 20, "grains": 18, "skills": ["e_mistgabel", "e_rempler"], "drops": [["f_koerner", 0.3], ["f_wurm", 0.12]],
		"quips": ["Zurück in den Stall!", "Du bist doch die vom Made!"], "death": "Die ... Ernte ..."},
	"fisher": {"name": "Fischer", "sprite": "fisher", "hp": 78, "atk": 18, "def": 8, "mag": 3, "res": 6, "spd": 9,
		"xp": 24, "grains": 22, "skills": ["e_netz", "e_machete"], "drops": [["w_fischgraete", 0.06], ["f_wurm", 0.15]],
		"quips": ["Heute fange ich Hühnchen!", "Im Netz waren wieder nur Dosen ..."], "death": "Endlich ... Ruhe vom Meer ..."},
	"fox": {"name": "Steppenfuchs", "sprite": "fox", "hp": 62, "atk": 20, "def": 6, "mag": 5, "res": 6, "spd": 19,
		"xp": 22, "grains": 6, "skills": ["e_biss"], "drops": [["f_wurm", 0.2]],
		"quips": ["*schnüffel* ... Abendessen.", "Lauf, kleines Huhn."], "death": "*jaul*"},
	"dog": {"name": "Kettenhund", "sprite": "dog", "hp": 84, "atk": 22, "def": 9, "mag": 3, "res": 6, "spd": 15,
		"xp": 28, "grains": 8, "skills": ["e_biss", "e_bellen"], "drops": [["f_mango", 0.2]],
		"quips": ["WUFF!", "*knurr*"], "death": "*winsel* ... braver ... Hund ..."},
	"bookie": {"name": "Buchmacher Benny", "sprite": "bookie", "hp": 230, "atk": 17, "def": 9, "mag": 11, "res": 8, "spd": 7,
		"xp": 130, "grains": 160, "boss": true, "skills": ["e_goldkette", "e_bestechung", "e_wettschein", "e_rempler"], "drops": [["w_korkenzieher", 1.0]],
		"quips": ["Ich wette 10 zu 1 auf deinen Tod!", "Der Hahn gehört MIR!", "Jeder hat seinen Preis, Huhn."],
		"death": "Die Wette ... war ... manipuliert ..."},
	"wolf": {"name": "Der Wolf", "sprite": "wolf", "hp": 680, "atk": 29, "def": 14, "mag": 22, "res": 12, "spd": 13,
		"xp": 420, "grains": 500, "boss": true, "skills": ["e_wolfsbiss", "e_knirschen", "e_abriss", "e_bauantrag"], "drops": [["a_kronkorken", 1.0]],
		"quips": ["*knirsch* *knirsch*", "Hier entsteht: Gili Genting Luxury Resort!", "Die Steppe gehört dem, der zahlt."],
		"death": "Mein ... Resort ... *knirsch* ..."},
	"farmhand": {"name": "Hofknecht", "sprite": "farmer", "hp": 120, "atk": 26, "def": 12, "mag": 3, "res": 8, "spd": 9,
		"xp": 40, "grains": 30, "skills": ["e_mistgabel", "e_sicheln"], "drops": [["f_nasigoreng", 0.15]],
		"quips": ["Wer hat das Licht ausgemacht?!", "Da! Ein Huhn mit Messer!"], "death": "Sag ... dem Bauern ... nichts ..."},
	"nightdog": {"name": "Hofhund", "sprite": "dog", "hp": 120, "atk": 28, "def": 12, "mag": 3, "res": 8, "spd": 17,
		"xp": 42, "grains": 10, "skills": ["e_biss", "e_bellen"], "drops": [["f_wurm", 0.2]],
		"quips": ["*knurr*", "WUFF WUFF!"], "death": "*winsel*"},
	"bauer": {"name": "Bauer Made", "sprite": "bauer", "hp": 420, "atk": 27, "def": 12, "mag": 8, "res": 10, "spd": 8,
		"xp": 0, "grains": 0, "boss": true, "skills": ["e_mistgabel", "e_hilfe", "e_sicheln"], "drops": [],
		"quips": ["Du bist drei Tage zu spät, Ania!", "Ich hab dich großgezogen!", "Der Pakt, Huhn! DER PAKT!"],
		"death": "Der ... Pakt ... war ... heilig ..."},
	"butcher": {"name": "Der Schlachter", "sprite": "butcher", "hp": 1850, "atk": 49, "def": 20, "mag": 10, "res": 16, "spd": 10,
		"xp": 0, "grains": 0, "boss": true, "skills": ["e_haken", "e_hackbeil", "e_rupfen", "e_schlachtzeit_laden"], "drops": [],
		"quips": ["Hab dich erwartet, Hühnchen.", "Deine Schlachtzeit war vor drei Tagen.", "Ich mach das seit dreißig Jahren. Ihr wehrt euch nie."],
		"death": "Ihr ... wehrt ... euch ... ja ... doch ..."},
}

# ------------------------------------------------------------------ helpers
var _tex_cache := {}

func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t

func sprite_tex(sprite_name: String) -> Texture2D:
	var t := tex("res://assets/sprites/%s.png" % sprite_name)
	if t == null:
		t = _placeholder(sprite_name)
	return t

func item_icon(item_id: String) -> Texture2D:
	var it: Dictionary = ITEMS.get(item_id, {})
	var icon: String = it.get("icon", item_id)
	return tex("res://assets/sprites/items/%s.png" % icon)

func ui_tex(n: String) -> Texture2D:
	return tex("res://assets/ui/%s.png" % n)

func _placeholder(n: String) -> Texture2D:
	var img := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(float(n.hash() % 360) / 360.0, 0.6, 0.9)
	img.fill(c)
	var t := ImageTexture.create_from_image(img)
	_tex_cache["res://assets/sprites/%s.png" % n] = t
	return t

func skill(id: String) -> Dictionary:
	return SKILLS.get(id, {})

func class_skills(cls: String) -> Array:
	var out: Array = []
	for b in CLASSES[cls]["branches"]:
		out += b["skills"]
	return out

func skill_cost(cls: String, sid: String) -> int:
	for b in CLASSES[cls]["branches"]:
		var i: int = b["skills"].find(sid)
		if i >= 0:
			return i + 1
	return 1

func skill_req(cls: String, sid: String) -> String:
	for b in CLASSES[cls]["branches"]:
		var i: int = b["skills"].find(sid)
		if i > 0:
			return b["skills"][i - 1]
	return ""

func xp_to_next(lv: int) -> int:
	return int(14.0 * pow(lv, 1.55) + 12.0)
