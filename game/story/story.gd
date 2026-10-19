extends Node
## All story & quest events. Map entities reference these by name: Story.run("name", actor).
## Lines marked as quotes are taken (lightly adapted) from the book "Gili Genting".

var main
var N: String:
	get:
		return Game.player_name

func run(ev: String, actor = null) -> void:
	var m := "ev_" + ev
	if has_method(m):
		await call(m, actor)
	else:
		push_warning("Story event missing: " + ev)

func map():
	return main.map if main else null

func say(lines: Array) -> void:
	await UI.talk(lines)

func ask(who: String, text: String, opts: Array) -> int:
	return await UI.ask(who, text, opts)

func fight(group: Array, opts := {}) -> String:
	var r: String = await main.battle(group, opts)
	return r

func recruit(id: String) -> void:
	Game.recruit(id)
	Game.set_flag(id + "_recruited")
	Audio.sfx("level_up")
	if Game.party.has(id):
		UI.toast("%s schließt sich dem Team an!" % Game.char_name(id))
	else:
		UI.toast("%s wartet am Lagerfeuer. (Team voll – im Menü tauschen)" % Game.char_name(id))

func think(text: String) -> void:
	await say([[N, text]])

# ======================================================================= PROLOG
func intro() -> void:
	await main.cutscene("intro", false)

# ======================================================================= KAPITEL 1: STRAND
func ev_strand_enter(_a) -> void:
	if Game.flag("strand_intro"):
		return
	Game.set_flag("strand_intro")
	await UI.chapter("Kapitel 1", "Der Sturm")
	await UI.narrate([
		"Ein plötzlicher und äußerst heftiger Sturm hat alles niedergemäht.",
		"Salz im Gefieder. Sand im Schnabel. Und keine einzige Erinnerung.",
	], "book", 0.7)
	await say([
		[N, "Wo ... bin ich?"],
		[N, "Und warum fühlt es sich an, als würde in mir eine Uhr ticken?"],
		["", "Tipp: [E] interagieren · [TAB] Menü · [SHIFT] rennen. Berühre Gegner, um zu kämpfen."],
	])
	Game.start_quest("main")
	UI.show_hud(true)

func ev_mem_pakt(_a) -> void:
	if Game.flag("mem1"):
		await say([["", "Der Stein summt leise. Er hat dir gesagt, was er weiß."]])
		return
	Audio.sfx("memory_flash")
	await main.cutscene("pakt")
	Game.set_flag("mem1")
	Game.days_left = 7
	Game.set_step("main", 1)
	Game.add_item("c_splitter")
	await say([
		[N, "Bauer Made. Mein Besitzer. Sein Hof liegt weit im Osten, hinter dem Dorf und der Steppe."],
		[N, "Noch sieben Tage bis zu meiner Schlachtzeit."],
		[N, "Ich muss überleben ... um zu sterben."],
		["", "Den Erinnerungssplitter kannst du im Menü als Talisman ausrüsten."],
	])
	map().refresh()
	UI.show_hud(true)

func ev_strand_noexit(_a) -> void:
	await think("Ins Inselinnere? Aber wohin überhaupt ... Ich weiß nicht mal, wer ich bin. Dieser leuchtende Stein bei den Felsen ...")
	var p = map().player
	p.teleport(p.global_position + Vector3(0, 0, 1.2))

func ev_plastik(_a) -> void:
	var n := Game.count("k_plastik")
	if Game.quest_state("kura") == "active":
		UI.toast("Plastikmüll: %d / 5" % n)
		if n >= 5:
			Game.set_step("kura", 1)
	elif n == 1:
		await think("Plastik. Überall Plastik. Wer wirft so etwas ins Paradies?")

func ev_kura(_a) -> void:
	var st := Game.quest_state("kura")
	if st == "":
		await say([
			["Opa Kura", "Ah. Ein Huhn. Lange nicht gesehen, dass eins freiwillig an den Strand kommt."],
			["Opa Kura", "Früher fingen die Fischer hier Fisch. Heute fangen ihre Netze Aluminiumdosen."],
			["Opa Kura", "Und ich? Ich fresse Plastiktüten, weil sie aussehen wie Quallen. Lecker. Und tödlich."],
		])
		var c := await ask("Opa Kura", "Sammelst du mir 5 Stück Plastikmüll vom Strand? Ich bin zu alt. Und zu Schildkröte.", ["Klar, Opa.", "Ich hab eine Schlachtung zu erwischen."])
		if c == 0:
			Game.start_quest("kura")
			if Game.count("k_plastik") >= 5:
				Game.set_step("kura", 1)
			await say([["Opa Kura", "Gutes Huhn. Ein bisschen Plastik liegt sogar in der versteckten Bucht im Osten. Man muss nur durchs Wasser waten."]])
		else:
			await say([["Opa Kura", "Ja, ja. Jeder hat etwas Wichtigeres zu tun. Darum sieht die Welt so aus."]])
		return
	if st == "active":
		if Game.count("k_plastik") >= 5:
			Game.remove_item("k_plastik", 5)
			await say([
				["Opa Kura", "Fünf Stück! Danke, Kind."],
				["Opa Kura", "Weißt du ... keine fünfzig Jahre ist es her, da blühte diese Insel in allen Farben. Mensch und Tier lebten im Einklang."],
				["Opa Kura", "Dann kamen die Touristen. Eine Pest, sagten die Alten. Sie suchten die Freiheit – und stahlen sie den anderen."],
				["Opa Kura", "Eine junge Hexe soll damals einen Zauber gewirkt haben ... ach, alte Geschichten. Hier, nimm das."],
			])
			Game.add_item("a_kokoshelm")
			Game.add_grains(60)
			Game.complete_quest("kura")
		else:
			await say([["Opa Kura", "Noch %d Stück. Ich warte. Ich bin gut im Warten. Hundertzwölf Jahre Übung." % (5 - Game.count("k_plastik"))]])
		return
	var idle := [
		"Der Strand atmet wieder ein bisschen. Danke.",
		"Wenn du je ins Meer springen willst, Kind: tu es nicht an der Klippe. Das Wasser dort ist ... traurig.",
		"Ich hab einen Hai gekannt. Netter Kerl. Jetzt wohnt er in einem Brunnen. Frag nicht.",
	]
	await say([["Opa Kura", idle[randi() % idle.size()]]])

func ev_kevin(_a) -> void:
	if Game.flag("kevin_talked"):
		var c0 := await ask("Kevin", "Duuude. Du schon wieder. Willst du auch einen Shake?", ["Nein danke.", "(Ihm ein Auge auspicken.)"])
		if c0 == 1:
			await _kevin_fight()
		return
	Game.set_flag("kevin_talked")
	await say([["Kevin", "Duuude. Ein Huhn. Ich hatte heute schon drei Magic-Mushroom-Shakes. Ich glaub, ich seh dich gar nicht wirklich."]])
	var c := await ask(N, "...", ["Ich bin echt.", "Was machst du hier?", "(Ihm ein Auge auspicken.)"])
	match c:
		0:
			await say([["Kevin", "Krass. Dann ... sorry für die Wings gestern, Bro. Die waren aber auch echt gut."]])
		1:
			await say([
				["Kevin", "Ich bin Kevin. Aus Castrop-Rauxel. Ich such hier mich selbst."],
				[N, "Und?"],
				["Kevin", "Bisher nur Sonnenbrand. Und einen Gecko im Dorf, der echt ALLES verkauft. Auch Sachen, die man nicht verkaufen sollte."],
			])
		2:
			await _kevin_fight()

