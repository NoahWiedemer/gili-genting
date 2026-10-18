extends Node
## Music (crossfading), ambient loops and pooled sound effects.

const NON_LOOP := ["victory", "victory_2", "victory_3", "boss_victory", "gameover", "revolution"]
const VOICES := {"tourist_m": "tourist", "tourist_f": "influencer", "macaque": "macaque", "crab": "crab", "fox": "fox",
	"dog": "dog", "nightdog": "dog", "guard": "guard", "farmer": "farmer", "farmhand": "farmer", "bauer": "farmer",
	"fisher": "fisher", "bookie": "bookie", "wolf": "wolf", "butcher": "butcher", "cow": "cow", "turtle": "turtle",
	"gecko": "gecko", "chicken": "chicken", "jimmy": "rooster"}
var _last_pick := {}
var listener: Node3D

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _current := ""
var _current_amb := ""
var _cache := {}
var music_volume := 0.8
var sfx_volume := 0.9

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _mk()
	_music_b = _mk()
	_ambient = _mk()
	for i in 12:
		_sfx_pool.append(_mk())

func _mk() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p

func _load(path: String, loop: bool) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamWAV and loop:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			var bytes_per := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
			if w.stereo:
				bytes_per *= 2
			w.loop_end = w.data.size() / bytes_per
	_cache[path] = s
	return s

func music(track: String, fade := 0.8) -> void:
	if track == _current:
		return
	_current = track
	var stream: AudioStream = null
	if track != "":
		stream = _load("res://assets/audio/music/%s.wav" % track, not (track in NON_LOOP))
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.stop)
	if stream:
		_music_a.stream = stream
		_music_a.volume_db = -40.0
		_music_a.play()
		var tw2 := create_tween()
		tw2.tween_property(_music_a, "volume_db", linear_to_db(max(music_volume, 0.001)), fade)

func refresh_volume() -> void:
	if _music_a and _music_a.playing:
		_music_a.volume_db = linear_to_db(max(music_volume, 0.001))

func exists(path: String) -> bool:
	return ResourceLoader.exists(path)

## Picks a random existing track from a pool (never the same twice in a row) and plays it.
func music_pick(pool: Array, key := "", fade := 0.8) -> void:
	var ok := pool.filter(func(t): return exists("res://assets/audio/music/%s.wav" % t))
	if ok.is_empty():
		return
	var last: String = _last_pick.get(key, "")
	var choice: String = ok[randi() % ok.size()]
	if ok.size() > 1:
		while choice == last:
			choice = ok[randi() % ok.size()]
	_last_pick[key] = choice
	music(choice, fade)

func sfx_any(names: Array, vol := 1.0) -> void:
	var ok := names.filter(func(n): return exists("res://assets/audio/sfx/%s.wav" % n))
	if not ok.is_empty():
		sfx(ok[randi() % ok.size()], randf_range(0.94, 1.08), vol)

## A creature's voice, louder when close to the listener (the player).
func voice(kind: String, pos = null, vol := 0.8) -> void:
	var v: String = VOICES.get(kind, kind)
	var d := 0.0
	if pos != null and listener and is_instance_valid(listener):
		d = listener.global_position.distance_to(pos)
	var att: float = clamp(1.0 - d / 10.0, 0.0, 1.0)
	if att <= 0.05:
		return
	sfx_any([v + "_1", v + "_2", v + "_3"], vol * att)

func current_music() -> String:
	return _current

func ambient(name: String) -> void:
	if name == _current_amb:
		return
	_current_amb = name
	if name == "":
		var tw := create_tween()
		tw.tween_property(_ambient, "volume_db", -40.0, 0.8)
		tw.tween_callback(_ambient.stop)
		return
	var s := _load("res://assets/audio/sfx/%s.wav" % name, true)
	if s:
		_ambient.stream = s
		_ambient.volume_db = -40.0
		_ambient.play()
		create_tween().tween_property(_ambient, "volume_db", linear_to_db(sfx_volume * 0.55), 1.2)

func sfx(name: String, pitch := 1.0, vol := 1.0) -> void:
	var s := _load("res://assets/audio/sfx/%s.wav" % name, false)
	if s == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(max(sfx_volume * vol, 0.001))
			p.play()
			return

func sfx_var(name: String, vol := 1.0) -> void:
	sfx(name, randf_range(0.9, 1.12), vol)
