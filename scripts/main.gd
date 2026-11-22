extends Node
## Screens (title, modes, world/level select, blades, settings), the match rules and HUD, results, autotest.

var arena: Arena
var ui: CanvasLayer
var root: Control
var screen: Control
var hud: Control
var overlay: Control
var frost: TextureRect
var flash: ColorRect
var popup_layer: Control
var screen_name := ""

# match
var mode := ""            # level, classic, arcade, zen
var L := {}
var running := false
var ended := false
var paused := false
var score := 0
var drops := 0
var progress := 0
var combos := 0
var time_left := 0.0
var elapsed := 0.0
var lives := 3
var waiting_start := false
var result := {}
var world_view := 0
var last_level := 0

# hud refs
var lbl_score: Label
var lbl_best: Label
var lbl_goal: Label
var goal_icon: TextureRect
var lbl_timer: Label
var lives_box: HBoxContainer
var boss_bar: ProgressBar
var power_box: VBoxContainer
var safe_top := 0.0

var log_lines: PackedStringArray = []
var fails := 0


func _ready() -> void:
	UiKit.init_theme()
	arena = Arena.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	ui = CanvasLayer.new()
	ui.layer = 5
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	root = Control.new()
	root.theme = UiKit.theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	frost = TextureRect.new()
	frost.texture = load("res://assets/textures/fx/frost.png")
	frost.set_anchors_preset(Control.PRESET_FULL_RECT)
	frost.stretch_mode = TextureRect.STRETCH_SCALE
	frost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost.modulate.a = 0.0
	root.add_child(frost)
	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popup_layer)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	arena.sliced.connect(_on_sliced)
	arena.missed.connect(_on_missed)
	arena.combo.connect(_on_combo)
	arena.bomb_hit.connect(_on_bomb)
	arena.special.connect(_on_special)
	arena.multi_done.connect(_on_multi)
	arena.boss_hit.connect(_on_boss_hit)
	arena.boss_dead.connect(_on_boss_dead)
	arena.stroke_started.connect(_on_stroke)
	get_viewport().size_changed.connect(_relayout)
	_apply_ui_scale()
	var sa := DisplayServer.get_display_safe_area()
	var ss := DisplayServer.screen_get_size()
	if ss.y > 0 and OS.has_feature("mobile"):
		safe_top = float(sa.position.y) / float(ss.y) * get_viewport().get_visible_rect().size.y
	world_view = int(Game.save.get("last_world", 0))
	if Game.args.has("autotest"):
		_autotest()
	elif Game.args.has("cardshot"):
		_cardshot(int(Game.args.cardshot))
	elif Game.args.has("level"):
		start_level(int(Game.args.level) - 1)
	else:
		show_title()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		Sfx.start_music()
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if running and not paused:
			pause_game()
	if waiting_start and ev is InputEventMouseButton and ev.pressed:
		_begin_match()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if running and not paused:
			pause_game()
		elif screen_name in ["levels", "modes", "blades", "settings"]:
			show_title()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if running and not paused and not Game.args.has("autotest"):
			pause_game()


func vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func is_landscape() -> bool:
	return vs().x > vs().y * 1.1


## Landscape windows: the 720x1280 base would shrink the UI by height, so scale it back up.
func _apply_ui_scale() -> void:
	var ws := get_window().size
	var a := float(ws.x) / maxf(1.0, float(ws.y))
	var f := clampf(a * 0.95, 1.0, 1.7) if a > 1.05 else 1.0
	if absf(get_window().content_scale_factor - f) > 0.01:
		get_window().content_scale_factor = f


func _relayout() -> void:
	_apply_ui_scale()
	match screen_name:
		"title":
			show_title()
		"levels":
			show_levels(world_view)
		"modes":
			show_modes()
		"blades":
			show_blades()
		"settings":
			show_settings()


# ------------------------------------------------------------------ screens helpers

func _clear_screen() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(screen)
	root.move_child(screen, popup_layer.get_index())


func _clear_hud() -> void:
	if hud and is_instance_valid(hud):
		hud.queue_free()
	hud = null


func _margin(c: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", int(l))
	m.add_theme_constant_override("margin_top", int(t + safe_top))
	m.add_theme_constant_override("margin_right", int(r))
	m.add_theme_constant_override("margin_bottom", int(b))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


func _vbox(sep := 18) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _hbox(sep := 18) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _icon(kind: String, d := 64.0) -> TextureRect:
	var t := TextureRect.new()
	var p := "res://assets/ui/fruits/%s.png" % kind
	if ResourceLoader.exists(p):
		t.texture = load(p)
	t.custom_minimum_size = Vector2(d, d)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Text followed by a drawn star (the fonts have no ★ glyph, and the web build has no fallback font).
func _star_label(text: String, size: int, color: Color) -> HBoxContainer:
	var h := _hbox(6)
	h.add_child(UiKit.label(text, size, color, maxi(5, size / 5)))
	h.add_child(UiKit.Star.new(size * 0.95, true))
	return h


func _logo(size := 1.0) -> VBoxContainer:
	var v := _vbox(-34)
	var a := UiKit.label(Game.tr_("title1"), int(104 * size), Color(1.0, 0.86, 0.3), 22, true)
	var b := UiKit.label(Game.tr_("title2"), int(128 * size), Color(1.0, 0.45, 0.2), 24, true)
	for l in [a, b]:
		l.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.02))
		l.add_theme_constant_override("shadow_offset_y", 10)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	v.add_child(a)
	v.add_child(b)
	return v


func _music_for(w: int, boss := false) -> void:
	Sfx.set_track("swords" if boss else ("tropical" if w in [1, 4, 5] else "chipnese"))


func _demo_world(w: int) -> void:
	_music_for(0)
	running = false
	ended = false
	_clear_hud()
	arena.paused = false
	get_tree().paused = false
	arena.clear_all()
	arena.set_world(w)
	arena.demo = true
	arena.bot = false
	arena.trail.apply_blade()
	arena.start({"speed": 0.85, "interval": 1.3, "wave": [1, 3], "bombs": 0.0, "special": 0.06, "fruits": Game.WORLDS[w].fruits,
		"specials": ["goldapple"]})


# ------------------------------------------------------------------ title