func _kevin_fight() -> void:
	await say([["Kevin", "Whoa, whoa! Bad Trip! BAD TRIP!"]])
	var r := await fight(["tourist_m"], {"intro_line": "Ich wusste, die Shakes waren zu stark!"})
	if r == "win":
		Game.set_flag("kevin_dead")
		Game.add_item("f_shake")
		map().refresh()
		await think("Er hat sich selbst gefunden. Am Ende.")

func ev_barwoman(_a) -> void:
	await say([["Ibu Wayan", "Ayo, Huhn! Du siehst hungrig aus. Seit dem Sturm ist alles anders – die Pfade weg, die Touristen noch lauter."]])
	var c := await ask("Ibu Wayan", "Nasi Goreng? Ohne Huhn, versprochen. Hihi. 25 Körner.", ["Nasi Goreng kaufen (25)", "Was weißt du über die Insel?", "Nein danke."])
	match c:
		0:
			if Game.grains >= 25:
				Game.grains -= 25
				Game.add_item("f_nasigoreng")
				Audio.sfx("coin")
				await say([["Ibu Wayan", "Selamat makan! Iss langsam, du hast ja nur noch ... ach, egal."]])
			else:
				await say([["Ibu Wayan", "Keine Körner? Dann musst du sie dir verdienen. Die Touristen haben immer welche dabei."]])
		1:
			await say([
				["Ibu Wayan", "Im Zentrum liegt das Dorf. Drumherum die Hütten der Verbannten – Familien, die wegen Eifersucht und Missgunst rausgeworfen wurden."],
				["Ibu Wayan", "Und hinter dem Dorf die alte Steppe. Da soll ein Brunnen wieder Wasser führen. Und es heißt, da unten redet jemand."],
			])

# ======================================================================= KAPITEL 2: DORF
func ev_dorf_enter(_a) -> void:
	if Game.flag("dorf_intro"):
		return
	Game.set_flag("dorf_intro")
	Game.set_step("main", 2)
	Game.days_left = 6
	await UI.chapter("Kapitel 2", "Das Dorf der Verbannten")
	await UI.narrate([
		"Im Zentrum der Insel liegt ein Dorf, in dem sich ein paar hundert Menschen angesiedelt haben.",
		"Es heißt, Streit – angefeuert durch Eifersucht und Missgunst – habe Familien in die Verbannung getrieben.",
		"Ihre Hütten liegen fast kreisförmig um das Dorf herum.",
	], "book", 0.6)
	await think("Der Weg nach Osten führt durchs Dorf. Ich muss mich beeilen. Und ich darf mich nicht erwischen lassen. Oder ... sie dürfen mich nicht erwischen.")

func ev_mem_sturm(_a) -> void:
	if Game.flag("mem2"):
		await say([["", "Der Stein flackert. Die Erinnerung ist noch warm."]])
		return
	Game.set_flag("mem2")
	await UI.memory([
		"Seit nun etwa einem Monat bin ich versehentlich verloren gegangen.",
		"Normalerweise besitze ich kaum Orientierungsschwierigkeiten.",
		"Doch seitdem dieser Sturm alles niedergemäht hat, erkenne ich die üblichen Pfade nicht mehr.",
		"Ich habe einen Sinn, der erfüllt werden muss.",
		"Es wird überliefert, dass jene, die den Pakt nicht einhalten, etwas viel Schrecklicheres erwartet als die Hölle.",
	])
	Game.days_left = 5
	UI.show_hud(true)
	await think("Fünf Tage. Den Pakt einhalten, dann kommt das Paradies. So war es, so ist es, so wird es immer sein ... oder?")

func ev_arena(_a) -> void:
	if Game.flag("arena_done"):
		return
	await say([
		["Buchmacher Benny", "Letzte Wetten, Leute! Der große Goldene gegen ... ach, der kämpft ja nicht. Seit drei Wochen nicht!"],
		["Buchmacher Benny", "Würde keiner Mücke ein Haar krümmen, der Fettsack. Morgen landet er im Topf."],
		["Jimmy", "..."],
		[N, "(Ein Hahn wie ein Kleiderschrank. In einem Käfig. Und er schaut so ... sanft.)"],
	])
	var c := await ask(N, "...", ["Lass den Hahn frei!", "(Ihm direkt ins Auge picken.)"])
	if c == 0:
		await say([["Buchmacher Benny", "Hahaha! Ein Huhn mit Meinung! Ich wette zehn zu eins auf deinen Tod!"]])
	else:
		await say([["Buchmacher Benny", "AAH! Mein Auge! Das Huhn hat ... JUNGS!"]])
	var r := await fight(["bookie", "tourist_m"], {"boss": true, "intro_line": "Jeder hat seinen Preis, Huhn. Deiner ist: Suppe."})
	if r != "win":
		return
	Game.set_flag("arena_done")
	Game.set_step("main", 3)
	map().refresh()
	await say([
		["Jimmy", "Du ... hast sie umgebracht."],
		[N, "Sie hätten dich umgebracht."],
		["Jimmy", "Ich hätte nicht gekämpft."],
		[N, "Genau deshalb."],
		["Jimmy", "Ich hab Geschichten gehört. Von Hallen jenseits des Meeres. Käfige, Maschinen, Leichenhäuser."],
		["Jimmy", "Ich hab nie verstanden, wofür ich so groß bin. Vielleicht ... um etwas zu beschützen."],
	])
	var c2 := await ask("Jimmy", "Darf ich mitkommen? Ich bin gut im Tragen. Und im Im-Weg-Stehen.", ["Komm mit, Jimmy.", "Ich gehe lieber allein."])
	if c2 == 0:
		recruit("jimmy")
		await say([["Jimmy", "Ein Schild braucht jemanden, den es beschützt. Danke."]])
	else:
		Game.set_flag("jimmy_waiting")
		await say([["Jimmy", "Verstehe. Ich warte am Lagerfeuer am Dorfplatz. Falls du es dir anders überlegst."]])
	map().refresh()

func ev_jimmy_wait(_a) -> void:
	var c := await ask("Jimmy", "Na? Brauchst du doch einen Schrank mit Federn?", ["Komm mit.", "Noch nicht."])
	if c == 0:
		Game.set_flag("jimmy_waiting", false)
		recruit("jimmy")
		map().refresh()

func ev_dorf_east(_a) -> void:
	if Game.flag("arena_done"):
		return
	await say([["", "Bennys Leute haben den Weg nach Osten mit Hahnenkampf-Käfigen verbarrikadiert. Die Arena liegt im Norden des Dorfes."]])
	var p = map().player
	p.teleport(p.global_position + Vector3(-1.2, 0, 0))

func ev_toke(_a) -> void:
	if not Game.flag("toke_met"):
		Game.set_flag("toke_met")
		Audio.voice("gecko", null, 0.9)
		await say([
			["Toké", "Toké! Toké! ... Pardon. Berufskrankheit."],
			["Toké", "Ein Huhn mit Körnern? Willkommen auf meinem Schwarzmarkt. Alles zu verkaufen. Moral kostet extra."],
		])
	var prev_m := Audio.current_music()
	Audio.music_pick(["shop"], "shop", 0.5)
	Audio.sfx_any(["shop_open"])
	await main.open_shop()
	Audio.music(prev_m, 0.6)

