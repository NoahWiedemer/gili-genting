class_name Painter
extends RefCounted
## Paints tile maps procedurally but deterministically (organic coasts, paths, scatter).

var w := 0
var d := 0
var g: Array = []   # Array of Arrays of single-char Strings
var rng := RandomNumberGenerator.new()

func _init(width: int, depth: int, fill := "\"", seed := 1) -> void:
	w = width
	d = depth
	rng.seed = seed
	for z in d:
		var row := []
		row.resize(w)
		row.fill(fill)
		g.append(row)

func inb(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < w and z < d

func setc(x: int, z: int, c: String) -> void:
	if inb(x, z):
		g[z][x] = c

func getc(x: int, z: int) -> String:
	return g[z][x] if inb(x, z) else "X"

func rect(x: int, z: int, rw: int, rd: int, c: String) -> void:
	for zz in range(z, z + rd):
		for xx in range(x, x + rw):
			setc(xx, zz, c)

func border(c: String, thick := 1) -> void:
	for z in d:
		for x in w:
			if x < thick or z < thick or x >= w - thick or z >= d - thick:
				setc(x, z, c)

func circle(cx: float, cz: float, r: float, c: String, wobble := 0.0) -> void:
	for z in range(int(cz - r - 2), int(cz + r + 3)):
		for x in range(int(cx - r - 2), int(cx + r + 3)):
			var a := atan2(z - cz, x - cx)
			var rr := r + sin(a * 3.0 + cx) * wobble + cos(a * 5.0 + cz) * wobble * 0.5
			if Vector2(x - cx, z - cz).length() <= rr:
				setc(x, z, c)

## South coast: for every column, rows below `base + wave` become sand/wet/shallow/deep.
func coast_south(base: float, amp: float, bands: Array) -> void:
	for x in w:
		var edge := base + sin(x * 0.21) * amp + sin(x * 0.53 + 1.3) * amp * 0.45
		var z0 := int(round(edge))
		var off := 0
		for b in bands:
			for k in b[1]:
				setc(x, z0 + off, b[0])
				off += 1
		for z in range(z0 + off, d):
			setc(x, z, bands[-1][0])

func coast_west(base: float, amp: float, bands: Array) -> void:
	for z in d:
		var edge := base + sin(z * 0.27 + 0.4) * amp + sin(z * 0.61) * amp * 0.4
		var x0 := int(round(edge))
		var off := 0
		for b in bands:
			for k in b[1]:
				setc(x0 - off, z, b[0])
				off += 1
		for x in range(0, x0 - off + 1):
			setc(x, z, bands[-1][0])

func coast_east(base: float, amp: float, bands: Array) -> void:
	for z in d:
		var edge := base + sin(z * 0.23 + 2.0) * amp + sin(z * 0.57) * amp * 0.4
		var x0 := int(round(edge))
		var off := 0
		for b in bands:
			for k in b[1]:
				setc(x0 + off, z, b[0])
				off += 1
		for x in range(x0 + off, w):
			setc(x, z, bands[-1][0])

## Thick path through points (axis-aligned segments with slight wiggle).
func path(points: Array, c: String, width := 2, only_on := "") -> void:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var steps := int(max(abs(b.x - a.x), abs(b.y - a.y))) * 2 + 1
		for s in steps + 1:
			var t := float(s) / steps
			var p := a.lerp(b, t)
			var wig := sin(p.x * 0.7 + p.y * 0.5) * 0.4
			for ox in width:
				for oz in width:
					var xx := int(round(p.x + ox - width / 2.0 + wig))
					var zz := int(round(p.y + oz - width / 2.0))
					if only_on == "" or getc(xx, zz) in only_on:
						setc(xx, zz, c)

## Randomly places `c` on cells whose current char is in `on`, inside a rect.
func scatter(x: int, z: int, rw: int, rd: int, c: String, density: float, on: String, min_gap := 0) -> void:
	for zz in range(z, z + rd):
		for xx in range(x, x + rw):
			if getc(xx, zz) in on and rng.randf() < density:
				if min_gap > 0 and _near(xx, zz, c, min_gap):
					continue
				setc(xx, zz, c)

func _near(x: int, z: int, c: String, r: int) -> bool:
	for zz in range(z - r, z + r + 1):
		for xx in range(x - r, x + r + 1):
			if getc(xx, zz) == c:
				return true
	return false

## Organic thick tree wall along the edges (for forest borders).
func forest_edge(c: String, depth: float, on := "") -> void:
	for z in d:
		for x in w:
			var dist: float = min(min(x, z), min(w - 1 - x, d - 1 - z))
			var n := depth + sin(x * 0.45 + z * 0.13) * 1.2 + sin(z * 0.37) * 0.8
			if dist < n and (on == "" or getc(x, z) in on):
				setc(x, z, c)

func clear(x: int, z: int, rw: int, rd: int, c: String) -> void:
	rect(x, z, rw, rd, c)

func rows() -> Array:
	var out := []
	for row in g:
		out.append("".join(row))
	return out