func show_title() -> void:
	screen_name = "title"
	if mode != "" or not arena.demo:
		mode = ""
		_demo_world(world_view)
		if ResourceLoader.exists("res://assets/backgrounds/title_bg.jpg"):
			arena.backdrop_mat.set_shader_parameter("tex", load("res://assets/backgrounds/title_bg.jpg"))
	_clear_screen()
	var v := _vbox(26)
	var logo := _logo(1.0 if not is_landscape() else 0.75)
	v.add_child(logo)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 260 if not is_landscape() else 30)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var play := UiKit.button(Game.tr_("play"), Color(1.0, 0.42, 0.15), Vector2(440, 124), 60)
	play.pressed.connect(func(): show_levels(Game.level(Game.highest_unlocked()).world))
	play.name = "Play"
	v.add_child(play)
	var modes := UiKit.button(Game.tr_("modes"), Color(0.3, 0.7, 0.3), Vector2(440, 104), 46)
	modes.pressed.connect(show_modes)
	v.add_child(modes)
	var row := _hbox(26)
	var bl := UiKit.IconButton.new("blade", Color(0.55, 0.35, 0.9), 104)
	bl.pressed.connect(show_blades)
	row.add_child(bl)
	var st := UiKit.IconButton.new("gear", Color(0.35, 0.5, 0.75), 104)
	st.pressed.connect(show_settings)
	row.add_child(st)
	var snd := UiKit.IconButton.new("sound", Color(0.9, 0.55, 0.2), 104)
	snd.off = not Game.save.sound
	snd.pressed.connect(func():
		Game.save.sound = not Game.save.sound
		snd.off = not Game.save.sound
		snd.queue_redraw()
		Game.save_game())
	row.add_child(snd)
	v.add_child(row)
	var stars := _star_label(Game.tr_("stars_total") % Game.total_stars(), 34, Color(1, 0.9, 0.5))
	v.add_child(stars)
	screen.add_child(_margin(v, 30, 40, 30, 40))
	UiKit.pop_in(logo, 0.05, 0.6)
	UiKit.pop_in(play, 0.2)
	UiKit.pop_in(modes, 0.28)
	UiKit.pop_in(row, 0.36)


# ------------------------------------------------------------------ modes