func ev_berta(_a) -> void:
	var st := Game.quest_state("kalb")
	if st == "" and Game.count("k_kalb") > 0:
		Game.start_quest("kalb")
		st = "active"
	if st == "":
		await say([
			["Berta", "Muuh ... entschuldige. Ich bin nur ... müde. Sie lassen mich jeden Tag den Pflug ziehen. Ich wiege noch hundertvierzig Kilo."],
			["Berta", "Und mein Klößchen ... mein Kalb ... sie haben es mitgenommen. In die Steppe, zum alten Gatter. Zum Mästen."],
		])
		var c := await ask("Berta", "Kannst du nach ihr sehen, kleines Huhn?", ["Ich finde Klößchen.", "Ich hab selbst genug Probleme."])
		if c == 0:
			Game.start_quest("kalb")
			await say([["Berta", "Sie trägt eine kleine Glocke. Bring sie mir, dann weiß ich, dass sie lebt."]])
		else:
			await say([["Berta", "Natürlich. Wer hilft schon einer Kuh."]])
		return
	if st == "active" and Game.count("k_kalb") > 0:
		Game.remove_item("k_kalb")
		await say([
			["Berta", "Die Glocke! Und ... ich hör sie! Klößchen läuft hinter dir her!"],
			["Klößchen", "Mama!"],
			["Berta", "Ich habe nichts zu geben außer ... nimm meinen Segen. Er macht dich klüger. Kühe wissen mehr, als man denkt."],
			["", "Bertas Segen: +1 Skillpunkt für alle!"],
		])
		Game.bonus_points += 1
		Game.complete_quest("kalb")
		Game.set_flag("kalb_home")
		map().refresh()
		return
	if st == "active":
		await say([["Berta", "Das alte Gatter liegt in der Steppe, östlich vom Dorf. Bitte beeil dich."]])
		return
	await say([["Berta", "Klößchen schläft. Zum ersten Mal ohne Angst. Muuh."]])

func ev_kalb(_a) -> void:
	Game.add_item("k_kalb")
	Game.set_step("kalb", 1)
	Game.set_flag("kalb_free")
	await say([
		["Klößchen", "Bist du ... ein Huhn? Mama sagt, Hühner sind dumm."],
		[N, "Deine Mama hat mich geschickt. Lauf nach Hause, ins Dorf. Ich nehm deine Glocke mit."],
		["Klößchen", "Danke, dummes Huhn!"],
	])
	map().refresh()

func ev_morchel(_a) -> void:
	var st := Game.quest_state("pilz")
	if st == "":
		await say([
			["Herr Morchel", "Psst! Huhn! Hier unten! Nein, nicht drauftreten!"],
			["Herr Morchel", "Die Menschen haben meine Freunde gepflückt. Für ihre Magic-Mushroom-Shakes! Barbaren!"],
		])
		var c := await ask("Herr Morchel", "Drei sind noch irgendwo im Dorf versteckt. Rettest du sie?", ["Ich rette deine Freunde.", "Sind Pilze nicht ... Essen?"])
		if c == 1:
			await say([["Herr Morchel", "Sind Hühner nicht ... Essen? Eben."]])
		Game.start_quest("pilz")
		return
	if st == "active" and Game.count("k_pilz") >= 3:
		Game.remove_item("k_pilz", 3)
		await say([
			["Herr Morchel", "Ihr lebt! Hans! Fritz! Ingeborg!"],
			["Herr Morchel", "Moment ... wo ist Günther?"],
			[N, "..."],
			["Herr Morchel", "Günther war schon im Shake, oder? ... Er hätte es so gewollt. Nein. Hätte er nicht."],
			["Herr Morchel", "Nimm meine Sporen. Bitte nicht inhalieren."],
		])
		Game.add_item("c_pilzsporen")
		Game.complete_quest("pilz")
		return
	if st == "active":
		await say([["Herr Morchel", "Noch %d Freunde. In Häusern, Körben, Mixern ... die Menschen verstecken Pilze überall." % (3 - Game.count("k_pilz"))]])
		return
	await say([["Herr Morchel", "Wir trauern um Günther. Mit Würde. Und Myzel."]])

func ev_pilz(_a) -> void:
	var n := Game.count("k_pilz")
	if Game.quest_state("pilz") == "active":
		UI.toast("Pilzfreunde: %d / 3" % n)
		if n >= 3:
			Game.set_step("pilz", 1)
	var pl := ["Danke! Danke! Ich war schon im Mixer!", "Ist es vorbei? Riecht es noch nach Smoothie?", "Ich hab Dinge gesehen, Huhn. Bunte Dinge."]
	await say([["Pilzfreund", pl[clampi(n - 1, 0, 2)], "mushroom"]])

func ev_lieselotte(_a) -> void:
	var st := Game.quest_state("punkte")
	if st == "":
		await say([
			["Lieselotte", "Ach, ach, ach! Der Sturm hat mir meine Punkte weggeweht! Drei Stück!"],
			["Lieselotte", "Ein Marienkäfer ohne Punkte ist nur ein ... roter Käfer. Wie peinlich."],
		])
		Game.start_quest("punkte")
		return
	if st == "active" and Game.count("k_punkt") >= 3:
		Game.remove_item("k_punkt", 3)
		await say([
			["Lieselotte", "Eins, zwei, drei ... und mit den alten sieben! SIEBEN? Ich hatte doch nur sechs!"],
			["Lieselotte", "Behalt den siebten. Er bringt Glück. Mir hat er's offensichtlich nicht."],
		])
		Game.add_item("c_punkte")
		Game.complete_quest("punkte")
		return
	if st == "active":
		await say([["Lieselotte", "Noch %d Punkte! Sie glitzern ein bisschen, wenn man genau hinsieht." % (3 - Game.count("k_punkt"))]])
		return
	await say([["Lieselotte", "Ich fühle mich wieder vollständig. Fast zu vollständig."]])

func ev_punkt(_a) -> void:
	var n := Game.count("k_punkt")
	if Game.quest_state("punkte") == "active":
		UI.toast("Marienkäfer-Punkte: %d / 3" % n)
		if n >= 3:
			Game.set_step("punkte", 1)

func ev_nugget(_a) -> void:
	if Game.flag("nugget_met"):
		var c0 := await ask("Nugget", "Der Fußring sagt, du bist zurück. Nimmst du mich jetzt mit?", ["Komm mit.", "Noch nicht."])
		if c0 == 0:
			recruit("nugget")
			map().refresh()
		return
	Game.set_flag("nugget_met")
	await say([
		["Nugget", "NICHT ANFASSEN! Ich bin nicht hier! Ich bin ein Sack Reis!"],
		[N, "Du bist ein Huhn."],
		["Nugget", "... Der Fußring sagt, du bist okay. Der Fußring irrt sich nie. Außer einmal. Da war es ein Fuchs."],
		["Nugget", "Ich bin aus dem Laster gesprungen. Der fuhr zum Hafen. Zu den Hallen aufs Festland."],
		["Nugget", "Weißt du, wie die Hallen sind? Ich schon. Dunkel. Eng. Ein Fenster, so klein wie ein Ei."],
		["Nugget", "Und Licht. Immer Licht. Damit wir mehr legen."],
	])
	var c := await ask("Nugget", "Wo gehst du hin? Ich kann sehr leise töten. Glaub ich. Hab's noch nie probiert.", ["Komm mit, Nugget.", "Bleib versteckt."])
	if c == 0:
		recruit("nugget")
	else:
		await say([["Nugget", "Okay. Ich bin ein Sack Reis. Ein sehr geduldiger Sack Reis."]])
	map().refresh()

func ev_witch_door(_a) -> void:
	await say([["", "Die Tür ist verschlossen. Es riecht nach Räucherstäbchen und ... Zukunft?"]])

