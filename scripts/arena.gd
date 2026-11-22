class_name Arena
extends Node3D
## The 3D play field: painted backdrop, lights, ambient particles, fruit launching, ballistic flight, slicing
## along the swipe, halves, juice, splats, popups, specials, bombs, bosses. Rules live in main.gd (Match);
## the arena only reports events through signals.

signal sliced(kind: String, points: int, pos: Vector2)
signal missed(kind: String, pos: Vector2)
signal combo(count: int, bonus: int, pos: Vector2)
signal bomb_hit(pos: Vector2)
signal special(kind: String)
signal multi_done(hits: int, bonus: int)
signal boss_hit(hp: int, max_hp: int)
signal boss_dead
signal stroke_started

const G := 9.8
const FRUIT_SCALE := 1.7
const SPLAT_Z := -3.0
const FX := "res://assets/textures/fx/"

var cam: Camera3D
var env: WorldEnvironment
var key_light: DirectionalLight3D
var backdrop: MeshInstance3D
var backdrop_mat: ShaderMaterial
var ambient: CPUParticles3D
var trail: BladeTrail

var meshes := {}          # kind -> {whole, top, bot}
var tex := {}
var fruits: Array = []    # live Fruit nodes
var pieces: Array = []    # flying halves
var splats: Array = []
var rng := RandomNumberGenerator.new()

# spawning
var cfg := {}             # speed, interval, wave, bombs, special, fruits, specials, focus
var spawning := false
var spawn_t := 0.6
var frenzy_t := 0.0
var frenzy_spawn := 0.0
var freeze_t := 0.0
var double_t := 0.0
var time_scale := 1.0
var slowmo_t := 0.0
var shake := 0.0
var demo := false         # title screen: a ghost blade slices everything
var bot := false          # autotest: the ghost blade plays the level (avoids bombs)
var bot_miss := 0.0       # chance the bot ignores a fruit (to test drops)
var paused := false

# blade / strokes
var pressing := false
var last_pos := Vector2.ZERO
var last_move_t := 0.0
var stroke_count := 0
var stroke_t := 0.0
var stroke_pos := Vector2.ZERO
var stroke_id := 0
var ghost_path: Array = []
var ghost_t := 0.0

# boss
var boss: Fruit = null
var boss_hp := 0
var boss_max := 0
var boss_t := 0.0
var boss_spit := 3.0
var boss_scale := 2.5

var half_h := 4.66
var half_w := 2.6


class Fruit extends Node3D:
	var kind := ""
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var radius := 0.4
	var points := 10
	var special := ""
	var dead := false
	var hold := 0.0
	var hits := 0
	var hit_cd := 0.0
	var mesh: MeshInstance3D
	var spark: CPUParticles3D
	var is_piece := false
	var life := 0.0
	var last_stroke := -1
	var safe_t := 0.0


func _ready() -> void:
	rng.randomize()
	_load_assets()
	cam = Camera3D.new()
	cam.position = Vector3(0, 0, 10)
	cam.fov = 50
	cam.near = 0.5
	cam.far = 60
	add_child(cam)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.environment = e
	add_child(env)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42, -35, 0)
	key_light.light_energy = 1.35
	key_light.light_specular = 1.2
	add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 150, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(1.0, 0.85, 0.75)
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 180, 0)
	rim.light_energy = 0.6
	add_child(rim)
	_make_backdrop()
	trail = BladeTrail.new()
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	cl.add_child(trail)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _load_assets() -> void:
	for k in Game.FRUITS + Game.SPECIALS + ["bomb"]:
		var path := "res://assets/models/fruits/%s.glb" % k
		if not ResourceLoader.exists(path):
			continue
		var sc: PackedScene = load(path)
		var inst := sc.instantiate()
		var d := {}
		for part in ["whole", "top", "bot"]:
			var mi := inst.find_child(part, true, false) as MeshInstance3D
			if mi:
				d[part] = mi.mesh
				_tune_materials(mi.mesh, k)
		meshes[k] = d
		inst.free()
	for t in ["dot", "drop", "splat_1", "splat_2", "splat_3", "splat_4", "streak", "ring", "spark", "petal", "flake", "smoke", "glow"]:
		tex[t] = load(FX + t + ".png")


func _tune_materials(m: Mesh, kind: String) -> void:
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s) as StandardMaterial3D
		if mat == null:
			continue
		mat.rim_enabled = true
		mat.rim = 0.35
		mat.rim_tint = 0.6
		mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		if kind == "frostberry":
			mat.emission_enabled = true
			mat.emission = Color(0.25, 0.55, 1.0)
			mat.emission_energy_multiplier = 0.6
		elif kind == "goldapple":
			mat.emission_enabled = true
			mat.emission = Color(0.5, 0.32, 0.05)
			mat.emission_energy_multiplier = 0.5


