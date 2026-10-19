class_name Cutscenes
extends RefCounted
## All in-engine cinematics. Each scene builds its own little set, then calls cs.begin()
## and plays shots. Captions always wait for the player.

static func hero_sprite() -> String:
	return Data.CLASSES[Game.player_class]["sprite"]

static func begin(cs: Cutscene, fade := 0.9) -> void:
	UI.letterbox(true)
	await UI.fade_in(fade)

static func tick_clock(cs: Cutscene, times: int, pitch := 0.5) -> void:
	for i in times:
		if not is_instance_valid(cs) or cs.skip_requested:
			return
		Audio.sfx("ui_move", pitch if i % 2 == 0 else pitch * 0.8, 0.6)
		await cs.get_tree().create_timer(0.5).timeout

static func screams(cs: Cutscene, count: int) -> void:
	for i in count:
		if not is_instance_valid(cs) or cs.skip_requested:
			return
		Audio.sfx("enemy_die", randf_range(0.6, 1.3), randf_range(0.25, 0.55))
		await cs.get_tree().create_timer(randf_range(0.6, 1.8)).timeout

# ======================================================================= 1. INTRO – die Halle
static func intro(cs: Cutscene) -> void:
	var rows := []
	for z in 11:
		rows.append("N".repeat(30) if z == 0 else "N" + "n".repeat(28) + "N")
	cs.build_set("dark", rows, ["dust"])
	for i in 21:
		var x := 1.6 + i * 1.3
		cs.prop("cages", Vector3(x, 0, 1.6), i % 2 == 0)
		cs.prop("cages", Vector3(x, 1.35, 1.55), i % 3 == 0)
		if i % 2 == 0:
			cs.prop("cages", Vector3(x + 0.3, 0, 9.4), true)
	cs.actor("ania", "hen_sleep", Vector3(15, 0, 5.4))
	cs.spot(Vector3(17, 7, -1), Vector3(15, 0, 5.4), Color(0.75, 0.85, 1.0), 9.0, 18.0, 16.0)
	cs.atmos.env.ambient_light_color = Color(0.35, 0.42, 0.6)
	cs.atmos.env.ambient_light_energy = 1.5
	for x in [4, 10, 20, 26]:
		cs.light(Vector3(x, 2.6, 4.5), Color(0.45, 0.55, 0.85), 1.6, 7.0)
	cs.light(Vector3(26, 2.4, 6), Color(0.9, 0.2, 0.1), 1.6, 8.0, true)
	cs.light(Vector3(15, 1.2, 7), Color(0.9, 0.85, 0.8), 1.4, 3.5)
	cs.set_dof(8.0)
	cs.cam_set(Vector3(26, 2.4, 9.5), Vector3(22, 1.2, 2.0), 46.0)
	Audio.music("memory", 1.5)
	Audio.ambient("night_loop")
	await begin(cs, 1.5)
	cs.cam_to(Vector3(9, 2.0, 9.5), Vector3(11, 1.1, 2.0), 16.0)
	await cs.say("Inmitten einer finsteren Halle beginnt ein neuer Tag.")
	await cs.say("Nicht einmal einen halben Quadratmeter Käfig für jede verlorene Seele.")
	await cs.cam_to(Vector3(15.7, 0.9, 7.6), Vector3(15, 0.35, 5.4), 3.5, 34.0).finished
	cs.set_dof(2.4, 0.16)
	Audio.sfx("cluck2", 0.7, 0.4)
	await cs.say("Nahrung? Nein! Ich nenne es pure Chemie.")
	cs.cam_to(Vector3(15.9, 1.0, 7.8), Vector3(16.5, 4.8, 0.0), 5.0, 40.0)
	await cs.say("So lebt ein Chicken in eurer Welt, nicht wahr? Misshandelt, vergiftet und bis zuletzt gequält.")
	await cs.say("Doch ... ihr Menschen fühlt euch fabelhaft, richtig?")
	await cs.cam_to(Vector3(15.6, 0.8, 7.4), Vector3(15, 0.4, 5.4), 2.5, 32.0).finished
	cs.swap("ania", hero_sprite())
	UI.flash(Color(1, 1, 1), 0.8, 0.9)
	Audio.sfx("memory_flash")
	await cs.say("Auf Gili Genting ist es anders. Hier gibt es den Pakt.")
	await cs.wait(0.6)