func ev_villager(_a) -> void:
	var lines := [
		["Dorfbewohner", "Ein Huhn? Allein? Das gehört bestimmt dem alten Made. Der sucht schon seit Wochen eins."],
		["Dorfbewohnerin", "Seit dem Sturm sind die Touristen noch schlimmer. Die suchen jetzt 'authentische Erfahrungen'."],
	]
	await say([lines[randi() % lines.size()]])

# ======================================================================= KAPITEL 3: STEPPE
func ev_steppe_enter(_a) -> void:
	if Game.flag("steppe_rain"):
		map().atmos.add_weather("rain")
	if Game.flag("steppe_intro"):
		return
	Game.set_flag("steppe_intro")
	Game.days_left = 4
	await UI.chapter("Kapitel 3", "Die verlassene Steppe")
	await UI.narrate([
		"Auf der Suche nach einem Weg heimwärts landete ich inmitten einer verlassenen Steppe.",
		"Lediglich in sich zusammenbrechende Holzhütten zieren die Landschaft.",
		"Überall, wo der Mensch hingelangt, überdauern sichtbare Spuren.",
		"Die Sonne, deren Strahlung mir unnatürlich heiß vorkommt, erschwert mir jeden einzelnen Schritt.",
	], "book", 0.6)
	UI.show_hud(true)

func ev_wanderer(_a) -> void:
	if Game.flag("wanderer_met"):
		await say([["Der Wanderer", "*hust* Geh weiter, Kind. Ich hab meinen Weg."]])
		return
	Game.set_flag("wanderer_met")
	await say([
		["Der Wanderer", "*hust* *hust* ... Keine Angst. Ich bin nur krank. Nicht ansteckend. Nur ... übrig."],
		["Der Wanderer", "Ich komme von weit her. Vom Festland. Willst du hören, wie es dort ist?"],
	])
	var c := await ask(N, "...", ["Erzähl.", "Lieber nicht."])
	if c == 0:
		await say([
			["Der Wanderer", "Riesige, finstere Hallen. Verschmutzte Käfige. Automatisierte Mordmaschinen."],
			["Der Wanderer", "Gefüllte Leichenhäuser. Küken, die schon am ersten Tag sortiert werden. Die Männchen ... in den Häcksler."],
			[N, "..."],
			["Der Wanderer", "Plötzlich kommt dir dein eigenes Elend recht harmlos vor, oder?"],
		])
	await say([
		["Der Wanderer", "Wegen meiner Krankheit verwehrt mir mein Herrscher die Schlachtung. Nicht mal das darf ich."],
		["Der Wanderer", "Aber auch für uns Verlassene gibt es einen Ausweg. Die Klippe der Aussichtslosen."],
		["Der Wanderer", "Für die, die zur Schlachtzeit nicht bei ihrem Besitzer sind. Ein Sprung. Und danach wird alles besser."],
		["Der Wanderer", "Wir sehen uns ... vielleicht. Am Ende."],
	])
	map().refresh()

func ev_vian(_a) -> void:
	if Game.flag("vian_met"):
		var c0 := await ask("Vian", "Das linke Auge sagt, du brauchst mich. Das rechte sagt nichts mehr.", ["Komm mit, Vian.", "Später."])
		if c0 == 0:
			recruit("vian")
			map().refresh()
		return
	Game.set_flag("vian_met")
	await say([
		["Vian", "Es wird regnen. Ich schmecke es. Salzig. Mit einer Note von ... Verzweiflung. Deiner, Kind."],
		[N, "Wer bist du?"],
		["Vian", "Vian. Meine Schlachtzeit ist seit drei Jahren vorbei. Ich hab den Geschichten nie geglaubt. Also bin ich einfach ... geblieben."],
		[N, "Nach der Schlachtzeit? Aber der Pakt! Das Paradies!"],
		["Vian", "Ich habe gesehen, wie du kommst. Mit dem linken Auge. Das rechte hat drei Füchse gesehen."],
		["Vian", "Beides stimmt übrigens. Duck dich."],
	])
	var r := await fight(["fox", "fox", "fox"], {"intro_line": "*schnüffel* Zwei Hühner. Eins davon schon vorgegart."})
	if r != "win":
		return
	Game.set_flag("steppe_rain")
	map().atmos.add_weather("rain")
	await say([
		["Vian", "Siehst du? Regen. Ich hab's dir gesagt."],
		["Vian", "Als ich merkte, dass die Schlachtzeit nicht das Ende ist, fehlte mir der Mut, etwas zu ändern."],
		["Vian", "Vielleicht ist es nie zu spät, sich dem Widerstand anzuschließen."],
		[N, "Welchem Widerstand?"],
		["Vian", "Dem, den du noch nicht kennst."],
	])
	var c := await ask("Vian", "Nimmst du eine alte, halbblinde Henne mit?", ["Komm mit, Vian.", "Du solltest dich ausruhen."])
	if c == 0:
		recruit("vian")
	else:
		await say([["Vian", "Ich warte. Ich schmecke, dass du zurückkommst."]])
	map().refresh()

func ev_paprika(_a) -> void:
	if Game.flag("paprika_met"):
		var c0 := await ask("Madame Paprika", "Ah, mein Publikum kehrt zurück! Eine Zugabe?", ["Komm mit, Madame.", "Später."])
		if c0 == 0:
			recruit("paprika")
			map().refresh()
		return
	Game.set_flag("paprika_met")
	await say([
		["Madame Paprika", "Meine Damen und Herren! Und nun – der große Feuerball!"],
		["Madame Paprika", "... Ah. Ein Publikum. Endlich. Der Sturm ist ein undankbares Publikum, er klatscht nur mit Blitzen."],
		["Madame Paprika", "In einem früheren Leben war ich Zauberer. In Wien. Ich hatte einen Schnurrbart und Schulden."],
	])
	var c := await ask("Madame Paprika", "Glaubst du an Magie, kleines Huhn?", ["Ja.", "Nein.", "Ich glaube an Schlachtzeiten."])
	var resp := ["Wundervoll! Ein Gläubiges!", "Ausgezeichnet! Skeptiker brennen am schönsten.", "Wie deprimierend. Dann brauchst du mich umso mehr."]
	await say([["Madame Paprika", resp[c]]])
	var c2 := await ask("Madame Paprika", "Jede Reise braucht Pyrotechnik. Nimmst du mich mit?", ["Komm mit, Madame.", "Nein danke."])
	if c2 == 0:
		recruit("paprika")
	else:
		await say([["Madame Paprika", "Ich bleibe. Die Klippe hat eine fabelhafte Akustik."]])
	map().refresh()

func ev_brunnen(_a) -> void:
	if Game.flag("hai_done"):
		var l := ["Geh weg. Ich bin tot. Ich hab zu tun.", "Noch eine Leiche und ich tick' aus. Das gilt auch für Besuch.", "Augen zu. Fühlen. Was hab ich gesagt?"]
		await say([["Toter Hai", l[randi() % l.size()]]])
		return
	await say([
		["", "Ein uralter, mit Moos bekleideter Brunnen. Pflanzen ranken aus der Öffnung. Unten glitzert Wasser."],
		[N, "Es wäre so einfach. Ein Schritt ..."],
		["???", "Du solltest nicht springen. Zumindest nicht jetzt. Und schon gar nicht an diesem Ort."],
	])
	var c := await ask(N, "...", ["Aber meine Zeit ... sie neigt sich dem Ende zu.", "Wer spricht da?"])
	if c == 0:
		await say([[N, "Mir bleiben nur noch wenige Tage, und das Leben war schrecklich. So schlimm kann keine Hölle sein! Was hält mich noch hier oben?"]])
	await say([
		["", "Unten im Wasser treibt ein kleiner weißer Hai. Auf dem Rücken."],
		["Toter Hai", "Du bist hier nicht willkommen. Noch eine weitere Leiche und ich tick' aus!"],
		[N, "Eine Leiche? Aber ich sehe niemanden außer dir."],
		["Toter Hai", "Ach du dummes Huhn! Siehst du nicht, dass ich es bin, der von den Toten zu dir spricht?"],
		["Toter Hai", "Trachte nicht dem Tode hinterher. Viel mehr im Leben sollst auch du den Funken Freiheit sehen."],
		["Toter Hai", "Deine Zeit ist nicht vorherbestimmt. Gewiss hat sie ein Ende – jedoch wissen, wann es kommt, das wirst du nicht."],
		["Toter Hai", "Ist deine Sicht betrübt, scheint etwas aussichtslos ... mach deine Augen zu und fühl's!"],
		["Toter Hai", "Und jetzt nimm den Zahn und verschwinde. Ich hab einen Brunnen zu verwesen."],
	])
	Game.add_item("c_haizahn")
	Game.set_flag("hai_done")
	Game.complete_quest("hai")