func _make_backdrop() -> void:
	backdrop = MeshInstance3D.new()
	var q := QuadMesh.new()
	backdrop.mesh = q
	backdrop.position = Vector3(0, 0, -14)
	backdrop_mat = ShaderMaterial.new()
	backdrop_mat.shader = load("res://shaders/backdrop.gdshader")
	backdrop.material_override = backdrop_mat
	add_child(backdrop)
	ambient = CPUParticles3D.new()
	ambient.amount = 40
	ambient.lifetime = 9.0
	ambient.preprocess = 9.0
	ambient.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ambient.emission_box_extents = Vector3(9, 0.5, 4)
	ambient.position = Vector3(0, 6.5, -4)
	ambient.direction = Vector3(0.2, -1, 0)
	ambient.spread = 25
	ambient.gravity = Vector3.ZERO
	ambient.initial_velocity_min = 0.8
	ambient.initial_velocity_max = 1.6
	ambient.angular_velocity_min = -90
	ambient.angular_velocity_max = 90
	ambient.angle_min = 0
	ambient.angle_max = 360
	ambient.scale_amount_min = 0.6
	ambient.scale_amount_max = 1.2
	add_child(ambient)


## Applies a world's look: painted backdrop, light colours, ambient particles.
func set_world(w: int) -> void:
	var W: Dictionary = Game.WORLDS[clampi(w, 0, Game.WORLDS.size() - 1)]
	var path := "res://assets/backgrounds/%s.jpg" % W.bg
	if ResourceLoader.exists(path):
		backdrop_mat.set_shader_parameter("tex", load(path))
	key_light.light_color = W.light
	env.environment.ambient_light_color = W.ambient
	var pm := QuadMesh.new()
	pm.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ambient.color = Color.WHITE
	ambient.direction = Vector3(0.2, -1, 0)
	ambient.position = Vector3(0, 6.5, -4)
	ambient.initial_velocity_min = 0.8
	ambient.initial_velocity_max = 1.6
	ambient.gravity = Vector3.ZERO
	match W.fx:
		"petals":
			mat.albedo_texture = tex.petal
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			ambient.color = Color(1, 0.75, 0.85)
			pm.size = Vector2(0.16, 0.2)
		"sparkles":
			mat.albedo_texture = tex.spark
			ambient.color = Color(1, 0.85, 0.5)
			ambient.position = Vector3(0, -6.5, -4)
			ambient.direction = Vector3(0, 1, 0)
			ambient.initial_velocity_min = 0.3
			ambient.initial_velocity_max = 0.7
		"lanterns":
			mat.albedo_texture = tex.glow
			ambient.color = Color(1, 0.55, 0.2, 0.8)
			pm.size = Vector2(0.35, 0.35)
			ambient.position = Vector3(0, -6.5, -4)
			ambient.direction = Vector3(0, 1, 0)
			ambient.initial_velocity_min = 0.3
			ambient.initial_velocity_max = 0.6
		"snow":
			mat.albedo_texture = tex.flake
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			ambient.color = Color(0.9, 0.95, 1.0)
			pm.size = Vector2(0.15, 0.15)
		"embers":
			mat.albedo_texture = tex.dot
			ambient.color = Color(1, 0.45, 0.1)
			pm.size = Vector2(0.12, 0.12)
			ambient.position = Vector3(0, -6.5, -4)
			ambient.direction = Vector3(0.1, 1, 0)
			ambient.initial_velocity_min = 1.0
			ambient.initial_velocity_max = 2.2
		"stars":
			mat.albedo_texture = tex.spark
			ambient.color = Color(0.8, 0.75, 1.0)
			ambient.initial_velocity_min = 0.1
			ambient.initial_velocity_max = 0.3
	pm.material = mat
	ambient.mesh = pm
	ambient.restart()


func _on_resize() -> void:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1.0, vs.y)
	half_h = tan(deg_to_rad(cam.fov * 0.5)) * cam.position.z
	half_w = half_h * aspect
	# backdrop covers the frustum at its depth (image is 2:3 portrait)
	var dist := cam.position.z - backdrop.position.z
	var bh := tan(deg_to_rad(cam.fov * 0.5)) * dist * 2.0 * 1.06
	var bw := bh * aspect
	var img_aspect := 2.0 / 3.0
	var size := Vector2(bw, bw / img_aspect) if bw / img_aspect >= bh else Vector2(bh * img_aspect, bh)
	(backdrop.mesh as QuadMesh).size = size


# ------------------------------------------------------------------ public control

func clear_all() -> void:
	for f in fruits + pieces:
		if is_instance_valid(f):
			f.queue_free()
	fruits.clear()
	pieces.clear()
	for s in splats:
		if is_instance_valid(s):
			s.queue_free()
	splats.clear()
	boss = null
	freeze_t = 0.0
	double_t = 0.0
	frenzy_t = 0.0
	time_scale = 1.0
	slowmo_t = 0.0
	Sfx.fuse(false)
	backdrop_mat.set_shader_parameter("freeze", 0.0)