func show_modes() -> void:
	screen_name = "modes"
	_clear_screen()
	var v := _vbox(22)
	v.add_child(UiKit.label(Game.tr_("modes"), 84, Color(1, 0.85, 0.35), 18, true))
	for m in [["classic", Color(1.0, 0.4, 0.2), "watermelon"], ["arcade", Color(0.95, 0.7, 0.1), "goldapple"], ["zen", Color(0.3, 0.75, 0.45), "kiwi"]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(minf(600, vs().x - 60), 150)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UiKit.style_button(b, m[1], 40)
		UiKit.juice(b)
		var h := _hbox(18)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(6, 0)
		h.add_child(pad)
		h.add_child(_icon(m[2], 112))
		var tv := _vbox(0)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		var t := UiKit.label(Game.tr_(m[0]), 50, Color.WHITE, 10, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tv.add_child(t)
		var d := UiKit.label(Game.tr_(m[0] + "_d"), 24, Color(1, 0.95, 0.85), 6)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		tv.add_child(d)
		var bs := UiKit.label("%s: %d" % [Game.tr_("best"), int(Game.save.modes.get(m[0], 0))], 24, Color(1, 0.9, 0.5), 6)
		bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tv.add_child(bs)
		h.add_child(tv)
		b.add_child(h)
		var mm: String = m[0]
		b.pressed.connect(func(): start_mode(mm))
		b.name = mm
		v.add_child(b)
		UiKit.pop_in(b, 0.05 * v.get_child_count())
	var back := UiKit.IconButton.new("back", Color(0.45, 0.4, 0.55), 100)
	back.pressed.connect(show_title)
	v.add_child(back)
	screen.add_child(_margin(v, 24, 40, 24, 40))


# ------------------------------------------------------------------ levels

func show_levels(w: int) -> void:
	screen_name = "levels"
	world_view = clampi(w, 0, Game.WORLDS.size() - 1)
	Game.save.last_world = world_view
	if mode != "" or not arena.demo:
		mode = ""
		_demo_world(world_view)
	else:
		arena.set_world(world_view)
		arena.cfg.fruits = Game.WORLDS[world_view].fruits
	_clear_screen()
	var W: Dictionary = Game.WORLDS[world_view]
	var v := _vbox(16)
	var head := _hbox(14)
	var prev := UiKit.IconButton.new("back", W.color, 92)
	prev.disabled = world_view == 0
	prev.pressed.connect(func(): show_levels(world_view - 1))
	head.add_child(prev)
	var tv := _vbox(-6)
	var wn := UiKit.label(Game.tr_("world_" + W.id), 56 if vs().x > 640 else 46, Color(1, 0.92, 0.6), 14, true)
	wn.custom_minimum_size = Vector2(400, 0)
	tv.add_child(wn)
	var got := 0
	for i in Game.LEVELS_PER_WORLD:
		got += Game.stars_of(world_view * Game.LEVELS_PER_WORLD + i)
	tv.add_child(_star_label("%d / %d" % [got, Game.LEVELS_PER_WORLD * 3], 30, Color(1, 0.85, 0.35)))
	head.add_child(tv)
	var nxt := UiKit.IconButton.new("next", W.color, 92)
	var first_next := (world_view + 1) * Game.LEVELS_PER_WORLD
	nxt.disabled = world_view >= Game.WORLDS.size() - 1 or not Game.unlocked(first_next)
	nxt.pressed.connect(func(): show_levels(world_view + 1))
	head.add_child(nxt)
	v.add_child(head)
	var cols := 5 if is_landscape() else 4
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	var avail_h := vs().y - 330.0 - safe_top
	var bsize := clampf(minf((vs().x - 80) / cols - 16, avail_h / ceil(Game.LEVELS_PER_WORLD / float(cols)) - 16), 90, 150)
	for i in Game.LEVELS_PER_WORLD:
		var n := world_view * Game.LEVELS_PER_WORLD + i
		grid.add_child(_level_button(n, bsize, W.color))
	var center := CenterContainer.new()
	center.add_child(grid)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(center)
	var row := _hbox(20)
	var home := UiKit.IconButton.new("home", Color(0.45, 0.4, 0.55), 96)
	home.pressed.connect(show_title)
	row.add_child(home)
	v.add_child(row)
	screen.add_child(_margin(v, 20, 30, 20, 30))
	Game.save_game()


func _level_button(n: int, d: float, color: Color) -> Control:
	var L_: Dictionary = Game.level(n)
	var b := Button.new()
	b.custom_minimum_size = Vector2(d, d)
	b.name = "L%d" % (n + 1)
	var open := Game.unlocked(n)
	var boss: bool = L_.goal == "boss"
	var c := color if not boss else Color(0.85, 0.2, 0.25)
	UiKit.style_button(b, c if open else Color(0.25, 0.22, 0.3), int(d * 0.28))
	b.disabled = not open
	UiKit.juice(b)
	var v := _vbox(0)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	if boss:
		var ic := _icon(L_.boss, d * 0.42)
		ic.modulate = Color(1, 1, 1) if open else Color(0.4, 0.4, 0.4)
		v.add_child(ic)
	else:
		v.add_child(UiKit.label(str(L_.num), int(d * 0.36), Color.WHITE if open else Color(0.6, 0.55, 0.65), 8))
	if open:
		v.add_child(UiKit.star_row(Game.stars_of(n), d * 0.2))
	else:
		var lk := UiKit.Lock.new(d * 0.26)
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(lk)
		v.add_child(cc)
	b.add_child(v)
	b.pressed.connect(func(): start_level(n))
	return b


# ------------------------------------------------------------------ blades

func show_blades() -> void:
	screen_name = "blades"
	_clear_screen()
	var v := _vbox(16)
	v.add_child(UiKit.label(Game.tr_("blades"), 80, Color(1, 0.85, 0.35), 18, true))
	v.add_child(_star_label(Game.tr_("stars_total") % Game.total_stars(), 32, Color(1, 0.9, 0.5)))
	var grid := GridContainer.new()
	grid.columns = 4 if is_landscape() else 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	var total := Game.total_stars()
	for b in Game.BLADES:
		var open: bool = total >= int(b.stars) or Game.args.has("unlock")
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 150)
		btn.name = "blade_" + b.id
		var sel: bool = Game.save.blade == b.id
		UiKit.style_button(btn, b.glow.darkened(0.2) if open else Color(0.25, 0.22, 0.3), 36)
		if sel:
			btn.add_theme_stylebox_override("normal", UiKit.box(b.glow.darkened(0.35), Color(1, 0.95, 0.6), 36, 7, 0.9))
		UiKit.juice(btn)
		var bv := _vbox(4)
		bv.set_anchors_preset(Control.PRESET_FULL_RECT)
		bv.add_child(_swoosh(b, open))
		bv.add_child(UiKit.label(Game.tr_("blade_" + b.id), 34, Color.WHITE if open else Color(0.7, 0.65, 0.75), 8))
		var sub := Game.tr_("selected") if sel else (Game.tr_("select") if open else Game.tr_("locked") % int(b.stars))
		if open:
			bv.add_child(UiKit.label(sub, 22, Color(1, 0.92, 0.6), 5))
		else:
			bv.add_child(_star_label(sub, 22, Color(0.75, 0.7, 0.8)))
		btn.add_child(bv)
		btn.disabled = not open
		var id: String = b.id
		btn.pressed.connect(func():
			Game.save.blade = id
			Game.save_game()
			arena.trail.apply_blade()
			Sfx.play("whoosh", 1.2)
			show_blades())
		grid.add_child(btn)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(grid)
	v.add_child(cc)
	var back := UiKit.IconButton.new("back", Color(0.45, 0.4, 0.55), 100)
	back.pressed.connect(show_title)
	v.add_child(back)
	screen.add_child(_margin(v, 20, 30, 20, 30))


class Swoosh extends Control:
	var core := Color.WHITE
	var glow := Color.WHITE
	var rainbow := false
	var dim := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts: Array[Vector2] = []
		for i in 24:
			var k := i / 23.0
			pts.append(Vector2(w * (0.1 + 0.8 * k), h * (0.75 - 0.5 * sin(k * PI * 0.9))))
		for pass_ in [[22.0, 0.35], [12.0, 0.7], [4.0, 1.0]]:
			for i in pts.size() - 1:
				var k := i / 23.0
				var c := glow if pass_[1] < 1.0 else core
				if rainbow and pass_[1] < 1.0:
					c = Color.from_hsv(k, 0.85, 1.0)
				var al: float = pass_[1] * k * (0.35 if dim else 1.0)
				draw_line(pts[i], pts[i + 1], Color(c, al), pass_[0] * k + 1.0, true)


func _swoosh(b: Dictionary, open: bool) -> Control:
	var s := Swoosh.new()
	s.custom_minimum_size = Vector2(240, 60)
	s.resized.connect(s.queue_redraw)
	s.core = b.core
	s.glow = b.glow
	s.rainbow = b.id == "rainbow"
	s.dim = not open
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# ------------------------------------------------------------------ settings

func show_settings() -> void:
	screen_name = "settings"
	_clear_screen()
	var p := UiKit.panel()
	var v := _vbox(20)
	v.add_child(UiKit.label(Game.tr_("settings"), 70, Color(1, 0.85, 0.35), 16, true))
	for k in ["sound", "music"]:
		var key: String = k
		var b := UiKit.button("%s: %s" % [Game.tr_(k), "✓" if Game.save[k] else "✗"], Color(0.3, 0.6, 0.4) if Game.save[k] else Color(0.5, 0.3, 0.3), Vector2(460, 96), 40)
		b.pressed.connect(func():
			Game.save[key] = not Game.save[key]
			Game.save_game()
			Sfx.update_music()
			show_settings())
		v.add_child(b)
	var lb := UiKit.button("%s: %s" % [Game.tr_("language"), "Русский" if Game.lang == "ru" else "English"], Color(0.35, 0.45, 0.75), Vector2(460, 96), 40)
	lb.pressed.connect(func():
		Game.lang = "en" if Game.lang == "ru" else "ru"
		Game.save.lang = Game.lang
		Game.save_game()
		show_settings())
	v.add_child(lb)
	var rs := UiKit.button(Game.tr_("reset"), Color(0.6, 0.25, 0.25), Vector2(460, 90), 34)
	rs.pressed.connect(_confirm_reset)
	v.add_child(rs)
	var close := UiKit.button(Game.tr_("close"), Color(1.0, 0.5, 0.2), Vector2(300, 96), 42)
	close.pressed.connect(show_title)
	v.add_child(close)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	screen.add_child(cc)
	UiKit.pop_in(p)


func _confirm_reset() -> void:
	_clear_screen()
	var p := UiKit.panel(Color(1, 0.3, 0.3))
	var v := _vbox(24)
	v.add_child(UiKit.label(Game.tr_("reset_q"), 48, Color.WHITE, 10))
	var row := _hbox(24)
	var y := UiKit.button(Game.tr_("yes"), Color(0.8, 0.25, 0.2), Vector2(200, 96), 42)
	y.pressed.connect(func():
		Game.save.stars = {}
		Game.save.best = {}
		Game.save.modes = {"classic": 0, "arcade": 0, "zen": 0}
		Game.save.blade = "steel"
		Game.save.tutorial = false
		Game.save_game()
		arena.trail.apply_blade()
		show_settings())
	var n := UiKit.button(Game.tr_("no"), Color(0.3, 0.6, 0.4), Vector2(200, 96), 42)
	n.pressed.connect(show_settings)
	row.add_child(y)
	row.add_child(n)
	v.add_child(row)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	screen.add_child(cc)


# ------------------------------------------------------------------ match

func start_level(n: int) -> void:
	mode = "level"
	last_level = n
	L = Game.level(n)
	world_view = L.world
	_music_for(L.world, L.goal == "boss")
	_prepare_match(L.world)
	_intro_panel()


func start_mode(m: String) -> void:
	mode = m
	_music_for(world_view)
	L = {"goal": m, "world": world_view}
	_prepare_match(world_view)
	_intro_panel()


func _prepare_match(w: int) -> void:
	get_tree().paused = false
	paused = false
	arena.paused = false
	arena.clear_all()
	arena.demo = false
	arena.set_world(w)
	arena.trail.apply_blade()
	arena.stop_spawning()
	running = false
	ended = false
	score = 0
	drops = 0
	progress = 0
	combos = 0
	elapsed = 0.0
	lives = 3
	time_left = float(L.get("time", 0))
	if mode == "arcade":
		time_left = 60.0
	elif mode == "zen":
		time_left = 90.0
	screen_name = "game"
	_clear_screen()
	_build_hud()


func _intro_panel() -> void:
	var p := UiKit.panel(Game.WORLDS[L.world].color if mode == "level" else Color(1, 0.6, 0.2))
	p.name = "Intro"
	var v := _vbox(14)
	if mode == "level":
		v.add_child(UiKit.label("%s %d" % [Game.tr_("level"), L.index + 1], 64, Color(1, 0.9, 0.5), 14, true))
		v.add_child(UiKit.label(Game.tr_("world_" + Game.WORLDS[L.world].id), 30, Color(1, 0.95, 0.85), 6))
		var gh := _hbox(12)
		if L.goal == "type":
			gh.add_child(_icon(L.fruit, 86))
		elif L.goal == "boss":
			gh.add_child(_icon(L.boss, 110))
		var gl := UiKit.label(Game.goal_text(L), 40, Color.WHITE, 10)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.custom_minimum_size = Vector2(440, 0)
		gh.add_child(gl)
		v.add_child(gh)
		if L.goal in ["count", "type", "survive", "perfect"]:
			v.add_child(UiKit.label(Game.tr_("misses") % (int(L.misses) - 1), 28, Color(1, 0.75, 0.6), 6))
		if L.bombs > 0.0 and L.index < 8:
			v.add_child(UiKit.label(Game.tr_("avoid_bomb"), 28, Color(1, 0.5, 0.45), 6))
	else:
		v.add_child(UiKit.label(Game.tr_(mode), 76, Color(1, 0.9, 0.5), 16, true))
		var d := UiKit.label(Game.tr_(mode + "_d"), 32, Color.WHITE, 8)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(460, 0)
		v.add_child(d)
	var tap := UiKit.label(Game.tr_("tap_start"), 32, Color(1, 0.85, 0.4), 8)
	v.add_child(tap)
	var tw := tap.create_tween().set_loops()
	tw.tween_property(tap, "modulate:a", 0.35, 0.6)
	tw.tween_property(tap, "modulate:a", 1.0, 0.6)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(p)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(cc)
	UiKit.pop_in(p)
	waiting_start = false
	get_tree().create_timer(0.35).timeout.connect(func():
		if not running and not ended and screen_name == "game":
			waiting_start = true)


func _begin_match() -> void:
	if not waiting_start:
		return
	waiting_start = false
	var intro := screen.find_child("Intro", true, false)
	if intro:
		var t := intro.create_tween()
		t.tween_property(intro, "scale", Vector2(0.01, 0.01), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_callback(intro.get_parent().queue_free)
	var cfg := {}
	match mode:
		"level":
			cfg = {"speed": L.speed, "interval": L.interval, "wave": L.wave, "bombs": L.bombs, "special": L.special,
				"fruits": L.fruits, "specials": L.specials}
			if L.goal == "type":
				cfg.focus = L.fruit
			if L.goal == "boss":
				cfg.boss = true
				cfg.interval = L.interval * 1.4
				arena.spawn_boss(L.boss, L.target)
			if L.index == 0 and not Game.save.tutorial:
				_toast(Game.tr_("swipe"), 3.0)
		"classic":
			cfg = {"speed": 0.95, "interval": 1.5, "wave": [1, 2], "bombs": 0.08, "special": 0.0, "fruits": Game.FRUITS, "specials": []}
		"arcade":
			cfg = {"speed": 1.05, "interval": 1.1, "wave": [2, 4], "bombs": 0.12, "special": 0.12, "fruits": Game.FRUITS,
				"specials": ["goldapple", "frostberry", "starfruit", "pomegranate"]}
		"zen":
			cfg = {"speed": 1.0, "interval": 1.0, "wave": [2, 4], "bombs": 0.0, "special": 0.0, "fruits": Game.FRUITS, "specials": []}
	arena.start(cfg)
	running = true
	_update_hud()


func _process(delta: float) -> void:
	if not running or paused or ended:
		return
	elapsed += delta
	if mode == "classic":
		var k := clampf(elapsed / 150.0, 0.0, 1.0)
		arena.cfg.speed = 0.95 + 0.4 * k
		arena.cfg.interval = lerpf(1.5, 0.75, k)
		arena.cfg.wave = [1, 2 + int(4 * k)]
		arena.cfg.bombs = 0.08 + 0.12 * k
		arena.cfg.special = 0.04 if elapsed > 20 else 0.0
		arena.cfg.specials = ["goldapple", "frostberry", "starfruit"] if elapsed > 20 else []
	if time_left > 0.0 or L.has("time") or mode in ["arcade", "zen"]:
		if L.goal in ["score", "combo", "survive", "boss"] or mode in ["arcade", "zen"]:
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				if L.goal == "survive":
					_finish(true, "")
				elif mode in ["arcade", "zen"]:
					_finish(true, "time")
				else:
					_finish(false, "lose_time")
	_update_hud()


# ------------------------------------------------------------------ events

func _on_stroke() -> void:
	pass


func _on_sliced(kind: String, pts: int, _pos: Vector2) -> void:
	if not running or ended:
		return
	score += pts
	if kind not in ["boss", "multi"]:
		Game.save.sliced = int(Game.save.sliced) + 1
		if L.goal in ["count", "perfect"]:
			progress += 1
		elif L.goal == "type" and kind == L.get("fruit", ""):
			progress += 1
	if L.goal == "score" and score >= int(L.target):
		_finish(true, "")
	elif L.goal in ["count", "perfect", "type"] and progress >= int(L.target):
		_finish(true, "")
	if mode == "level" and L.index == 0 and not Game.save.tutorial and progress >= 3:
		Game.save.tutorial = true
	_bump(lbl_score)
	_update_hud()


func _on_missed(_kind: String, pos: Vector2) -> void:
	if not running or ended or mode in ["arcade", "zen"]:
		return
	if mode == "level" and L.goal in ["score", "combo", "boss"]:
		return
	drops += 1
	_miss_mark(pos)
	_update_hud()
	var limit := 3 if mode == "classic" else int(L.get("misses", 3))
	if drops >= limit:
		_finish(false, "lose_miss" if mode == "level" else "game_over")


func _on_combo(count: int, bonus: int, _pos: Vector2) -> void:
	if not running or ended:
		return
	score += bonus
	combos += 1
	if L.goal == "combo" and combos >= int(L.target):
		_finish(true, "")
	elif L.goal == "score" and score >= int(L.target):
		_finish(true, "")
	_update_hud()


func _on_bomb(_pos: Vector2) -> void:
	_flash(Color(1, 1, 1), 0.9)
	if not running or ended:
		return
	if mode == "arcade":
		score = maxi(0, score - 15)
		_toast("-15", 1.0)
		_update_hud()
		return
	arena.slowmo(1.2, 0.2)
	_finish(false, "lose_bomb")


func _on_special(kind: String) -> void:
	if kind == "freeze":
		var t := frost.create_tween()
		t.tween_property(frost, "modulate:a", 0.85, 0.25)
		t.tween_interval(3.9)
		t.tween_property(frost, "modulate:a", 0.0, 0.5)
		_flash(Color(0.6, 0.85, 1.0), 0.5)
	elif kind == "double":
		_flash(Color(1, 0.85, 0.3), 0.4)
	elif kind == "frenzy":
		_flash(Color(1, 0.6, 0.9), 0.4)
	_power_pill(kind)


func _on_multi(_hits: int, bonus: int) -> void:
	if running and not ended:
		score += bonus
		_update_hud()


func _on_boss_hit(hp: int, max_hp: int) -> void:
	if boss_bar:
		boss_bar.max_value = max_hp
		boss_bar.value = hp


func _on_boss_dead() -> void:
	if running and not ended:
		score += 100
		_finish(true, "")


# ------------------------------------------------------------------ end

func _finish(win: bool, reason: String) -> void:
	if ended:
		return
	ended = true
	running = false
	arena.stop_spawning()
	Sfx.fuse(false)
	var stars := 0
	var new_best := false
	if mode == "level":
		if win:
			stars = _stars()
			Game.record(L.index, stars, score)
	else:
		var prev := int(Game.save.modes.get(mode, 0))
		if score > prev:
			Game.save.modes[mode] = score
			new_best = true
			Game.save_game()
	result = {"win": win, "reason": reason, "stars": stars, "score": score, "new_best": new_best}
	_log("finish %s win=%s reason=%s score=%d stars=%d drops=%d" % [mode, win, reason, score, stars, drops])
	if win or mode != "level":
		get_tree().create_timer(0.5).timeout.connect(func(): Sfx.play("win" if win or new_best else "fail"))
	else:
		Sfx.play("fail", 1.0, -2.0)
	var t := get_tree().create_timer(1.3 if reason != "lose_bomb" else 1.6)
	t.timeout.connect(_show_result)


func _stars() -> int:
	match L.goal:
		"count", "type", "survive":
			var lim := int(L.misses) - 1
			if drops == 0:
				return 3
			return 2 if drops <= maxi(1, lim / 2) else 1
		"perfect":
			return 3
		_:
			var total := float(L.get("time", 60))
			var k := time_left / total
			return 3 if k >= 0.3 else (2 if k >= 0.12 else 1)


func _show_result() -> void:
	_clear_hud()
	_clear_screen()
	screen_name = "result"
	var win: bool = result.win
	var p := UiKit.panel(Color(1.0, 0.7, 0.2) if win else Color(0.8, 0.3, 0.3))
	p.name = "Result"
	var v := _vbox(16)
	var title := ""
	if mode == "level":
		title = Game.tr_("win") if win else Game.tr_("lose")
	else:
		title = Game.tr_("time_up") if result.reason == "time" else Game.tr_("game_over")
	v.add_child(UiKit.label(title, 66, Color(1, 0.9, 0.45) if win else Color(1, 0.6, 0.5), 14, true))
	if not win and result.reason in ["lose_bomb", "lose_miss", "lose_time"]:
		v.add_child(UiKit.label(Game.tr_(result.reason), 30, Color(1, 0.85, 0.8), 6))
	if mode == "level" and win:
		var row := _hbox(10)
		var stars_nodes := []
		for k in 3:
			var s := UiKit.Star.new(104, k < int(result.stars))
			row.add_child(s)
			stars_nodes.append(s)
		v.add_child(row)
		for k in stars_nodes.size():
			UiKit.pop_in(stars_nodes[k], 0.25 + k * 0.22, 0.5)
			if k < int(result.stars):
				get_tree().create_timer(0.3 + k * 0.22).timeout.connect(func(): Sfx.play("star", 1.0 + k * 0.12))
		_confetti()
	var sc := UiKit.label("%s: 0" % Game.tr_("score"), 48, Color.WHITE, 10)
	v.add_child(sc)
	var tw := sc.create_tween()
	tw.tween_method(func(x: float): sc.text = "%s: %d" % [Game.tr_("score"), int(x)], 0.0, float(result.score), 0.8)
	var best := int(Game.save.best.get(str(L.get("index", -1)), 0)) if mode == "level" else int(Game.save.modes.get(mode, 0))
	v.add_child(UiKit.label("%s: %d" % [Game.tr_("best"), best], 30, Color(1, 0.9, 0.6), 6))
	if result.new_best:
		var nb := UiKit.label(Game.tr_("new_best"), 40, Color(1, 0.8, 0.2), 10, true)
		v.add_child(nb)
		UiKit.pop_in(nb, 0.9)
		_confetti()
	var row2 := _hbox(16)
	if mode == "level":
		var lv := UiKit.IconButton.new("levels", Color(0.45, 0.4, 0.55), 100)
		lv.pressed.connect(func(): show_levels(L.world))
		row2.add_child(lv)
		var rt := UiKit.IconButton.new("restart", Color(0.35, 0.55, 0.85), 100)
		rt.name = "Retry"
		rt.pressed.connect(func(): start_level(L.index))
		row2.add_child(rt)
		if win and L.index + 1 < Game.levels.size():
			var nx := UiKit.button(Game.tr_("next"), Color(1.0, 0.45, 0.15), Vector2(230, 100), 44)
			nx.name = "Next"
			nx.pressed.connect(func(): start_level(L.index + 1))
			row2.add_child(nx)
	else:
		var hm := UiKit.IconButton.new("home", Color(0.45, 0.4, 0.55), 100)
		hm.pressed.connect(show_title)
		row2.add_child(hm)
		var rt := UiKit.button(Game.tr_("retry"), Color(1.0, 0.45, 0.15), Vector2(260, 100), 44)
		rt.name = "Retry"
		var m := mode
		rt.pressed.connect(func(): start_mode(m))
		row2.add_child(rt)
	v.add_child(row2)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	screen.add_child(cc)
	UiKit.pop_in(p)


# ------------------------------------------------------------------ pause

func pause_game() -> void:
	if paused:
		return
	paused = true
	get_tree().paused = true
	arena.paused = true
	Sfx.fuse(false)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.name = "PauseLayer"
	var p := UiKit.panel()
	var v := _vbox(18)
	v.add_child(UiKit.label(Game.tr_("paused"), 70, Color(1, 0.9, 0.5), 14, true))
	var res := UiKit.button(Game.tr_("resume"), Color(1.0, 0.45, 0.15), Vector2(380, 104), 48)
	res.pressed.connect(func():
		dim.queue_free()
		paused = false
		arena.paused = false
		get_tree().paused = false)
	v.add_child(res)
	var rt := UiKit.button(Game.tr_("retry"), Color(0.35, 0.55, 0.85), Vector2(380, 96), 42)
	rt.pressed.connect(func():
		dim.queue_free()
		if mode == "level":
			start_level(L.index)
		else:
			start_mode(mode))
	v.add_child(rt)
	var mn := UiKit.button(Game.tr_("menu"), Color(0.45, 0.4, 0.55), Vector2(380, 96), 42)
	mn.pressed.connect(func():
		dim.queue_free()
		paused = false
		get_tree().paused = false
		if mode == "level":
			show_levels(L.world)
		else:
			show_title())
	v.add_child(mn)
	var row := _hbox(18)
	for k in ["sound", "music"]:
		var key: String = k
		var b := UiKit.IconButton.new(k, Color(0.9, 0.55, 0.2), 92)
		b.off = not Game.save[k]
		b.pressed.connect(func():
			Game.save[key] = not Game.save[key]
			b.off = not Game.save[key]
			b.queue_redraw()
			Sfx.update_music()
			Game.save_game())
		row.add_child(b)
	v.add_child(row)
	p.add_child(v)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(p)
	dim.add_child(cc)
	root.add_child(dim)
	UiKit.pop_in(p, 0.0, 0.3)


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	_clear_hud()
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	root.move_child(hud, screen.get_index() if screen and is_instance_valid(screen) and not screen.is_queued_for_deletion() else popup_layer.get_index())
	var top := _hbox(10)
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22
	top.offset_right = -22
	top.offset_top = 16 + safe_top
	top.offset_bottom = 150 + safe_top
	var left := _vbox(-8)
	left.alignment = BoxContainer.ALIGNMENT_BEGIN
	lbl_score = UiKit.label("0", 76, Color(1, 0.9, 0.45), 16, true)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(lbl_score)
	var best := int(Game.save.best.get(str(L.get("index", -1)), 0)) if mode == "level" else int(Game.save.modes.get(mode, 0))
	lbl_best = UiKit.label("%s: %d" % [Game.tr_("best"), best], 24, Color(1, 0.95, 0.85), 6)
	lbl_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(lbl_best)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	var mid := _vbox(0)
	var gh := _hbox(6)
	goal_icon = _icon(L.get("fruit", "apple"), 56)
	goal_icon.visible = L.goal in ["type"]
	gh.add_child(goal_icon)
	lbl_goal = UiKit.label("", 42, Color.WHITE, 10)
	gh.add_child(lbl_goal)
	mid.add_child(gh)
	lbl_timer = UiKit.label("", 36, Color(1, 0.95, 0.8), 8)
	mid.add_child(lbl_timer)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(mid)
	var right := _hbox(8)
	right.alignment = BoxContainer.ALIGNMENT_END
	lives_box = _hbox(2)
	right.add_child(lives_box)
	var pb := UiKit.IconButton.new("pause", Color(0.45, 0.4, 0.55), 84)
	pb.name = "Pause"
	pb.pressed.connect(pause_game)
	right.add_child(pb)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	hud.add_child(top)
	if L.goal == "boss":
		boss_bar = ProgressBar.new()
		boss_bar.show_percentage = false
		boss_bar.max_value = L.target
		boss_bar.value = L.target
		boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		boss_bar.offset_left = 120
		boss_bar.offset_right = -120
		boss_bar.offset_top = 160 + safe_top
		boss_bar.offset_bottom = 190 + safe_top
		boss_bar.add_theme_stylebox_override("background", UiKit.box(Color(0.1, 0.03, 0.03, 0.8), Color(1, 0.8, 0.5), 15, 3))
		var fill := UiKit.box(Color(0.95, 0.2, 0.25), Color(1, 0.6, 0.5), 15, 0)
		boss_bar.add_theme_stylebox_override("fill", fill)
		hud.add_child(boss_bar)
	else:
		boss_bar = null
	power_box = _vbox(8)
	power_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	power_box.offset_top = -170
	power_box.offset_bottom = -40
	power_box.offset_left = -200
	power_box.offset_right = 200
	hud.add_child(power_box)
	_update_hud()


func _update_hud() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	lbl_score.text = str(score)
	var goal := ""
	match L.goal:
		"count", "perfect", "type":
			goal = "%d / %d" % [progress, int(L.target)]
		"score":
			goal = "%d / %d" % [mini(score, int(L.target)), int(L.target)]
		"combo":
			goal = "%s %d / %d" % [Game.tr_("combo"), combos, int(L.target)]
		"boss":
			goal = Game.tr_("boss_hp")
	lbl_goal.text = goal
	var timed: bool = mode in ["arcade", "zen"] or L.goal in ["score", "combo", "survive", "boss"]
	lbl_timer.visible = timed
	if timed:
		var s := int(ceil(time_left))
		lbl_timer.text = "%d:%02d" % [s / 60, s % 60]
		lbl_timer.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if time_left < 8.0 else Color(1, 0.95, 0.8))
	# lives / drops
	var limit := 0
	if mode == "classic":
		limit = 3
	elif mode == "level" and L.goal in ["count", "type", "survive", "perfect"]:
		limit = int(L.misses)
	if lives_box.get_child_count() != limit:
		for c in lives_box.get_children():
			c.queue_free()
		for i in limit:
			var x := MissMark.new()
			x.custom_minimum_size = Vector2(46, 46)
			lives_box.add_child(x)
	for i in lives_box.get_child_count():
		var x: MissMark = lives_box.get_child(i)
		var on := i < drops
		if x.on != on:
			x.on = on
			x.queue_redraw()
			if on:
				UiKit.pop_in(x, 0.0, 0.3)
	# power-up timers
	for c in power_box.get_children():
		var k: String = c.get_meta("kind")
		var left := arena.freeze_t if k == "freeze" else (arena.double_t if k == "double" else arena.frenzy_t)
		if left <= 0.0:
			c.queue_free()
		else:
			(c.get_node("L") as Label).text = "%s %.0f" % [Game.tr_(k), ceil(left)]


class MissMark extends Control:
	var on := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.38
		var col := Color(1, 0.2, 0.2) if on else Color(1, 1, 1, 0.35)
		var w := 9.0 if on else 6.0
		if on:
			draw_line(c + Vector2(-r, -r) * 1.08, c + Vector2(r, r) * 1.08, Color(0.3, 0, 0, 0.8), w + 6, true)
			draw_line(c + Vector2(r, -r) * 1.08, c + Vector2(-r, r) * 1.08, Color(0.3, 0, 0, 0.8), w + 6, true)
		draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, w, true)
		draw_line(c + Vector2(r, -r), c + Vector2(-r, r), col, w, true)