# ======================================================================= 2. PAKT – Schlüpfen im Morgenlicht
static func pakt(cs: Cutscene) -> void:
	var rows := []
	for z in 14:
		var r := ""
		for x in 22:
			r += ":" if (z > 8 and x > 4 and x < 17) else "\""
		rows.append(r)
	cs.build_set("dusk", rows, ["dust"], false, Color(0.95, 0.6, 0.3))
	cs.add_child(House.build({"x": 13, "z": 1, "w": 6, "d": 4, "style": "barn"}, func(n): return Data.tex("res://assets/textures/%s.png" % n), false))
	for x in [2, 4, 6, 18, 20]:
		cs.prop("fence", Vector3(x, 0, 3.5))
	cs.prop("haybale", Vector3(10, 0, 8.6))
	cs.prop("weathervane", Vector3(4, 0, 2.5))
	var chick := cs.actor("chick", "chick", Vector3(10, 0.25, 9.0))
	chick.scale = Vector3(0.01, 0.01, 1)
	var bauer := cs.actor("bauer", "bauer", Vector3(12.2, 0, 6.2), true)
	bauer.set_tint(Color(0.06, 0.04, 0.05))
	cs.spot(Vector3(1, 3.5, 12), Vector3(10, 0.3, 9), Color(1.0, 0.75, 0.4), 12.0, 14.0, 20.0)
	cs.set_dof(2.0, 0.16)
	cs.cam_set(Vector3(10.7, 0.55, 10.6), Vector3(10, 0.35, 9.0), 34.0)
	Audio.music("memory", 1.0)
	await begin(cs)
	tick_clock(cs, 40)
	await cs.say("Bei meiner Geburt wurde ein Pakt mit dem Menschen geschlossen, dessen Besitz ich bin.")
	for i in 3:
		Audio.sfx("peck", 1.3 + i * 0.15, 0.8)
		cs.shake(0.25)
		await cs.wait(0.45)
	var tw := cs.create_tween()
	tw.tween_property(chick, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.sfx("cluck1", 1.8, 0.8)
	UI.flash(Color(1, 0.85, 0.5), 0.6, 0.5)
	await cs.say("Schon als der erste Sonnenstrahl mich durch die angebrochene Eierschale erleuchtete ...")
	cs.set_dof(7.5, 0.1)
	cs.cam_to(Vector3(9.4, 2.6, 14.5), Vector3(11, 1.2, 6.5), 6.0, 42.0)
	await cs.say("... erfuhr ich den exakten Zeitpunkt meiner Schlachtung.")
	await cs.cam_to(Vector3(11.7, 1.7, 8.6), Vector3(12.2, 1.6, 6.2), 3.0, 30.0).finished
	cs.set_dof(2.6, 0.14)
	bauer.flash_hit(Color(1, 0.1, 0.05), 0.8)
	Audio.sfx("thunder", 0.6, 0.6)
	await cs.say("Es wird mir gestattet, uneingeschränkt auf der gesamten Insel zu verweilen.")
	await cs.say("Im Gegenzug muss ich zurückkehren. Zu einer bestimmten Zeit. Meiner Schlachtzeit.")
	await cs.wait(0.4)

# ======================================================================= 3+4. KLIPPE
static func build_cliff(cs: Cutscene) -> void:
	var rows := []
	for z in 22:
		var r := ""
		for x in 26:
			var half := 5.5 if z > 7 else (2.0 + (z - 3) * 0.8)
			var inside: bool = z >= 3 and abs(x - 12.5) <= half + sin(z * 0.9 + x) * 0.6
			r += ("G" if (x + z) % 5 else "K") if inside else "~"
		rows.append(r)
	cs.build_set("storm", rows, ["storm"], true)
	cs.prop("dead_tree", Vector3(9, 2.2, 12), false, 0.05)
	cs.prop("thorn_bush", Vector3(16, 2.2, 10))
	cs.prop("rock_pile", Vector3(8, 2.2, 8))
	cs.prop("dead_chicken", Vector3(11.6, 2.2, 4.4))
	cs.light(Vector3(12, 3.5, 6), Color(0.5, 0.6, 1.0), 1.2, 7.0)

static func klippe(cs: Cutscene) -> void:
	build_cliff(cs)
	cs.actor("ania", hero_sprite(), Vector3(12.5, 2.2, 17))
	cs.set_dof(6.0)
	cs.cam_set(Vector3(12.5, 5.2, 22.5), Vector3(12.5, 2.6, 14), 44.0)
	Audio.music("cliff", 1.0)
	await begin(cs)
	cs.move("ania", Vector3(12.4, 2.2, 9.5), 4.5)
	cs.cam_to(Vector3(13.4, 3.8, 14.0), Vector3(12.4, 2.6, 7.0), 4.5)
	await cs.say("Der Weg ist uneben und steinig. Ihre Schritte werden langsamer.")
	await cs.move("ania", Vector3(12.9, 2.2, 6.0), 2.5)
	cs.set_dof(2.6, 0.15)
	await cs.cam_to(Vector3(10.6, 2.75, 7.0), Vector3(11.8, 2.4, 4.6), 3.0, 34.0).finished
	cs.shake(0.6)
	UI.flash(Color(0.8, 0.85, 1.0), 0.4, 0.6)
	Audio.sfx("thunder")
	await cs.say("Kurz vor der Abbruchkante liegt das erkrankte Chicken von damals.")
	await cs.say("Regungslos. Der Wind saust durch die kalten Federn. Und doch scheint es, als wäre er nun endlich frei.")
	cs.set_dof(9.0, 0.08)
	await cs.cam_to(Vector3(19.0, 6.5, 12.0), Vector3(12.2, 2.0, 4.0), 5.0, 42.0).finished
	await cs.say("Plötzlich strömen ihr Tränen aus den Augen. In ihrem Leib macht sich eine längst verborgene Wut breit.")

static func revolution(cs: Cutscene) -> void:
	build_cliff(cs)
	var hero := Vector3(12.6, 2.2, 5.6)
	cs.actor("ania", hero_sprite(), hero)
	cs.set_dof(3.2, 0.14)
	cs.cam_set(Vector3(12.6, 2.9, 9.0), hero + Vector3(0, 0.5, 0), 36.0)
	Audio.music("revolution", 0.4)
	await begin(cs, 0.6)
	cs.orbit(hero, 3.2, 0.9, 0.0, 300.0, 26.0)
	await cs.say("Sie schließt die Augen und bändigt die aufgeregte Atmung.")
	await cs.say("Sie fühlt es. Eine Erfahrung, so intensiv wie das Eierlegen.")
	cs.atmos.sun.light_color = Color(1.0, 0.25, 0.2)
	cs.atmos.env.background_color = Color(0.25, 0.02, 0.02)
	cs.atmos.env.fog_light_color = Color(0.35, 0.05, 0.05)
	UI.flash(Color(1, 0.2, 0.15), 0.8, 0.8)
	cs.shake(0.8)
	Audio.sfx("thunder", 0.7)
	await cs.say("Es war kein Ende!")
	# the island's chickens rise behind her
	var army := ["cls_base", "chick", "cls_krieger", "cls_assassine", "cls_tank", "chick", "cls_base", "cls_heiler", "cls_magier", "cls_base"]
	for i in army.size():
		var p := Vector3(8.5 + i * 0.9, 2.2, 10.5 + (i % 3) * 1.6)
		var s := cs.actor("a%d" % i, army[i], p, i % 2 == 0)
		s.set_tint(Color(0.35, 0.05, 0.05))
		s.set_emission(0.25)
		s.set_alpha(0.0)
		var tw := cs.create_tween()
		tw.tween_interval(i * 0.25)
		tw.tween_method(func(v): s.set_alpha(v), 0.0, 1.0, 0.6)
	await cs.say("Der Zeiger schlug auf Schlachten – und sie fühlte sich lebendiger als je zuvor.")
	await cs.say("Eure Lügen, eure Taten und vor allem eure Gier – all das widert mich an.", Game.player_name)
	cs.set_dof(6.0, 0.1)
	await cs.cam_to(Vector3(12.6, 5.0, 18.0), Vector3(12.6, 2.6, 8.0), 3.0, 44.0).finished
	UI.flash(Color(1, 0.1, 0.05), 1.0, 1.0)
	Audio.sfx("thunder", 0.55)
	cs.shake(1.0)
	await cs.say("Rache. An denjenigen, die es verdient haben. Der Zeiger schlägt auf Revolution.")

# ======================================================================= 5. DER PLAN – Stromausfall
static func plan(cs: Cutscene) -> void:
	var rows := []
	for z in 18:
		var r := ""
		for x in 34:
			r += ":" if (z >= 9 and z <= 11) else "\""
		rows.append(r)
	cs.build_set("moon", rows, ["fireflies"])
	var houses := []
	var loader := func(n): return Data.tex("res://assets/textures/%s.png" % n)
	for i in 5:
		var e := {"x": 2 + i * 6, "z": 4, "w": 4, "d": 3, "style": ["bamboo", "wood", "plaster", "bamboo", "wood"][i], "lit": true}
		var h := House.build(e, loader, true)
		cs.add_child(h)
		houses.append(h)
	for i in 4:
		var e2 := {"x": 4 + i * 7, "z": 13, "w": 4, "d": 3, "style": ["wood", "bamboo", "plaster", "wood"][i], "lit": true}
		var h2 := House.build(e2, loader, true)
		cs.add_child(h2)
		houses.append(h2)
	var lamps := []
	for x in [5, 11, 17, 23, 29]:
		cs.prop("lantern", Vector3(x, 0, 8.6))
		lamps.append(cs.light(Vector3(x, 1.2, 8.8), Color(1.0, 0.6, 0.3), 2.0, 5.0, true))
	cs.prop("palm", Vector3(1, 0, 9), false, 0.2)
	cs.prop("palm", Vector3(32, 0, 10), true, 0.2)
	cs.set_dof(10.0, 0.1)
	cs.cam_set(Vector3(30, 7.5, 20), Vector3(17, 0.5, 9), 46.0)
	Audio.music("farm", 1.0)
	await begin(cs)
	cs.cam_to(Vector3(8, 6.0, 19), Vector3(14, 0.5, 9), 12.0)
	await cs.say("Der Plan lautet wie folgt: Am Abend des nächsten Vollmondes wird heimlich die zentrale Stromversorgung gekappt.")
	# power cut
	Audio.sfx("power_down")
	for l in lamps:
		cs.create_tween().tween_property(l, "light_energy", 0.0, 0.4)
	for h in houses:
		for c in h.get_children():
			if c is OmniLight3D:
				cs.create_tween().tween_property(c, "light_energy", 0.0, 0.5)
			elif c is MeshInstance3D and c.material_override is StandardMaterial3D and c.material_override.emission_enabled:
				c.material_override.emission_enabled = false
				c.material_override.albedo_color = Color(0.05, 0.06, 0.08)
	await cs.wait(1.0)
	await cs.say("Ihr schlaft gemütlich in euren Gemächern. Draußen schleicht sich der Tod in aller Stille an.")
	# red eyes everywhere
	var spots := [Vector3(3, 2.6, 6.5), Vector3(9.5, 2.5, 6.4), Vector3(15, 2.6, 6.6), Vector3(21, 2.4, 6.4), Vector3(27, 2.5, 6.5),
		Vector3(6, 0, 10.2), Vector3(12, 0, 10.6), Vector3(18, 0, 9.8), Vector3(24, 0, 10.4), Vector3(30, 0, 10.0), Vector3(8, 2.6, 15.5), Vector3(22, 2.6, 15.6)]
	for i in spots.size():
		var s := cs.actor("c%d" % i, ["cls_base", "chick", "cls_assassine", "cls_krieger"][i % 4], spots[i], i % 2 == 0)
		s.set_tint(Color(0.12, 0.1, 0.14))
		s.set_alpha(0.0)
		var eyes := Label3D.new()
		eyes.text = "• •"
		eyes.font = UI.font
		eyes.font_size = 20
		eyes.pixel_size = 0.008
		eyes.modulate = Color(3.0, 0.2, 0.15)
		eyes.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		eyes.position = Vector3(0.08, s.height * 0.78, 0.05)
		s.add_child(eyes)
		var tw := cs.create_tween()
		tw.tween_interval(i * 0.18)
		tw.tween_method(func(v): s.set_alpha(v), 0.0, 1.0, 0.5)
	cs.cam_to(Vector3(17, 2.0, 13.5), Vector3(17, 1.0, 8.0), 10.0, 40.0)
	await cs.say("Die Jungen und die Flinken nutzen jedes Schlupfloch, um in die Häuser einzudringen.")
	await cs.say("Ihr Menschen glaubt, ihr hättet die Kontrolle über alle Lebewesen auf diesem Planeten.")
	Audio.sfx("cluck_angry", 0.8)
	await cs.say("Doch wir werden euch zeigen, dass wir nur eine Nacht benötigen, um den Spieß umzudrehen.")

# ======================================================================= 6. DER WEISSE RAUM – das Lied der Heuschrecke
static func void_song(cs: Cutscene) -> void:
	var rows := []
	for z in 16:
		rows.append("v".repeat(24))
	cs.build_set("void", rows, ["void"])
	var gh := cs.actor("gh", "grasshopper", Vector3(12, 0, 8), true, false)
	gh.scale = Vector3(1, -1, 1)
	gh.position.y = gh.height
	var ants := AntTrail.new()
	ants.position = Vector3(12, 0, 8)
	cs.add_child(ants)
	cs.actor("ania", hero_sprite(), Vector3(10.6, 0, 8.2))
	cs.set_dof(3.0, 0.1)
	cs.cam_set(Vector3(12, 1.2, 11.2), Vector3(11.6, 0.4, 8), 38.0)
	Audio.music("void", 1.0)
	await begin(cs, 1.2)
	cs.orbit(Vector3(11.5, 0, 8), 3.4, 1.1, 0.0, 140.0, 40.0)
	var lines := [
		"Zögerlich schließt das Chicken die Augen. Ein Gesang erklingt, so herrlich wie der Tausender Vögel.",
		"♪ Unvorhersehbar ist der Schlüssel zum Glück. ♪",
		"♪ Die Menge macht das Gift, durch das jenes Licht der Menschen in einem Augenblick erlischt. ♪",
		"♪ Der Mensch war Tier und kann sich wieder wandeln – so kann auch das Tier hinterlistig wie die Menschheit handeln. ♪",
		"♪ Die Freiheit, die du wahrlich hast, ist zu entscheiden, wie und was du machst. ♪",
		"♪ Doch das Leid, das dich begleitet, liegt der Entscheidung inne, die dich leitet. ♪",
	]
	for l in lines:
		cs.notes(Vector3(12, 0.3, 8), 5)
		await cs.say(l, "Heuschrecke" if l.begins_with("♪") else "")
	cs.set_meta("end_color", Color(1, 1, 1))

# ======================================================================= 7. DER SPIEGEL
static func mirror(cs: Cutscene) -> void:
	var rows := ["WWWWWWWWWWWW", "WwwwwwwwwwwW", "WwwwwwwwwwwW", "WwwwwwwcccwW", "WwwwwwwcccwW", "WwwwwwwwwwwW", "WwwwwwwwwwwW", "WWWWWwwWWWWW"]
	cs.build_set("eclipse", rows, ["ash"])
	cs.prop("shelf", Vector3(1.5, 0, 1.5))
	cs.prop("altar", Vector3(9.5, 0, 1.5))
	cs.prop("bed", Vector3(9.5, 0, 5.5))
	cs.prop("mirror_stand", Vector3(6, 0, 1.5))
	var refl := cs.actor("refl", hero_sprite(), Vector3(6.02, 0.55, 1.56), true, false)
	refl.scale = Vector3(0.52, 0.52, 1)
	refl.set_tint(Color(0.7, 0.75, 0.9))
	cs.actor("ania", hero_sprite(), Vector3(6, 0, 3.6))
	cs.light(Vector3(6.3, 1.3, 5.6), Color(1.0, 0.8, 0.65), 1.8, 5.0)
	cs.light(Vector3(6, 1.2, 2.4), Color(0.7, 0.8, 1.0), 1.4, 2.5)
	cs.atmos.env.ambient_light_energy = 1.1
	var red := cs.light(Vector3(4, 2.2, 3), Color(1.0, 0.25, 0.15), 2.5, 8.0, false, true)
	var pulse := cs.create_tween().set_loops()
	pulse.tween_property(red, "light_energy", 1.0, 1.2)
	pulse.tween_property(red, "light_energy", 3.0, 1.2)
	cs.set_dof(4.0, 0.12)
	cs.cam_set(Vector3(6.6, 1.6, 7.6), Vector3(6, 0.8, 2), 40.0)
	Audio.music("cliff", 1.0)
	await begin(cs)
	screams(cs, 14)
	cs.cam_to(Vector3(6.2, 1.0, 3.3), Vector3(6.02, 0.85, 1.5), 9.0, 30.0)
	await cs.say("Während sich der Mond schleichend vor die Sonne drängt, fühlt sie, dass sich etwas Grundlegendes verändert.")
	await cs.say("Der Raum scheint enger zu werden. Zu schrumpfen. Sie zu zerquetschen.")
	cs.set_dof(1.8, 0.18)
	cs.shake(0.6)
	UI.flash(Color(1, 1, 1), 0.9, 1.0)
	Audio.sfx("memory_flash")
	cs.swap("refl", "tourist_f")
	var r2: PixelSprite = cs.actors["refl"]
	r2.scale = Vector3(0.3, 0.3, 1)
	await cs.say("Im Spiegel erkennt sie einen Menschen. Ein Mädchen. Vielleicht schon eine junge Dame.")
	await cs.say("Draußen ertönt grauenvolles Geschrei. Und ein jeder verspürt dasselbe altneue Leid.")

# ======================================================================= 8. DAS ENDE – Geburtstag
static func ending(cs: Cutscene) -> void:
	var rows := ["WWWWWWWWWWWWWW", "WwwwwwwwwwwwwW", "WwwwwwwwwwwwwW", "WwwwwcccccwwwW", "WwwwwcccccwwwW", "WwwwwwwwwwwwwW", "WwwwwwwwwwwwwW", "WWWWWWWWWWWWWW"]
	cs.build_set("interior", rows, [])
	cs.prop("shelf", Vector3(2, 0, 1.5))
	cs.prop("wardrobe", Vector3(11.5, 0, 1.5))
	cs.prop("table_rice", Vector3(7, 0, 4.2), false, 0.0, 1.4)
	cs.prop("items/f_nasigoreng", Vector3(7, 0.62, 4.3))
	cs.prop("pots", Vector3(1.5, 0, 5.5))
	cs.actor("hannah", "tourist_f", Vector3(5.6, 0, 3.6))
	cs.actor("mann", "tourist_m", Vector3(8.6, 0, 3.5), true)
	for x in [6.4, 7.0, 7.6]:
		cs.light(Vector3(x, 1.0, 4.3), Color(1.0, 0.65, 0.3), 1.4, 3.0, true)
	cs.light(Vector3(7, 2.4, 6), Color(1.0, 0.8, 0.6), 0.8, 8.0)
	var ghost := cs.actor("ghost", hero_sprite(), Vector3(12.4, 0.3, 1.3), true)
	ghost.set_alpha(0.0)
	ghost.set_emission(0.6)
	ghost.set_tint(Color(0.75, 0.85, 1.0))
	cs.set_dof(6.0, 0.1)
	cs.cam_set(Vector3(7, 2.4, 10.5), Vector3(7, 0.9, 3.5), 42.0)
	Audio.music("ending", 1.5)
	await begin(cs, 1.2)
	cs.cam_to(Vector3(7, 1.5, 7.2), Vector3(7, 0.8, 3.8), 12.0, 36.0)
	await cs.say("Heute versammelt sich die gesamte Familie für einen besonderen Tag.")
	await cs.say("Ihr ältester Sohn feiert den siebten Geburtstag. Und selbstverständlich wird sein liebstes Gericht serviert.")
	cs.set_dof(3.0, 0.15)
	await cs.cam_to(Vector3(7.2, 1.1, 5.6), Vector3(7, 0.7, 4.3), 2.5, 28.0).finished
	await cs.say("Chicken Wings mit Pommes.")
	cs.set_dof(5.5, 0.12)
	cs.cam_to(Vector3(9.8, 1.2, 5.8), Vector3(12.4, 0.8, 1.3), 4.0, 34.0)
	await cs.wait(2.5)
	await cs.fade_actor("ghost", 0.5, 2.5)
	Audio.sfx("cluck1", 0.6, 0.4)
	await cs.wait(2.0)