func start(config: Dictionary) -> void:
	cfg = config
	spawning = true
	spawn_t = 0.8
	stroke_count = 0


func stop_spawning() -> void:
	spawning = false


func live_count() -> int:
	var n := 0
	for f: Fruit in fruits:
		if not f.dead:
			n += 1
	return n


# ------------------------------------------------------------------ spawning

func _spawn_wave() -> void:
	var w: Array = cfg.get("wave", [1, 2])
	var n := rng.randi_range(int(w[0]), int(w[1]))
	var pattern := rng.randi() % 3
	var base_x := rng.randf_range(-0.6, 0.6) * half_w
	var bombs_here := 0
	for i in n:
		var kind := _pick_kind()
		if kind == "bomb":
			if bombs_here >= 1 + n / 4 or (n == 1 and rng.randf() < 0.5):
				kind = _pick_fruit()
			else:
				bombs_here += 1
		var delay := 0.0
		var x0 := rng.randf_range(-0.85, 0.85) * half_w
		if pattern == 1:
			delay = i * 0.17
		elif pattern == 2:
			x0 = base_x + rng.randf_range(-0.3, 0.3)
			delay = i * 0.06
		if delay <= 0.0:
			launch(kind, x0)
		else:
			get_tree().create_timer(delay / maxf(0.2, float(cfg.get("speed", 1.0))), false).timeout.connect(func(): if spawning: launch(kind, x0))


func _pick_fruit() -> String:
	var pool: Array = cfg.get("fruits", Game.FRUITS)
	var focus: String = cfg.get("focus", "")
	if focus != "" and rng.randf() < 0.42:
		return focus
	return pool[rng.randi() % pool.size()]


func _pick_kind() -> String:
	if rng.randf() < float(cfg.get("bombs", 0.0)):
		return "bomb"
	var sp: Array = cfg.get("specials", [])
	if not sp.is_empty() and rng.randf() < float(cfg.get("special", 0.0)):
		var active := false
		for f: Fruit in fruits:
			if f.special != "" and f.special != "bomb" and not f.dead:
				active = true
		if not active:
			return sp[rng.randi() % sp.size()]
	return _pick_fruit()


func make_fruit(kind: String) -> Fruit:
	var f := Fruit.new()
	f.kind = kind
	var meta: Dictionary = Game.fruit_meta.get(kind, {})
	f.radius = float(meta.get("radius", 0.3)) * FRUIT_SCALE
	f.points = int(meta.get("points", 10))
	f.special = String(meta.get("special", ""))
	f.mesh = MeshInstance3D.new()
	f.mesh.mesh = meshes.get(kind, {}).get("whole")
	f.mesh.scale = Vector3.ONE * FRUIT_SCALE
	f.add_child(f.mesh)
	if kind == "bomb":
		f.spark = _fuse_spark()
		f.spark.position = Vector3(0.15, 0.55, 0.03) * FRUIT_SCALE
		f.add_child(f.spark)
		var glow := Sprite3D.new()
		glow.texture = tex.glow
		glow.modulate = Color(1.0, 0.15, 0.1, 0.55)
		glow.pixel_size = 0.012
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.position = Vector3(0, 0, -0.2)
		f.add_child(glow)
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "modulate:a", 0.15, 0.25)
		tw.tween_property(glow, "modulate:a", 0.6, 0.25)
	elif f.special != "":
		var halo := Sprite3D.new()
		halo.texture = tex.glow
		halo.modulate = {"double": Color(1, 0.8, 0.2, 0.7), "freeze": Color(0.3, 0.7, 1.0, 0.7), "frenzy": Color(1, 0.9, 0.3, 0.7), "multi": Color(1, 0.3, 0.3, 0.7)}.get(f.special, Color.WHITE)
		halo.pixel_size = 0.014
		halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		halo.position = Vector3(0, 0, -0.3)
		f.add_child(halo)
	add_child(f)
	return f


func launch(kind: String, x0: float, side := 0) -> Fruit:
	var f := make_fruit(kind)
	var sp := float(cfg.get("speed", 1.0))
	var z := rng.randf_range(-1.0, 0.7)
	if side == 0:
		var y0 := -half_h - 0.9
		var apex := rng.randf_range(0.05, 0.78) * half_h
		apex = minf(apex, half_h - f.radius * 1.4)
		var vy := sqrt(2.0 * G * (apex - y0))
		var ta := vy / G
		var xr := rng.randf_range(-0.55, 0.55) * half_w
		f.position = Vector3(x0, y0, z)
		f.vel = Vector3((xr - x0) / ta * 0.85, vy, 0)
	else:
		var y0 := rng.randf_range(-0.5, 0.3) * half_h
		f.position = Vector3(side * (half_w + 0.8), y0, z)
		f.vel = Vector3(-side * rng.randf_range(2.5, 4.5), rng.randf_range(4.0, 7.5), 0)
	f.spin = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(1.5, 4.5)
	f.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	if kind == "bomb":
		f.spin *= 0.4
		f.rotation = Vector3(0, rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
	fruits.append(f)
	Sfx.play("launch", rng.randf_range(0.85, 1.2) * sqrt(sp), -8.0)
	return f


func _fuse_spark() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.35
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex.spark
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 1, 0)
	p.spread = 70
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.7, 1))
	g.set_color(1, Color(1, 0.3, 0.05, 0))
	p.color_ramp = g
	p.local_coords = false
	return p


