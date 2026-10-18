class_name SpriteAnim
extends Node
## Procedural, per-character idle animation for single-frame pixel sprites
## (squash & stretch, lean, little gestures). Each creature type has its own personality.

var spr: PixelSprite
var profile := "hen"
var active := true
var facing := 1.0          # +1 right, -1 left (set by owner)
var _t := 0.0
var _gesture := 0.0        # 0..1 progress of the current gesture
var _next := 2.0
var _seed := 0.0

const PROFILES := {
	"cls_krieger": "hen", "cls_magier": "hen", "cls_heiler": "hen", "cls_tank": "rooster", "cls_assassine": "nervous",
	"cls_base": "hen", "hen_sleep": "sleep", "chick": "chick", "jimmy": "rooster", "vian": "old", "nugget": "nervous",
	"paprika": "diva", "wanderer": "old", "tourist_m": "fat", "tourist_f": "sway", "farmer": "worker", "fisher": "worker",
	"bauer": "worker", "guard": "guard", "bookie": "sway", "butcher": "boss", "wolf": "boss", "fox": "beast", "dog": "beast",
	"crab": "crab", "macaque": "monkey", "cow": "chew", "calf": "chick", "mushroom": "wobble", "ladybug": "flutter",
	"gecko": "beast", "turtle": "slow", "witch": "old", "warung_woman": "worker", "backpacker": "sway", "grasshopper": "flutter",
}

static func attach(s: PixelSprite, sprite_name: String) -> SpriteAnim:
	var a := SpriteAnim.new()
	a.spr = s
	a.profile = PROFILES.get(sprite_name, "")
	if a.profile == "":
		return null
	s.add_child(a)
	return a

func _ready() -> void:
	_seed = randf() * 100.0
	_t = _seed
	_next = randf_range(1.0, 3.5)

func _process(delta: float) -> void:
	if not is_instance_valid(spr):
		return
	_t += delta
	if not active:
		spr.mat.set_shader_parameter("lean", 0.0)
		return
	_next -= delta
	if _next <= 0.0 and _gesture <= 0.0:
		_gesture = 1.0
		_next = randf_range(2.0, 5.0)
	var g := 0.0
	if _gesture > 0.0:
		_gesture = max(0.0, _gesture - delta * 2.4)
		g = sin((1.0 - _gesture) * PI)   # 0 -> 1 -> 0
	var sx := 1.0
	var sy := 1.0
	var rot := 0.0
	var lean := 0.0
	match profile:
		"hen":
			var b := sin(_t * 2.6) * 0.025
			sx -= b * 0.6
			sy += b
			# peck at the ground
			lean = g * 0.16 * facing
			sy -= g * 0.1
		"chick":
			sy += abs(sin(_t * 6.0)) * 0.06
			lean = sin(_t * 9.0) * 0.02 + g * 0.08 * facing
		"rooster":
			var p := sin(_t * 1.7) * 0.035
			sx += p
			sy += p * 0.4
			sx += g * 0.07   # chest flex
			sy += g * 0.05
		"old":
			lean = sin(_t * 1.1) * 0.03 + sin(_t * 17.0) * 0.006
			sy += sin(_t * 1.6) * 0.015 - g * 0.05
		"nervous":
			lean = sin(_t * 13.0 + _seed) * 0.02 + (randf_range(-0.03, 0.03) if randf() < 0.08 else 0.0)
			sy += sin(_t * 5.0) * 0.02
			if g > 0.5:
				spr.set_flip(facing > 0)  # quick paranoid look back
			else:
				spr.set_flip(facing < 0)
		"diva":
			lean = sin(_t * 1.4) * 0.05
			sy += sin(_t * 2.8) * 0.02 + g * 0.08
			sx -= g * 0.04
		"sleep":
			sy += sin(_t * 1.3) * 0.04
		"fat":
			var belly := sin(_t * 1.5) * 0.045
			sx += belly
			sy -= belly * 0.5
			lean = sin(_t * 0.8) * 0.03
		"sway":
			lean = sin(_t * 2.0) * 0.07
			sy += abs(sin(_t * 2.0)) * 0.015 + g * 0.05
		"worker":
			lean = sin(_t * 0.9) * 0.035
			sy += sin(_t * 1.8) * 0.015
			rot = -g * 0.06 * facing
		"guard":
			sy += sin(_t * 4.2) * 0.015
			lean = g * 0.05 * facing
		"beast":
			var pant := sin(_t * 8.0) * 0.022
			sy += pant
			sx -= pant * 0.5
			lean = sin(_t * 3.0) * 0.015 + g * 0.1 * facing   # sniff
		"crab":
			lean = sin(_t * 11.0) * 0.04
			sx += abs(sin(_t * 3.0)) * 0.05 + g * 0.08
			sy -= g * 0.06
		"monkey":
			var hop: float = abs(sin(_t * 4.5))
			sy += hop * 0.08 - 0.04
			sx -= hop * 0.03
			lean = sin(_t * 2.2) * 0.04
		"boss":
			var br := sin(_t * 1.1) * 0.03
			sx += br
			sy += br * 0.6
			lean = 0.04 * facing + sin(_t * 0.7) * 0.02 + g * 0.06 * facing
		"chew":
			sy += sin(_t * 7.0) * 0.012
			lean = sin(_t * 0.9) * 0.02 + g * 0.05
		"wobble":
			rot = sin(_t * 3.0) * 0.06
			sy += abs(sin(_t * 3.0)) * 0.04
		"flutter":
			sy += sin(_t * 14.0) * 0.03
			lean = sin(_t * 2.0) * 0.03
		"slow":
			sy += sin(_t * 0.8) * 0.02
	spr.scale = Vector3(sx, sy, 1.0)
	spr.rotation.z = rot
	spr.mat.set_shader_parameter("lean", lean * spr.height)