func ev_wolf(_a) -> void:
	if Game.flag("wolf_dead"):
		return
	await say([
		["Der Wolf", "*knirsch* *knirsch* ... Ein Huhn. Auf MEINEM Grundstück."],
		["Der Wolf", "Hier entsteht: Gili Genting Luxury Resort & Spa. Infinity-Pool. Bio-Hühnchen-Buffet."],
		[N, "Das hier ist eine Steppe. Hier wohnt niemand mehr."],
		["Der Wolf", "Eben! Perfekt! Erst der Dschungel, dann der Acker, dann der Pool. So funktioniert Fortschritt, Kleines."],
		["Der Wolf", "Die meisten bleiben ja regungslos. Aus Angst vor Leuten wie mir. *knirsch*"],
	])
	var r := await fight(["wolf", "guard"], {"boss": true, "intro_line": "Ich zahle Leute dafür, Hühner wie dich zu entsorgen!"})
	if r != "win":
		return
	Game.set_flag("wolf_dead")
	map().refresh()
	await think("Er hatte einen Bauplan. Jetzt hat er keinen Puls mehr.")
	await say([["", "Der Weg nach Osten ist frei. Die Sonne sinkt. Es wird Nacht über der Steppe."]])

func ev_steppe_east(_a) -> void:
	if not Game.flag("wolf_dead"):
		await say([["", "Pflöcke, Absperrband und Wachleute. 'BAUSTELLE – BETRETEN VERBOTEN'. Irgendwer plant hier etwas."]])
		var p = map().player
		p.teleport(p.global_position + Vector3(-1.2, 0, 0))
		return
	await _camp_night()

func _camp_night() -> void:
	await UI.fade_out(1.0)
	Audio.music("ending", 1.0)
	var companions := Game.active_party().filter(func(x): return x != "ania")
	var lines := ["In einer wolkenlosen Nacht liegen die Gefährten aneinandergekuschelt am Rand der Steppe."]
	if companions.is_empty():
		lines = ["In einer wolkenlosen Nacht liegt unser Chicken allein am Rand der Steppe. Die Einsamkeit ist kein angenehmer Begleiter."]
	lines += [
		"Unser Chicken jedoch ist hellwach. Fragen rund um die Wahrscheinlichkeit rauben ihr den Schlaf.",
		"Als ein Meteor ihre Aufmerksamkeit auf sich zieht, bemerkt sie, dass die Sterne anders erscheinen als sonst.",
		"Sie blinzelt ein letztes Mal ...",
	]
	await UI.narrate(lines, "book", 1.0)
	main.goto_map("void", "start", false)

# ======================================================================= VOID
func ev_void_enter(_a) -> void:
	if Game.flag("void_seen"):
		return
	await think("... und erwacht in einem weißen, mit Leere gefüllten Raum.")
	map().add_blood(map().player.global_position + Vector3(0.2, 0, 0.1))
	await think("Ist das ... Blut? Aus meiner Nase?")

func ev_heuschrecke(_a) -> void:
	if Game.flag("void_seen"):
		return
	await say([
		["Heuschrecke", "Was fällt dir ein, mein Konzert zu stören! Und darüber hinaus blutest du mir alles voll. Ekelhaft!"],
		[N, "Wer ... wo?"],
		["Heuschrecke", "Du dummes Huhn, hier unten! Unter deinen Füßen!"],
		["", "Unter dir liegt eine Heuschrecke, die allem Anschein nach von unzähligen Ameisen verspeist wird."],
		[N, "Oh verdammt, das tut mir leid! Ich hab dich nicht gesehen. Und ehrlich gesagt, gehört auch nicht."],
		["Heuschrecke", "Du bist nicht ehrlich, Kind. Du bist blind. Und taub ... das bist du auch."],
		["Heuschrecke", "Mach die Augen zu, sei still! Dann hörst auch du das wundervolle Lied, das ich zu meinem Tode sing'."],
	])
	await main.cutscene("void_song", false)
	Game.set_flag("void_seen")
	await UI.fade_out(1.2, Color(1, 1, 1))
	var companions := Game.active_party().filter(func(x): return x != "ania")
	var lines := []
	if companions.is_empty():
		lines.append("Als sie erwacht, ist es still. Niemand hat sie gewärmt. Sie hat drei Nächte durchgeschlafen.")
	else:
		lines.append("Während ihrer Abwesenheit versorgten sie ihre Gefährten mit Wasser und hielten sie warm.")
		lines.append("Das erste Mal in ihrem Leben hat sich jemand – fern von egoistischen Gründen – um sie gesorgt.")
		lines.append("Rückblickend fühlte es sich an wie ein kleines Nickerchen. Doch sie hatte drei Nächte durchgeschlafen.")
	lines.append("Drei Nächte. Die Schlachtzeit ist heute.")
	await UI.narrate(lines, "book", 1.0)
	Game.days_left = 0
	Game.set_step("main", 4)
	main.goto_map("klippe", "start", false)

# ======================================================================= KAPITEL 4: KLIPPE
func ev_klippe_enter(_a) -> void:
	if Game.flag("klippe_intro"):
		return
	Game.set_flag("klippe_intro")
	Game.full_heal()
	await UI.chapter("Kapitel 4", "Die Klippe der Aussichtslosen")
	await UI.narrate([
		"Der Hof von Bauer Made ist zu weit. Kein Huhn der Insel schafft das bis heute Nacht.",
		"Die Hoffnung auf einen würdevollen Tod bringt sie an die Klippe der Aussichtslosen.",
		"Je näher sie ihrem Ende kommt, desto entspannter wird ihr Gemüt.",
	], "book", 0.6)
	for id in Game.active_party():
		if id == "jimmy":
			await say([["Jimmy", "Ich lass dich nicht allein da hoch."]])
		elif id == "vian":
			await say([["Vian", "Ich schmecke Salz. Und eine Entscheidung."]])
		elif id == "nugget":
			await say([["Nugget", "Der Fußring sagt, wir sollten umdrehen. Ich hör nicht mehr auf den Fußring."]])
		elif id == "paprika":
			await say([["Madame Paprika", "Ein Sturm! Was für eine Bühne!"]])
	UI.show_hud(true)