# ------------------------------------------------------------------ boss

func spawn_boss(kind: String, hp: int) -> void:
	boss = make_fruit(kind)
	boss_scale = clampf(half_w * 0.62 / boss.radius, 1.6, 2.6)
	boss.mesh.scale = Vector3.ONE * FRUIT_SCALE * boss_scale
	boss.radius *= boss_scale
	boss.special = "boss"
	boss.position = Vector3(0, -half_h - 3.0, -0.8)
	boss.spin = Vector3(0, 0.6, 0)
	boss_hp = hp
	boss_max = hp
	boss_t = 0.0
	boss_spit = 4.0
	var aura := Sprite3D.new()
	aura.texture = tex.glow
	aura.modulate = Color(1, 0.4, 0.2, 0.55)
	aura.pixel_size = 0.04
	aura.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	aura.position = Vector3(0, 0, -1.0)
	boss.add_child(aura)
	fruits.append(boss)


func _update_boss(dt: float) -> void:
	if boss == null or not is_instance_valid(boss) or boss.dead:
		return
	boss_t += dt
	var target := Vector3(sin(boss_t * 0.7) * half_w * 0.45, half_h * 0.22 + sin(boss_t * 1.13) * half_h * 0.18, -0.8)
	if boss_t < 1.6:
		boss.position = boss.position.lerp(Vector3(0, half_h * 0.2, -0.8), clampf(dt * 2.5, 0, 1))
	else:
		boss.position = boss.position.lerp(target, clampf(dt * 1.5, 0, 1))
	boss.rotate_y(dt * 0.5)
	boss.rotation.z = sin(boss_t * 1.7) * 0.15
	boss.hit_cd -= dt
	if spawning:
		boss_spit -= dt
		if boss_spit <= 0.0:
			boss_spit = rng.randf_range(2.6, 4.2) / float(cfg.get("speed", 1.0))
			var n := 1 + int(boss_max > 50) + int(rng.randf() < 0.35)
			for i in n:
				var k := "bomb" if rng.randf() < 0.45 else _pick_fruit()
				var f := launch(k, boss.position.x)
				var sd := -1.0 if rng.randf() < 0.5 else 1.0
				f.position = boss.position + Vector3(sd * boss.radius * 0.8, -0.3, 0.6)
				f.vel = Vector3(sd * rng.randf_range(3.0, 5.0), rng.randf_range(3.5, 6.0), 0)
				f.safe_t = 0.45
			Sfx.play("launch", 0.7, -2.0)