func _power_pill(kind: String) -> void:
	if power_box == null or not is_instance_valid(power_box):
		return
	for c in power_box.get_children():
		if c.get_meta("kind") == kind:
			return
	var p := UiKit.pill(30)
	(p.get_node("L") as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.set_meta("kind", kind)
	power_box.add_child(p)
	UiKit.pop_in(p)


func _bump(l: Control) -> void:
	if l == null or not is_instance_valid(l):
		return
	l.pivot_offset = l.size * Vector2(0.0, 0.5)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2(1.15, 1.15), 0.05)
	t.tween_property(l, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func _toast(text: String, dur: float) -> void:
	var p := UiKit.pill(36)
	var lb := p.get_node("L") as Label
	lb.text = text
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	popup_layer.add_child(p)
	p.reset_size()
	p.position = Vector2((vs().x - p.size.x) * 0.5, vs().y * 0.64)
	UiKit.pop_in(p)
	var t := p.create_tween()
	t.tween_interval(dur)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)


func _flash(c: Color, a: float) -> void:
	flash.color = Color(c, a)
	var t := flash.create_tween()
	t.tween_property(flash, "color:a", 0.0, 0.45)


func _miss_mark(pos: Vector2) -> void:
	var m := MissMark.new()
	m.on = true
	m.size = Vector2(70, 70)
	m.position = Vector2(clampf(pos.x - 35, 10, vs().x - 80), vs().y - 110)
	popup_layer.add_child(m)
	UiKit.pop_in(m, 0.0, 0.3)
	var t := m.create_tween()
	t.tween_interval(0.8)
	t.tween_property(m, "modulate:a", 0.0, 0.4)
	t.tween_callback(m.queue_free)