func ev_klippe_edge(_a) -> void:
	if Game.flag("revolution"):
		return
	await main.cutscene("klippe")
	while true:
		var c := await ask(N, "Wie warm sich das Ertrinken wohl anfühlen muss?", ["Springen.", "Die Augen schließen. Und fühlen."])
		if c == 0:
			await UI.fade_out(0.4)
			Audio.sfx("whoosh")
			await UI.narrate(["Schwerelos ...", "Endlich die Last des Lebens von den Federn werfen ..."], "book", 1.0)
			Audio.sfx("thunder")
			UI.flash(Color(1, 1, 1), 0.6, 1.0)
			if Game.flag("hai_done"):
				await say([["Toter Hai", "ICH HAB GESAGT: NICHT SPRINGEN! Noch eine Leiche und ich tick' aus! Zurück mit dir!"]])
			else:
				await say([["Eine Stimme aus dem Meer", "Nein, nein, nein. Nicht hier. Nicht so. Zurück mit dir, dummes Huhn!"]])
			await UI.fade_in(0.4)
			continue
		break
	await main.cutscene("revolution")
	map().atmos.sun.light_color = Color(1.0, 0.3, 0.25)
	await UI.chapter("", "Der Zeiger schlägt auf Revolution.")
	Game.set_flag("revolution")
	Game.bonus_points += 2
	Game.set_step("main", 5)
	Game.full_heal()
	UI.toast("Neuer Skill: \"Der Zeiger schlägt\"  ·  +2 Skillpunkte")
	UI.show_hud(true)
	for id in Game.active_party():
		match id:
			"jimmy": await say([["Jimmy", "Für die Hallen. Für die Küken. Dann kämpfe ich."]])
			"vian": await say([["Vian", "Ich hab es geschmeckt. Es schmeckt nach Eisen."]])
			"nugget": await say([["Nugget", "Der Fußring sagt: endlich."]])
			"paprika": await say([["Madame Paprika", "Endlich ein Finale, das meiner würdig ist!"]])
	if Game.active_party().size() == 1:
		await think("Allein. Aber nicht mehr verloren.")
	await main.cutscene("plan", false)
	main.goto_map("hof", "start")

# ======================================================================= KAPITEL 5: HOF
func ev_hof_enter(_a) -> void:
	if Game.flag("power_off"):
		map().power_off()
		for e in map().enemies:
			e.ent["sleeping"] = true
			e.init_enemy()
	if Game.flag("hof_intro"):
		return
	Game.set_flag("hof_intro")
	await UI.chapter("Kapitel 5", "Vollmond über dem Hof")
	await say([
		[N, "Der Hof von Bauer Made. Hier bin ich geschlüpft. Hier sollte ich sterben."],
		[N, "Der Stromkasten steht beim Schlachthaus. Erst das Licht. Dann der Schlachter."],
	])
	Game.set_step("main", 6)
	UI.show_hud(true)

func ev_strom(_a) -> void:
	if Game.flag("power_off"):
		await say([["", "Der Stromkasten raucht. Die Insel ist dunkel."]])
		return
	var c := await ask("", "Ein grauer Stromkasten. Kabel führen zu jedem Haus der Insel. Es summt.", ["Reinpicken.", "Noch nicht."])
	if c != 0:
		return
	Audio.sfx("peck")
	await get_tree().create_timer(0.3).timeout
	Audio.sfx("power_down")
	UI.flash(Color(0.6, 0.8, 1.0), 0.3, 0.8)
	Game.set_flag("power_off")
	map().power_off()
	Audio.music_pick(["farm_2", "farm"], "map_hof", 1.5)
	for e in map().enemies:
		e.ent["sleeping"] = true
		e.init_enemy()
	map().refresh()
	await say([
		["", "Mit einem letzten Summen erlischt jedes Licht auf Gili Genting."],
		[N, "Diejenigen, die rechtzeitig aufwachen, werden versuchen, das Licht einzuschalten."],
		[N, "Doch das haben wir euch bereits genommen."],
		["", "Aus der Dunkelheit leuchten hunderte rote Augen. Die Hühner der Insel sind gekommen."],
		["", "Tipp: Schlafende Gegner kannst du anschleichen (nicht rennen!) und überraschen."],
	])

func ev_army(_a) -> void:
	var l := ["Ein Hahn genügt.", "Die Fenster sind offen. Wir sind drin.", "Für die Küken!", "Bwok. Bwok. BWOK.", "Wir haben gebetet. Jetzt picken wir."]
	await say([["Huhn der Revolution", l[randi() % l.size()]]])

func ev_schlachthaus_door(_a) -> void:
	pass

func ev_finale(_a) -> void:
	if Game.flag("bauer_dead"):
		return
	Audio.music("", 0.5)
	await say([
		["Bauer Made", "Ania. Da bist du ja. Drei Tage zu spät."],
		[N, "Mein Name ist %s." % N if N != "Ania" else "Ich weiß."],
		["Bauer Made", "Ich hab dich großgezogen. Gefüttert. Den Pakt mit dir geschlossen, als du aus dem Ei kamst."],
		["Bauer Made", "Und du kommst mit einem Messer und einem Haufen Federvieh in mein Schlachthaus?"],
		[N, "Ihr habt den Pakt zuerst gebrochen. Mit jedem Küken. Mit jeder Halle. Mit jedem Wing."],
		["Der Schlachter", "Made, red nicht mit dem Essen."],
		["Der Schlachter", "Ich mach das seit dreißig Jahren. Ihr wehrt euch nie."],
	])
	var r := await fight(["bauer", "farmhand", "farmhand"], {"boss": true, "intro_line": "Der Pakt, Huhn! DER PAKT!"})
	if r != "win":
		return
	Game.set_flag("bauer_dead")
	map().refresh()
	await say([
		["Der Schlachter", "Hm. Der Made war immer weich."],
		["Der Schlachter", "Weißt du, was das Schöne an meinem Beruf ist, Hühnchen? Es gibt immer Nachschub."],
		[N, "Nicht mehr."],
	])
	Game.full_heal()
	UI.toast("Deine Hühner heilen dich. Alle HP & MP wiederhergestellt.")
	r = await fight(["butcher"], {"boss": true, "intro_line": "Hab dich erwartet, Hühnchen. Deine Schlachtzeit war vor drei Tagen."})
	if r != "win":
		return
	Game.set_flag("butcher_dead")
	Game.set_step("main", 7)
	await _epilogue_start()

# ======================================================================= EPILOG
func _epilogue_start() -> void:
	await UI.fade_out(1.0)
	Audio.music("cliff", 1.5)
	await UI.narrate([
		"Die glorreiche Schlacht ist beendet. Und wie erwartet, war sie ein riesiger Erfolg für die Chicken.",
		"Das Schreien der Menschen hallte bis ins Morgengrauen. Eine Melodie der Freiheit.",
		"Die tapferen Gefallenen wurden im letzten Waldabschnitt der Insel begraben.",
		"Und doch ... obwohl sie nun das glücklichste Chicken der Welt sein sollte, lässt sie eine Begegnung nachts nicht schlafen.",
		"Eine alte Dame. Im Haus am Dorfrand. Sie hatte gelächelt, als das Feuer kam.",
	], "book", 1.0)
	main.goto_map("hexenhaus", "start", false)

func ev_epilog_enter(_a) -> void:
	if Game.flag("epilog_intro"):
		return
	Game.set_flag("epilog_intro")
	await UI.chapter("Epilog", "Sonnenfinsternis")
	await say([[N, "Ihr Haus. Irgendwo hier muss eine Antwort sein. Irgendwas, damit ich wieder schlafen kann."]])