func _hit_boss(at: Vector2, dir: Vector2) -> void:
	if boss.hit_cd > 0.0:
		return
	boss.hit_cd = 0.11
	boss_hp -= 1
	var wp := boss.global_position + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), 1.2)
	var juice: Color = _juice(boss.kind)
	_burst(wp, juice, 14, 1.0)
	_flash_streak(wp, dir, juice, 2.5)
	_add_splat(wp, juice, 1.2)
	Sfx.play("thump", rng.randf_range(0.9, 1.15))
	Sfx.play("squish", rng.randf_range(0.8, 1.1), -6.0)
	shake = maxf(shake, 0.18)
	var t := boss.mesh.create_tween()
	var s := FRUIT_SCALE * boss_scale
	t.tween_property(boss.mesh, "scale", Vector3(s * 1.08, s * 0.92, s * 1.08), 0.05)
	t.tween_property(boss.mesh, "scale", Vector3.ONE * s, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_popup("+5", wp, Color(1, 0.95, 0.6), 0.9)
	sliced.emit("boss", 5, at)
	boss_hit.emit(boss_hp, boss_max)
	if boss_hp <= 0:
		_kill_boss(dir)


func _kill_boss(dir: Vector2) -> void:
	slowmo(1.2, 0.25)
	_slice(boss, dir, true)
	for i in 3:
		var p := boss.global_position + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 1)
		_burst(p, _juice(boss.kind), 40, 2.0)
		_add_splat(p, _juice(boss.kind), 2.5)
	_ring(boss.global_position, Color(1, 0.9, 0.6), 4.0)
	Sfx.play("bomb", 0.7, -4.0)
	Sfx.play("firework")
	shake = 0.6
	boss = null
	boss_dead.emit()


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if paused:
		return
	var real := delta
	if slowmo_t > 0.0:
		slowmo_t -= real
		if slowmo_t <= 0.0:
			time_scale = 1.0
	if freeze_t > 0.0:
		freeze_t -= real
		backdrop_mat.set_shader_parameter("freeze", clampf(freeze_t * 2.0, 0, 1))
		if freeze_t <= 0.0:
			backdrop_mat.set_shader_parameter("freeze", 0.0)
	if double_t > 0.0:
		double_t -= real
	var ts := time_scale * (0.4 if freeze_t > 0.0 else 1.0)
	var sp := float(cfg.get("speed", 1.0))
	var dt := delta * ts * sp
	# spawning
	if spawning:
		if frenzy_t > 0.0:
			frenzy_t -= real
			frenzy_spawn -= real
			if frenzy_spawn <= 0.0:
				frenzy_spawn = 0.11
				launch(_pick_fruit(), 0.0, -1 if rng.randf() < 0.5 else 1)
		elif boss == null or not cfg.has("boss"):
			spawn_t -= dt
			if spawn_t <= 0.0 and (live_count() == 0 or spawn_t < -float(cfg.get("interval", 1.4)) * 0.6):
				_spawn_wave()
				spawn_t = float(cfg.get("interval", 1.4)) * rng.randf_range(0.8, 1.25)
		else:
			spawn_t -= dt
			if spawn_t <= 0.0:
				spawn_t = float(cfg.get("interval", 1.4)) * 1.8
				_spawn_wave()
	_update_boss(dt)
	var any_bomb := false
	for o in fruits.duplicate():
		if not is_instance_valid(o):
			fruits.erase(o)
			continue
		var f: Fruit = o
		if f == boss:
			continue
		if f.hold > 0.0:
			f.hold -= real
			f.mesh.position = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0) * 0.04 * (1 + f.hits * 0.1)
			f.rotate(Vector3(0, 1, 0).normalized(), real * 3.0)
			f.hit_cd -= real
			if f.hold <= 0.0:
				_finish_multi(f)
			continue
		f.safe_t -= real
		f.vel.y -= G * dt
		f.position += f.vel * dt
		if f.spin.length() > 0.0:
			f.rotate(f.spin.normalized(), f.spin.length() * dt)
		if f.kind == "bomb":
			any_bomb = true
		if f.position.y < -half_h - 1.6 and f.vel.y < 0.0:
			fruits.erase(f)
			if not f.dead and f.kind != "bomb" and f.special == "":
				var sx := cam.unproject_position(Vector3(f.position.x, -half_h, 0))
				missed.emit(f.kind, sx)
				Sfx.play("miss", 1.0, -4.0)
			f.queue_free()
	Sfx.fuse(any_bomb and spawning)
	for o in pieces.duplicate():
		if not is_instance_valid(o):
			pieces.erase(o)
			continue
		var p: Fruit = o
		p.vel.y -= G * dt
		p.position += p.vel * dt
		p.rotate(p.spin.normalized(), p.spin.length() * dt)
		p.life += real
		if p.position.y < -half_h - 2.5 or p.life > 6.0:
			pieces.erase(p)
			p.queue_free()
	# stroke end -> combo
	if stroke_count > 0 and Time.get_ticks_msec() / 1000.0 - stroke_t > 0.28:
		_end_stroke()
	# camera shake and gentle sway
	shake = maxf(0.0, shake - real * 1.8)
	var tt := Time.get_ticks_msec() / 1000.0
	cam.h_offset = sin(tt * 37.0) * shake * 0.35 + sin(tt * 0.31) * 0.05
	cam.v_offset = cos(tt * 41.0) * shake * 0.35 + cos(tt * 0.23) * 0.04
	backdrop_mat.set_shader_parameter("sway", Vector2(cam.h_offset, cam.v_offset) * 0.004)
	if demo or bot:
		_ghost(real)


# ------------------------------------------------------------------ blade input

func _unhandled_input(ev: InputEvent) -> void:
	if paused or demo or bot:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			pressing = true
			last_pos = ev.position
			trail.begin(ev.position)
			stroke_started.emit()
		else:
			pressing = false
			trail.end()
	elif ev is InputEventMouseMotion and pressing:
		swipe_to(ev.position)


func swipe_to(p: Vector2) -> void:
	var a := last_pos
	last_pos = p
	trail.add(p)
	if a.distance_to(p) < 2.0:
		return
	if a.distance_to(p) > 26.0 and rng.randf() < 0.25:
		Sfx.play("whoosh", rng.randf_range(0.9, 1.25), -9.0)
	_cut(a, p)