func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.amount = 90
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.4
	p.position = Vector2(vs().x * 0.5, vs().y * 0.3)
	p.direction = Vector2(0, -1)
	p.spread = 80
	p.initial_velocity_min = 350
	p.initial_velocity_max = 750
	p.gravity = Vector2(0, 700)
	p.scale_amount_min = 6
	p.scale_amount_max = 12
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.3, 0.3))
	g.set_color(1, Color(0.3, 0.6, 1))
	g.add_point(0.25, Color(1, 0.85, 0.2))
	g.add_point(0.5, Color(0.4, 0.95, 0.4))
	g.add_point(0.75, Color(1, 0.4, 0.9))
	p.color_initial_ramp = g
	popup_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ autotest

func _log(s: String) -> void:
	print("AUTOTEST ", s)
	log_lines.append(s)


func _check(ok: bool, what: String) -> void:
	if ok:
		_log("ok   " + what)
	else:
		fails += 1
		_log("FAIL " + what)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/game"))
	var pre := "land_" if is_landscape() else ""
	img.save_png("res://renders/game/%s%s.png" % [pre, name])


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _tap_start() -> void:
	waiting_start = true
	_begin_match()


func _play_level_bot(n: int, timeout: float, shot := "") -> bool:
	start_level(n)
	await _wait(0.6)
	arena.bot = true
	arena.bot_miss = 0.0
	_tap_start()
	if n == 0:
		await _wait(1.2)
		await _shot("06b_tutorial")
	var t := 0.0
	var shot_done := false
	while not ended and t < timeout:
		await _wait(0.25)
		t += 0.25
		if shot != "" and not shot_done and t > 5.0 and arena.pieces.size() > 0:
			shot_done = true
			await _shot(shot)
	arena.bot = false
	await _wait(1.8)
	return ended and result.get("win", false)


