class_name GameOverScreen
extends CanvasLayer
## "Geschlachtet." – retry from the last autosave or go back to the title.

signal done(choice: String)

const LINES := [
	"Du wurdest geschlachtet. Etwas zu früh. Der Bauer ist trotzdem zufrieden.",
	"Ende. Irgendwo freut sich jemand über Chicken Wings.",
	"Das Paradies hat angerufen. Es sagt, du warst nicht pünktlich.",
	"Ein toter Hai flüstert: \"Noch eine Leiche und ich tick' aus.\"",
]

func _ready() -> void:
	layer = 6
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.0, 0.0)
	root.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -220
	v.offset_right = 220
	v.offset_top = -70
	v.offset_bottom = 80
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	var t := UI.label("GESCHLACHTET", Color(0.95, 0.25, 0.2), 42, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label(LINES[randi() % LINES.size()], UI.CREAM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	var b1 := Button.new()
	b1.text = "Nochmal (letzter Speicherpunkt)"
	b1.pressed.connect(func(): done.emit("retry"))
	v.add_child(b1)
	var b2 := Button.new()
	b2.text = "Zum Titel"
	b2.pressed.connect(func(): done.emit("title"))
	v.add_child(b2)
	await get_tree().process_frame
	b1.grab_focus()
	if Game.auto:
		print("[story] GAME OVER (auto) at map ", Game.map_id, " levels ", Game.slot_level)
		get_tree().quit(2)