func _cut(a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	for o in fruits.duplicate():
		if not is_instance_valid(o) or o.dead:
			continue
		var f: Fruit = o
		if f.safe_t > 0.0:
			continue
		var c := cam.unproject_position(f.global_position)
		var edge := cam.unproject_position(f.global_position + cam.global_transform.basis.x * f.radius)
		var r := c.distance_to(edge)
		if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) > r * 1.05:
			continue
		if f == boss:
			_hit_boss(c, dir)
		elif f.hold > 0.0:
			if f.hit_cd <= 0.0:
				f.hit_cd = 0.07
				f.hits += 1
				var wp := f.global_position + Vector3(0, 0, 0.5)
				_burst(wp, _juice(f.kind), 8, 0.8)
				_popup("+%d" % (f.hits), wp + Vector3(rng.randf_range(-0.5, 0.5), 0.6, 0), Color(1, 0.85, 0.4), 0.7)
				Sfx.play("hit", 0.9 + f.hits * 0.04, -3.0)
				sliced.emit("multi", 2, c)
		else:
			_slice(f, dir)
			if f.kind == "bomb":
				return
			var pts := f.points * (2 if double_t > 0.0 else 1)
			if f.special in ["double", "freeze", "frenzy"]:
				_activate(f.special, f.global_position)
			if f.special == "multi":
				continue
			stroke_count += 1
			stroke_t = Time.get_ticks_msec() / 1000.0
			stroke_pos = c
			Sfx.chime(stroke_count - 1)
			_popup("+%d" % pts, f.global_position + Vector3(0, 0.4, 0.6), Color(1, 1, 1), 0.8 if pts < 20 else 1.1)
			sliced.emit(f.kind, pts, c)
	if stroke_count > 0:
		stroke_t = Time.get_ticks_msec() / 1000.0 if stroke_t == 0.0 else stroke_t


func _end_stroke() -> void:
	if stroke_count >= 3:
		var bonus := stroke_count * 5 * (2 if double_t > 0.0 else 1)
		combo.emit(stroke_count, bonus, stroke_pos)
		var wp := _screen_to_world(stroke_pos, 1.0)
		_popup("%s ×%d\n+%d" % [Game.tr_("combo"), stroke_count, bonus], wp + Vector3(0, 0.8, 0), Color(1, 0.8, 0.2), 1.6)
		Sfx.play("special", 1.0 + stroke_count * 0.05, -2.0)
		shake = maxf(shake, 0.12 + stroke_count * 0.03)
		if stroke_count >= 5:
			slowmo(0.5, 0.45)
	stroke_count = 0
	stroke_t = 0.0


func _screen_to_world(p: Vector2, z: float) -> Vector3:
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var t := (z - o.z) / d.z
	return o + d * t


func slowmo(dur: float, scale: float) -> void:
	slowmo_t = dur
	time_scale = scale


# ------------------------------------------------------------------ slicing

func _juice(kind: String) -> Color:
	var j: Array = Game.fruit_meta.get(kind, {}).get("juice", [1, 0.5, 0.3])
	return Color(j[0], j[1], j[2])


func _slice(f: Fruit, dir2: Vector2, big := false) -> void:
	f.dead = true
	var pos := f.global_position
	if f.kind == "bomb":
		_explode(f)
		return
	if f.special == "multi" and not big:
		f.dead = false
		f.hold = 1.8
		f.hits = 1
		f.vel = Vector3.ZERO
		f.hit_cd = 0.1
		_popup(Game.tr_("hits") % 1, pos + Vector3(0, 0.8, 0.6), Color(1, 0.6, 0.4), 1.0)
		Sfx.play("hit", 0.9)
		_burst(pos + Vector3(0, 0, 0.5), _juice(f.kind), 10, 1.0)
		return
	var dir := Vector3(dir2.x, -dir2.y, 0).normalized()
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	var n := Vector3(-dir.y, dir.x, 0)          # cut normal in the screen plane
	var juice := _juice(f.kind)
	var sc: float = f.mesh.scale.x
	var meta: Dictionary = Game.fruit_meta.get(f.kind, {})
	var offs: Dictionary = meta.get("offsets", {})
	var m: Dictionary = meshes.get(f.kind, {})
	for side in ["top", "bot"]:
		if not m.has(side):
			continue
		var p := Fruit.new()
		p.is_piece = true
		p.mesh = MeshInstance3D.new()
		p.mesh.mesh = m[side]
		p.mesh.scale = Vector3.ONE * sc
		p.add_child(p.mesh)
		var s := 1.0 if side == "top" else -1.0
		# local +Y (away from the cut) = +-n, tilted so the cut face turns toward the camera
		var y := n.rotated(dir, -0.85 * s)
		var z := dir.cross(y).normalized()
		var basis := Basis(dir, y, z).orthonormalized()
		var o: Array = offs.get(side, [0, 0.1 * s, 0])
		p.transform = Transform3D(basis, pos + basis * (Vector3(o[0], o[1], o[2]) * sc))
		p.vel = f.vel * 0.6 + n * s * (1.6 + (2.0 if big else 0.0)) + dir * 0.6 + Vector3(0, 0.6, 0)
		p.spin = dir * s * rng.randf_range(0.6, 1.4) + Vector3(0, 0, rng.randf_range(-1.2, 1.2))
		add_child(p)
		pieces.append(p)
	var front := pos + Vector3(0, 0, f.radius + 0.2)
	_burst(front, juice, 26 if not big else 80, 1.0 if not big else 2.5)
	_flash_streak(front, dir2, juice, 2.2 * (2.0 if big else 1.0))
	_add_splat(pos, juice, 1.0 if not big else 3.0)
	Sfx.play("slice", rng.randf_range(0.9, 1.15), -2.0)
	Sfx.play("squish", rng.randf_range(0.85, 1.2), -5.0)
	fruits.erase(f)
	f.queue_free()