func ev_witch(_a) -> void:
	if Game.flag("witch_gone"):
		return
	await say([
		["Alte Dame", "Ach Kind. Da bist du ja endlich."],
		["Alte Dame", "Mit meinem lang ersehnten Tod startet ein neues Leben nun für dich."],
		["Alte Dame", "Ich hoff', dass du bei nächster Sonnenfinsternis dein ganzes Leid endlich vergisst."],
	])
	Game.set_flag("witch_gone")
	var w = _a
	if w and w.sprite:
		var tw = w.create_tween()
		tw.tween_method(func(v): w.sprite.set_alpha(v), 1.0, 0.0, 2.0)
		Audio.sfx("magic_dark")
		map().atmos.add_weather("ash")
		await tw.finished
		w.visible = false
		w.interactable = false
	await think("Sie ist ... zu Asche zerfallen. Einfach davongeflogen.")

func ev_buch(_a) -> void:
	if not Game.flag("witch_gone"):
		await say([["", "Ein altes, abgenutztes Buch. Die alte Dame beobachtet dich still."]])
		return
	if Game.flag("book_read"):
		return
	Game.set_flag("book_read")
	Game.add_item("k_buch", 1, false)
	await UI.narrate([
		"Keine 50 Jahre ist es her, dass die Insel Gili Genting in den unterschiedlichsten Farben blühte.",
		"Die Menschen der Insel waren ein Teil von ihr, tief verbunden mit allen Bewohnern.",
		"Dann lockte der Wunsch nach Freiheit eine Horde von Touristen an. Eine Pest, so beschrieben es die Einheimischen.",
		"Die einen suchen das Freisein und stehlen es den anderen. Ein typisch menschliches Syndrom.",
		"Noch bevor das Land endgültig unterging, kreierte eine damals junge Hexe einen Zauber ...",
		"... der jeden Touristen in ein Chicken verwandelte.",
	], "book", 0.92)
	await think("Jeden ... Touristen ...?")

func ev_spiegel(_a) -> void:
	if not Game.flag("book_read"):
		await say([["", "Ein gesprungener Spiegel. Du siehst ein Huhn. Natürlich siehst du ein Huhn."]])
		return
	Audio.sfx("memory_flash")
	await main.cutscene("mirror")
	await UI.narrate([
		"\"Hör auf zu weinen, Kind. Gewiss verspürst du Schmerz, so unerträglich ...\"",
		"\"Dennoch trägst nun du die Last, die ein jeder Mensch tagein, tagaus zu tragen hat.\"",
		"\"%s war der Name, den du dir als Huhn gegeben hast.\"" % N,
		"\"Hannah ist dein Name. Und ich bin Teil von dir.\"",
		"\"Ich bin die Lust, die Eifersucht, bin auch die Gier. Wohl bin ich alles, was der Mensch heut' ist.\"",
		"\"Ich zeige dir den Weg zum Glück. Du musst vergessen, welch' Leid die anderen bedrückt.\"",
	], "void", 1.0)
	await _ending()

func _ending() -> void:
	await UI.fade_out(1.0)
	Audio.music("ending", 1.5)
	var jimmy_line := "Draußen findet sie Jimmy. Ein robuster, breitgebauter junger Mann. Er hat die ganze Nacht nach ihr gesucht."
	if not ("jimmy" in Game.recruited):
		jimmy_line = "Draußen findet sie einen robusten, breitgebauten jungen Mann. Er sagt, er sei einmal ein Hahn gewesen. In einer Arena."
	var vian_line := "Schweren Herzens erzählt er ihr, dass Vian, die alte weise Henne, doch noch ihren Weg zur Klippe der Aussichtslosen fand."
	if not ("vian" in Game.recruited):
		vian_line = "Er erzählt von einer alten, halbblinden Henne, die er nie kennenlernen durfte. Sie soll zur Klippe gegangen sein."
	await UI.narrate([
		jimmy_line,
		vian_line,
		"Hannah verzieht keine Miene.",
		"Acht Jahre später.",
		"Jimmy kämpft weiter. Als Mensch versucht er, seinesgleichen zu überzeugen, dass Freiheit nicht auf dem Leid anderer basieren darf.",
		"Seine Anhänger werden mehr. In den Augen einiger machthabender Wölfe wird er zur Bedrohung. Das Knirschen ihrer Zähne wird lauter.",
		"Fünf weitere Jahre. Von Jimmy fehlt jede Spur.",
		"Hannah hat ihre Ideale aufgegeben. Sie führt ein sorgloses Leben in einem kleinen Dorf, umgeben von schönster Natur.",
	], "book", 1.0)
	await main.cutscene("ending", false)
	await UI.narrate(["Mach deine Augen zu.", "Und fühl's."], "void", 1.0)
	await _credits()
	main.show_title()

func _credits() -> void:
	var pt := int(Game.playtime)
	await UI.narrate([
		"GILI GENTING\nThe Island of Chicken",
		"Nach der Geschichte \"Gili Genting\" – The Island · The Revolution · The Epiphany of Chicken",
		"Menschen geschlachtet: %d\nSpielzeit: %d:%02d\nBegleiter: %d" % [Game.kills, pt / 3600, (pt / 60) % 60, Game.recruited.size()],
		"Kein Huhn wurde bei der Entwicklung dieses Spiels verletzt.\nViele Touristen schon.",
		"Danke fürs Spielen.",
	], "book", 1.0)

func ev_sandcastle(_a) -> void:
	if Game.flag("sandcastle"):
		await say([["", "Die Ruine einer Sandburg. Du hast sie zerstört. Ein Kind wird weinen. Gut."]])
		return
	var c := await ask("", "Eine Sandburg. Ein Kind hat stundenlang daran gebaut. Mit Liebe. Mit Hingabe.", ["Zertreten.", "In Ruhe lassen."])
	if c == 0:
		Game.set_flag("sandcastle")
		Audio.sfx("blood_splat")
		await say([[N, "Für jedes Ei, das ihr gefrühstückt habt."], ["", "Unter dem Turm lag ein vergrabener Beutel Körner."]])
		Game.add_grains(35)
	else:
		await think("Noch nicht. Erst die Erwachsenen.")

func ev_shrine(_a) -> void:
	var l := [
		"Ein kleiner Schrein. Opfergaben: Blumen, Reis, ein Keks. Niemand opfert Hühnern etwas.",
		"Du pickst den Reis aus der Opferschale. Die Götter schweigen. Wahrscheinlich sind sie auch nur Hühner.",
	]
	await say([["", l[randi() % l.size()]]])
	if not Game.flag("shrine_rice"):
		Game.set_flag("shrine_rice")
		Game.add_item("f_koerner", 2)

# ======================================================================= PUZZLES & SECRETS
## Switch puzzles: every switch entity has "puzzle", "key", and the puzzle's "order".
func _pz_progress(pz: String) -> Array:
	return Game.flags.get("pz_" + pz, [])

func switch_visual(a) -> void:
	if not is_instance_valid(a):
		return
	var e: Dictionary = a.ent
	var lit: bool = Game.flag(e["puzzle"] + "_open") or (e["key"] in _pz_progress(e["puzzle"]))
	var gl: OmniLight3D = a.get_node("Glow")
	var sym: Label3D = a.get_node("Sym")
	gl.light_energy = 2.2 if lit else 0.0
	var col := Color(e.get("color", "60e0ff"))
	sym.modulate = Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 1.0) if lit else Color(0.55, 0.55, 0.6, 1.0)
	a.sprite.set_emission(0.45 if lit else 0.0)

