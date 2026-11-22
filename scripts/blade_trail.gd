class_name BladeTrail
extends Node2D
## The glowing blade ribbon drawn over the 3D view: a wide additive glow plus a sharp white core that
## tapers toward the tail. Colours come from the selected blade (Game.blade()).

const LIFE := 0.16
const MAX_W := 26.0

var points: Array = []      # {p: Vector2, t: float}
var active := false
var core := Color.WHITE
var glow := Color(0.6, 0.85, 1.0)
var rainbow := false
var glow_node: Node2D
var sparks: CPUParticles2D


func _ready() -> void:
	glow_node = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_node.material = m
	glow_node.draw.connect(_draw_glow)
	add_child(glow_node)
	sparks = CPUParticles2D.new()
	sparks.emitting = false
	sparks.amount = 40
	sparks.lifetime = 0.35
	sparks.texture = load("res://assets/textures/fx/spark.png")
	sparks.spread = 180
	sparks.initial_velocity_min = 40
	sparks.initial_velocity_max = 160
	sparks.gravity = Vector2(0, 300)
	sparks.scale_amount_min = 0.25
	sparks.scale_amount_max = 0.6
	sparks.material = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = g
	add_child(sparks)
	apply_blade()


func apply_blade() -> void:
	var b: Dictionary = Game.blade()
	core = b.core
	glow = b.glow
	rainbow = b.id == "rainbow"
	sparks.color = glow.lightened(0.3)


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func begin(p: Vector2) -> void:
	points.clear()
	points.append({"p": p, "t": now()})
	active = true


func add(p: Vector2) -> void:
	if not active:
		begin(p)
		return
	var last: Vector2 = points[-1].p
	var d := last.distance_to(p)
	# subdivide long jumps so the ribbon stays smooth
	var n := int(d / 18.0)
	for i in range(1, n + 1):
		points.append({"p": last.lerp(p, float(i) / (n + 1)), "t": now()})
	points.append({"p": p, "t": now()})
	sparks.position = p
	sparks.emitting = d > 6.0


func end() -> void:
	active = false
	sparks.emitting = false


func _process(_d: float) -> void:
	var t := now()
	while not points.is_empty() and t - points[0].t > LIFE:
		points.pop_front()
	if rainbow:
		glow = Color.from_hsv(fmod(t * 0.6, 1.0), 0.85, 1.0)
	queue_redraw()
	glow_node.queue_redraw()


func _ribbon(width: float, col_head: Color, col_tail: Color) -> void:
	var n := points.size()
	if n < 2:
		return
	var t := now()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		var p: Vector2 = points[i].p
		var a: Vector2 = points[maxi(i - 1, 0)].p
		var b: Vector2 = points[mini(i + 1, n - 1)].p
		var dir := (b - a)
		if dir.length() < 0.001:
			dir = Vector2(1, 0)
		var nrm := Vector2(-dir.y, dir.x).normalized()
		var k := float(i) / float(n - 1)
		var age := clampf(1.0 - (t - points[i].t) / LIFE, 0.0, 1.0)
		var w := width * k * age
		left.append(p + nrm * w * 0.5)
		right.append(p - nrm * w * 0.5)
		cols.append(col_tail.lerp(col_head, k) * Color(1, 1, 1, age))
	var poly := PackedVector2Array()
	var pc := PackedColorArray()
	for i in n:
		poly.append(left[i])
		pc.append(cols[i])
	for i in range(n - 1, -1, -1):
		poly.append(right[i])
		pc.append(cols[i])
	if Geometry2D.triangulate_polygon(poly).is_empty():
		# self-intersecting: draw per segment quads
		for i in n - 1:
			draw_polygon(PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]]), PackedColorArray([cols[i], cols[i + 1], cols[i + 1], cols[i]]))
	else:
		draw_polygon(poly, pc)
	draw_circle(points[-1].p, width * 0.5, cols[-1])


func _draw() -> void:
	_ribbon(MAX_W * 0.38, core, Color(core, 0.0))


func _draw_glow() -> void:
	if points.size() < 2:
		return
	# wide soft glow, two passes
	_glow_pass(MAX_W * 1.9, Color(glow, 0.22))
	_glow_pass(MAX_W * 1.05, Color(glow, 0.5))


func _glow_pass(width: float, c: Color) -> void:
	var n := points.size()
	var t := now()
	for i in n - 1:
		var a: Vector2 = points[i].p
		var b: Vector2 = points[i + 1].p
		var k := float(i + 1) / float(n - 1)
		var age := clampf(1.0 - (t - points[i].t) / LIFE, 0.0, 1.0)
		glow_node.draw_line(a, b, Color(c, c.a * age * k), maxf(1.0, width * k * age), true)
	glow_node.draw_circle(points[-1].p, width * 0.45, c)