func _finish_multi(f: Fruit) -> void:
	var bonus := f.hits * 3 * (2 if double_t > 0.0 else 1)
	_popup(Game.tr_("hits") % f.hits, f.global_position + Vector3(0, 1.0, 0.8), Color(1, 0.75, 0.3), 1.5)
	multi_done.emit(f.hits, bonus)
	f.vel = Vector3(0, 2, 0)
	_slice(f, Vector2(1, -0.3), true)
	Sfx.play("firework", 1.0, -3.0)
	shake = 0.3


func _activate(kind: String, at: Vector3) -> void:
	special.emit(kind)
	Sfx.play("powerup")
	_ring(at, Color(1, 1, 1), 3.0)
	match kind:
		"freeze":
			freeze_t = 4.5
			Sfx.play("freeze")
			_popup(Game.tr_("freeze"), at + Vector3(0, 1, 1), Color(0.6, 0.9, 1.0), 1.0)
		"double":
			double_t = 8.0
			_popup(Game.tr_("double"), at + Vector3(0, 1, 1), Color(1, 0.85, 0.3), 1.0)
		"frenzy":
			frenzy_t = 3.2
			frenzy_spawn = 0.3
			_popup(Game.tr_("frenzy"), at + Vector3(0, 1, 1), Color(1, 0.6, 0.9), 1.0)


func _explode(f: Fruit) -> void:
	var pos := f.global_position
	fruits.erase(f)
	f.queue_free()
	Sfx.fuse(false)
	Sfx.play("bomb", 1.0, 2.0)
	shake = 0.9
	_ring(pos, Color(1, 0.8, 0.5), 6.0)
	_burst(pos, Color(1, 0.6, 0.2), 60, 3.0, true)
	_smoke(pos)
	bomb_hit.emit(cam.unproject_position(pos))


# ------------------------------------------------------------------ fx