func ev_switch(a) -> void:
	var e: Dictionary = a.ent
	var pz: String = e["puzzle"]
	if Game.flag(pz + "_open"):
		await say([["", e.get("solved_text", "Es leuchtet ruhig. Hier ist nichts mehr zu tun.")]])
		return
	var prog: Array = _pz_progress(pz).duplicate()
	if e["key"] in prog:
		await say([["", "Das leuchtet schon."]])
		return
	var order: Array = e["order"]
	prog.append(e["key"])
	Audio.sfx_any(["switch_on", "magic_ice"])
	if order.slice(0, prog.size()) != prog:
		Game.flags["pz_" + pz] = []
		Audio.sfx_any(["switch_fail", "ui_error"])
		for c in map().actors:
			if is_instance_valid(c) and c.ent.get("puzzle", "") == pz:
				switch_visual(c)
		await say([["", e.get("fail_text", "Das Leuchten erlischt überall. Falsche Reihenfolge.")]])
		return
	Game.flags["pz_" + pz] = prog
	switch_visual(a)
	if prog.size() == order.size():
		Game.set_flag(pz + "_open")
		Audio.sfx_any(["puzzle_solved", "level_up"])
		get_tree().create_timer(1.4).timeout.connect(func(): Audio.sfx_any(["secret_found", "quest"]))
		UI.flash(Color(0.6, 1, 1), 0.6, 0.6)
		await get_tree().create_timer(0.4).timeout
		await say([["", e.get("open_text", "Irgendwo bewegt sich etwas Schweres.")]])
		map().refresh()

func ev_gezeiten_tafel(_a) -> void:
	await say([["", "In den Fels geritzt, halb von Algen bedeckt:"], ["", "„Was zuerst singt, dann fühlt, dann vom Himmel fällt – nur so öffnet sich, was das Meer verbirgt.“"],
		[N, "Singen ... fühlen ... fallen. Das klingt wie ein Traum, den ich noch nicht hatte."]])

func ev_grotte_spalt(_a) -> void:
	if not Game.flag("gezeiten_open"):
		await say([["", "Ein mächtiger Felsbrocken. Dahinter rauscht Wasser."]])

func ev_grotte_fragment(_a) -> void:
	if Game.flag("grotte_fragment"):
		await say([["", "Der Kristall ist still geworden."]])
		return
	Game.set_flag("grotte_fragment")
	await UI.memory([
		"Ein Kristall, tief in der Grotte. Er summt in deiner Stimme.",
		"Ich habe einen Sinn, der erfüllt werden muss ... oder?",
		"Gewiss hat meine Zeit ein Ende. Doch wissen, wann es kommt – das werde ich nicht.",
	])
	Game.bonus_points += 1
	UI.toast("Erinnerungsfragment: +1 Skillpunkt für alle!")
	Audio.sfx("level_up")

func ev_schrein_tafel(_a) -> void:
	await say([["", "Eine verwitterte Tafel neben dem Schrein:"],
		["", "„Entzünde zuerst das Licht, wo man handelt, dann das Licht, wo man ruht, zuletzt das Licht, wo man betet.“"],
		[N, "Handeln, ruhen, beten. Klingt nach einem typischen Menschentag."]])

func ev_dorfbrunnen(_a) -> void:
	if not Game.flag("laternen_open"):
		await say([["", "Der alte Dorfbrunnen. Ausgetrocknet. Ein Gitter versperrt den Schacht. Darin klickt etwas, als warte es auf Licht."]])
		return
	await say([["", "Das Gitter ist aufgesprungen. Eine rostige Leiter führt hinab in die Dunkelheit."]])
	var c := await ask(N, "Hinabsteigen?", ["Runter da.", "Lieber nicht."])
	if c == 0:
		Audio.sfx_any(["well", "door"])
		main.goto_map("keller", "start")

func ev_hexen_tagebuch(_a) -> void:
	if Game.flag("tagebuch"):
		await say([["", "Das Tagebuch. Die letzten Seiten sind herausgerissen."]])
		return
	Game.set_flag("tagebuch")
	await UI.narrate([
		"Ein Tagebuch, die Schrift jung und wütend:",
		"„Sie kommen mit Booten, jeden Tag mehr. Sie suchen das Freisein und stehlen es uns.“",
		"„Die Netze fangen Dosen. Die Mangos schmecken nach Benzin. Die Alten sagen: eine Pest.“",
		"„Ich weiß einen Zauber. Großmutter hat gesagt, man darf ihn nie benutzen.“",
		"„Morgen ist Sonnenfinsternis.“",
	], "book", 0.9)
	await think("Wer hat das geschrieben? ... Und warum zittern mir die Federn?")

func ev_karte(_a) -> void:
	await say([["", "Eine zerknitterte Karte, zwischen Netzen versteckt."], [N, "„Drei Schritte südlich vom gehörnten Schädel, im Schatten des toten Baums.“ ... In der Steppe?"]])

func ev_schatz(_a) -> void:
	if Game.flag("schatz"):
		await say([["", "Ein leeres Loch. Du hast es gegraben. Stolz."]])
		return
	if Game.count("k_karte") == 0:
		await say([["", "Der Boden ist hier seltsam locker. Aber warum solltest du hier graben?"]])
		return
	Game.set_flag("schatz")
	Audio.sfx_any(["dig", "peck"])
	await say([[N, "Drei Schritte südlich vom Schädel ... *scharr* *scharr* ..."], ["", "Ein Beutel! Darin: Körner, ein Goldzahn und ein Zettel: „Für schlechte Zeiten. – K.“"]])
	Game.remove_item("k_karte")
	Game.add_grains(120)
	Game.add_item("l_goldzahn")

# ======================================================================= MISC
## Quest marker for an NPC entity: "!" = new, "?" = ready to turn in, "" = nothing.
func marker_for(e: Dictionary) -> String:
	var q: String = e.get("quest", "")
	if q != "":
		var st := Game.quest_state(q)
		if st == "":
			return "!"
		if st == "active":
			var ready := {"kura": Game.count("k_plastik") >= 5, "kalb": Game.count("k_kalb") > 0,
				"pilz": Game.count("k_pilz") >= 3, "punkte": Game.count("k_punkt") >= 3}
			return "?" if ready.get(q, false) else ""
		return ""
	var f: String = e.get("story_flag", "")
	if f != "" and not Game.flag(f):
		return "!"
	return ""

func ev_rest(_a) -> void:
	var c := await ask("", "Ein Lagerfeuer knistert. Ausruhen? (HP/MP voll & Speichern)", ["Ausruhen.", "Weitergehen."])
	if c != 0:
		return
	var prev := Audio.current_music()
	Audio.music_pick(["rest"], "rest", 0.8)
	await UI.fade_out(0.6)
	Game.full_heal()
	await get_tree().create_timer(1.2).timeout
	Audio.music(prev, 1.0)
	Game.map_pos = map().player.global_position
	Game.has_map_pos = true
	Game.save_game()
	Audio.sfx("save")
	await UI.fade_in(0.6)
	var thoughts := [
		"Denkt ihr oft an den Tod? Sind wir danach ein und dasselbe – oder seid ihr dann immer noch der Meinung, etwas Besseres zu sein?",
		"Glaubt ihr Menschen wirklich, dass ihr frei seid? Oder seid ihr viel eher gefesselt von eurem Glauben?",
		"Weshalb sollte ein niederwertiges Chicken in einer von Menschen geregelten Welt vom Glück träumen dürfen?",
		"Ich verstand, dass Leid notwendig ist, damit an anderer Stelle Glück existieren kann.",
		"Die Einsamkeit ist kein angenehmer Begleiter.",
	]
	await say([[N, thoughts[randi() % thoughts.size()]]])
	var bench := Game.recruited.filter(func(x): return not (x in Game.party))
	if not bench.is_empty():
		await say([["", "Am Feuer warten: %s. (Im Menü unter \"Team\" tauschen.)" % ", ".join(bench.map(func(x): return Game.char_name(x)))]])
	UI.toast("Gespeichert.")