## Portal / store image: the bot plays a level of world W, HUD hidden; shots renders/card_*.png, then quit.
func _cardshot(w: int) -> void:
	start_level(w * Game.LEVELS_PER_WORLD + 6)
	await _wait(0.5)
	hud.visible = false
	arena.quiet = true
	arena.cam.position.z = 6.2
	arena._on_resize()
	arena.bot = true
	_tap_start()
	var k := 0
	var t := 0.0
	while k < 8 and t < 40.0:
		await _wait(0.1)
		t += 0.1
		if t > 3.0 and arena.pieces.size() >= 4 and arena.splats.size() >= 3:
			await _shot("card_%d" % k)
			k += 1
			await _wait(0.9)
	get_tree().quit()


func _autotest() -> void:
	_log("start")
	Game.save.tutorial = false
	show_title()
	await _wait(3.5)
	await _shot("01_title")
	show_modes()
	await _wait(0.8)
	await _shot("02_modes")
	for w in Game.WORLDS.size():
		show_levels(w)
		await _wait(1.6)
		await _shot("03_levels_%d" % (w + 1))
	show_blades()
	await _wait(0.8)
	await _shot("04_blades")
	show_settings()
	await _wait(0.6)
	await _shot("05_settings")
	# level 1 by the bot
	start_level(0)
	await _wait(0.8)
	await _shot("06_intro")
	await _wait(0.2)
	var won := await _play_level_bot(0, 60.0, "07_play_w1")
	_check(won, "bot wins level 1 (score %d)" % score)
	await _shot("08_result_win")
	_check(Game.stars_of(0) > 0, "level 1 recorded stars %d" % Game.stars_of(0))
	# bomb loses
	start_level(4)
	await _wait(0.5)
	_tap_start()
	arena.stop_spawning()
	await _wait(0.3)
	var b := arena.launch("bomb", 0.0)
	b.position = Vector3(0, 0, 0)
	b.vel = Vector3.ZERO
	await _wait(0.1)
	var c := arena.cam.unproject_position(b.global_position)
	arena.trail.begin(c - Vector2(150, 20))
	arena.last_pos = c - Vector2(150, 20)
	arena.swipe_to(c + Vector2(150, 20))
	await _wait(0.4)
	await _shot("09_bomb")
	_check(ended and not result.win and result.reason == "lose_bomb", "slicing a bomb loses the level")
	await _wait(1.8)
	await _shot("10_result_lose")
	# specials
	start_mode("arcade")
	await _wait(0.5)
	_tap_start()
	arena.stop_spawning()
	for k in ["frostberry", "goldapple", "starfruit"]:
		var f := arena.launch(k, 0.0)
		f.position = Vector3(0, 0.5, 0)
		f.vel = Vector3(0, 0.5, 0)
		await _wait(0.05)
		var p := arena.cam.unproject_position(f.global_position)
		arena.last_pos = p - Vector2(160, 0)
		arena.trail.begin(arena.last_pos)
		arena.swipe_to(p + Vector2(160, 0))
		await _wait(0.5)
		if k == "frostberry":
			_check(arena.freeze_t > 0.0, "frost berry freezes time")
			await _shot("11_freeze")
		elif k == "goldapple":
			_check(arena.double_t > 0.0, "golden apple doubles points")
		else:
			_check(arena.frenzy_t > 0.0, "star fruit starts a frenzy")
			arena.spawning = true
			await _wait(1.0)
			await _shot("12_frenzy")
			arena.spawning = false
	var pom := arena.launch("pomegranate", 0.0)
	pom.position = Vector3(0, 0.5, 0)
	pom.vel = Vector3(0, 0.3, 0)
	var multi_hits := [0]
	arena.multi_done.connect(func(h, _b): multi_hits[0] = h, CONNECT_ONE_SHOT)
	await _wait(0.05)
	for i in 10:
		var p := arena.cam.unproject_position(pom.global_position) if is_instance_valid(pom) else Vector2(360, 600)
		var d := Vector2(150, (i % 3 - 1) * 60).rotated(i * 0.7)
		arena.last_pos = p - d
		arena.trail.begin(arena.last_pos)
		arena.swipe_to(p + d)
		await _wait(0.1)
	await _shot("13_pomegranate")
	await _wait(2.0)
	_check(multi_hits[0] >= 5, "pomegranate counts %d hits" % multi_hits[0])
	# combo
	arena.freeze_t = 0.0
	var row: Array = []
	for i in 4:
		var f := arena.launch("orange", 0.0)
		f.position = Vector3(-1.5 + i * 1.0, -0.5, 0)
		f.vel = Vector3(0, 0.5, 0)
		row.append(f)
	await _wait(0.05)
	var got_combo := [0]
	arena.combo.connect(func(n, _b, _p): got_combo[0] = n, CONNECT_ONE_SHOT)
	var a0 := arena.cam.unproject_position(Vector3(-2.5, -0.45, 0))
	var a1 := arena.cam.unproject_position(Vector3(2.5, -0.45, 0))
	arena.last_pos = a0
	arena.trail.begin(a0)
	for i in 10:
		arena.swipe_to(a0.lerp(a1, (i + 1) / 10.0))
		await _wait(0.016)
	await _wait(0.6)
	_check(got_combo[0] >= 4, "4-fruit swipe makes a combo (%d)" % got_combo[0])
	await _shot("14_combo")
	# classic: dropping 3 fruit ends the game
	start_mode("classic")
	await _wait(0.4)
	_tap_start()
	arena.stop_spawning()
	for i in 3:
		var f := arena.launch("apple", -1.0 + i)
		f.vel = Vector3(0, 6.0, 0)
	var t := 0.0
	while not ended and t < 8.0:
		await _wait(0.25)
		t += 0.25
	_check(ended and drops == 3 and not result.win, "classic ends after 3 drops")
	await _wait(1.8)
	await _shot("15_classic_over")
	# boss of world 1 by the bot
	var boss_won := await _play_level_bot(19, 70.0, "16_boss")
	_check(boss_won, "bot beats the world-1 boss (score %d)" % score)
	# every world in play
	for w in Game.WORLDS.size():
		start_level(w * Game.LEVELS_PER_WORLD + 3)
		await _wait(0.4)
		arena.bot = true
		_tap_start()
		await _wait(4.5)
		await _shot("17_world_%d" % (w + 1))
		arena.bot = false
		arena.clear_all()
	# pause
	start_level(1)
	await _wait(0.4)
	_tap_start()
	await _wait(1.0)
	pause_game()
	await _wait(0.4)
	await _shot("18_pause")
	_check(get_tree().paused, "pause stops the game")
	get_tree().paused = false
	paused = false
	arena.paused = false
	_log("AUTOTEST DONE fails=%d" % fails)
	var f := FileAccess.open("res://renders/autotest.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit(1 if fails > 0 else 0)