func _particle_mat(t: Texture2D, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = t
	return m


func _burst(pos: Vector3, color: Color, amount: int, power: float, fire := false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 1.1
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	q.material = _particle_mat(tex.spark if fire else tex.drop, fire)
	p.mesh = q
	p.direction = Vector3(0, 1, 0.3)
	p.spread = 180
	p.initial_velocity_min = 2.0 * power
	p.initial_velocity_max = 6.5 * power
	p.gravity = Vector3(0, -12, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8 if not fire else 3.0
	var g := Gradient.new()
	var c2 := color.lightened(0.25)
	g.set_color(0, Color(c2, 1.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.7, Color(color, 0.9))
	p.color_ramp = g
	p.position = pos
	add_child(p)
	p.emitting = true
	# mist puff
	var mist := Sprite3D.new()
	mist.texture = tex.glow
	mist.modulate = Color(color.lightened(0.2), 0.7)
	mist.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mist.pixel_size = 0.006 * power
	mist.position = pos
	add_child(mist)
	var t := mist.create_tween().set_parallel()
	t.tween_property(mist, "pixel_size", 0.02 * power, 0.35)
	t.tween_property(mist, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(mist.queue_free)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _flash_streak(pos: Vector3, dir2: Vector2, color: Color, length: float) -> void:
	var s := Sprite3D.new()
	s.texture = tex.streak
	s.modulate = Color(color.lightened(0.6), 1.0)
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.pixel_size = 0.01
	s.position = pos + Vector3(0, 0, 0.3)
	s.rotation.z = atan2(-dir2.y, dir2.x)
	s.scale = Vector3(length * 0.4, 0.6, 1)
	add_child(s)
	var t := s.create_tween().set_parallel()
	t.tween_property(s, "scale", Vector3(length * 0.6, 0.05, 1), 0.22)
	t.tween_property(s, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(s.queue_free)


func _add_splat(pos: Vector3, color: Color, size: float) -> void:
	var s := Sprite3D.new()
	s.texture = tex["splat_%d" % rng.randi_range(1, 4)]
	s.modulate = Color(color.darkened(0.05), 0.85)
	s.pixel_size = 0.009 * size * rng.randf_range(0.8, 1.2)
	s.position = Vector3(pos.x, pos.y, SPLAT_Z) * 1.0 + Vector3(0, 0, rng.randf() * 0.01)
	s.rotation.z = rng.randf() * TAU
	s.shaded = false
	add_child(s)
	splats.append(s)
	var t := s.create_tween()
	s.scale = Vector3.ONE * 0.3
	t.tween_property(s, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.2)
	t.tween_property(s, "modulate:a", 0.0, 1.6)
	t.tween_callback(func():
		splats.erase(s)
		s.queue_free())
	while splats.size() > 18:
		var o = splats.pop_front()
		if is_instance_valid(o):
			o.queue_free()


func _ring(pos: Vector3, color: Color, size: float) -> void:
	var s := Sprite3D.new()
	s.texture = tex.ring
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = 0.002
	s.position = pos + Vector3(0, 0, 0.5)
	add_child(s)
	var t := s.create_tween().set_parallel()
	t.tween_property(s, "pixel_size", 0.012 * size, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(s, "modulate:a", 0.0, 0.45)
	t.chain().tween_callback(s.queue_free)


func _smoke(pos: Vector3) -> void:
	for i in 8:
		var s := Sprite3D.new()
		s.texture = tex.smoke
		s.modulate = Color(0.25, 0.22, 0.2, 0.8)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.01
		s.position = pos + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), 0.6)
		add_child(s)
		var t := s.create_tween().set_parallel()
		t.tween_property(s, "position", s.position + Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(0, 2), 0), 1.4)
		t.tween_property(s, "pixel_size", 0.03, 1.4)
		t.tween_property(s, "modulate:a", 0.0, 1.4)
		t.chain().tween_callback(s.queue_free)


func _popup(text: String, pos: Vector3, color: Color, size := 1.0) -> void:
	if demo:
		return
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.font_title
	l.font_size = int(96 * size)
	l.outline_size = int(22 * size)
	l.modulate = color
	l.outline_modulate = Color(0.25, 0.05, 0.02, 0.95)
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	var lines := text.split("
")
	var longest := 0
	for ln in lines:
		longest = maxi(longest, ln.length())
	var est_w := longest * l.font_size * 0.55 * l.pixel_size * 0.8
	var lim := maxf(0.0, half_w * 0.8 - est_w * 0.5)
	if est_w > half_w * 1.6:
		l.pixel_size *= half_w * 1.6 / est_w
		lim = 0.0
	l.position = Vector3(clampf(pos.x, -lim, lim), clampf(pos.y, -half_h + 0.8, half_h - 1.6), 2.0)
	add_child(l)
	l.scale = Vector3.ONE * 0.3
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "position:y", l.position.y + 0.8, 0.9)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


# ------------------------------------------------------------------ ghost blade (title demo + autotest bot)

func _bomb_near(a: Vector2, b: Vector2, margin: float) -> bool:
	for o in fruits:
		if not is_instance_valid(o) or o.kind != "bomb":
			continue
		var f: Fruit = o
		for k: float in [0.0, 0.12]:
			var wp := f.global_position + f.vel * k
			var bc := cam.unproject_position(wp)
			var br := bc.distance_to(cam.unproject_position(wp + cam.global_transform.basis.x * f.radius))
			if Geometry2D.get_closest_point_to_segment(bc, a, b).distance_to(bc) < br + margin:
				return true
	return false


func _ghost(real: float) -> void:
	if not ghost_path.is_empty():
		ghost_t += real
		while not ghost_path.is_empty() and ghost_path[0].t <= ghost_t:
			var pt: Vector2 = ghost_path.pop_front().p
			if bot and _bomb_near(last_pos, pt, 70.0):
				ghost_path.clear()
				break
			if trail.points.is_empty():
				trail.begin(pt)
				last_pos = pt
			else:
				swipe_to(pt)
		if ghost_path.is_empty():
			trail.end()
		return
	# choose the slowest (near apex) live fruit that is on screen
	var best: Fruit = null
	var best_v := 1e9
	for f: Fruit in fruits:
		if not is_instance_valid(f) or f.dead or f.kind == "bomb":
			continue
		if f == boss:
			if boss_t > 1.6:
				best = f
				break
			continue
		if f.hold > 0.0:
			best = f
			break
		if f.position.y < -half_h * 0.65 or abs(f.position.x) > half_w * 0.95:
			continue
		if f.vel.y > 3.5 and f.position.y < half_h * 0.1:
			continue
		if bot and bot_miss > 0.0 and rng.randf() < bot_miss * real * 4.0:
			continue
		var v: float = abs(f.vel.y)
		if v < best_v:
			best_v = v
			best = f
	if best == null:
		return
	var c := cam.unproject_position(best.global_position)
	var r := c.distance_to(cam.unproject_position(best.global_position + cam.global_transform.basis.x * best.radius))
	var ang := rng.randf_range(-0.9, 0.9) + (PI if rng.randf() < 0.5 else 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var a := c - d * (r + 70)
	var b := c + d * (r + 70)
	# avoid bombs near the path (now and a moment later)
	if _bomb_near(a, b, 90.0):
		return
	ghost_path.clear()
	ghost_t = 0.0
	var steps := 7
	for i in steps + 1:
		ghost_path.append({"t": i * 0.016, "p": a.lerp(b, float(i) / steps)})
	trail.points.clear()
