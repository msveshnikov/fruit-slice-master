extends Node
## Sound effects and music. Sources and licences: assets/CREDITS.md.

const A := "res://assets/audio/"
const GROUPS := {
	"slice": ["sword.mp3", "sword2.mp3", "sword3.mp3"],
	"squish": ["splash_1.ogg", "splash_2.ogg", "squish_1.wav", "squish_2.wav", "squish_3.wav"],
	"whoosh": ["whoosh_1.wav", "whoosh_2.wav", "whoosh_3.wav"],
	"launch": ["launch_1.wav", "launch_2.wav"],
	"bomb": ["bomb_1.ogg", "bomb_2.ogg"],
	"fuse": ["fuse.wav"],
	"chime": ["chime_0.ogg", "chime_2.ogg", "chime_4.ogg", "chime_6.ogg", "chime_8.ogg"],
	"miss": ["miss.wav"],
	"fail": ["fail.ogg", "error2.ogg"],
	"powerup": ["powerup.ogg", "powerup.mp3"],
	"freeze": ["freeze.wav"],
	"sparkle": ["sparkle.ogg"],
	"hit": ["crack_1.ogg", "crack_2.ogg", "crack_3.ogg"],
	"thump": ["thump.wav"],
	"click": ["click.ogg"],
	"toggle": ["toggle.ogg"],
	"pop": ["pop.ogg"],
	"star": ["star.ogg"],
	"firework": ["fw_1.ogg", "fw_2.ogg", "fw_3.ogg"],
	"complete": ["complete.ogg"],
	"special": ["special.ogg"],
	"win": ["win_vibraphone.ogg", "win_pizzicato.ogg", "win_steeldrums.ogg", "win_fantasia.ogg"],
}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var fuse_player: AudioStreamPlayer
var _next := 0
var _music_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for g in GROUPS:
		var arr: Array = []
		for f in GROUPS[g]:
			if ResourceLoader.exists(A + f):
				var s = load(A + f)
				if s:
					arr.append(s)
		streams[g] = arr
	for i in 18:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	fuse_player = AudioStreamPlayer.new()
	add_child(fuse_player)
	var fz: Array = streams.get("fuse", [])
	if not fz.is_empty():
		var s = fz[0]
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / 2
		fuse_player.stream = s
		fuse_player.volume_db = -14.0
	music = AudioStreamPlayer.new()
	add_child(music)
	music.volume_db = -11.0
	set_track("chipnese")


func _free_player() -> AudioStreamPlayer:
	for i in players.size():
		var c := players[(_next + i) % players.size()]
		if not c.playing:
			_next += 1
			return c
	_next += 1
	return players[_next % players.size()]


func play(name: String, pitch := 1.0, vol := 0.0) -> AudioStreamPlayer:
	if not Game.save.sound:
		return null
	var arr: Array = streams.get(name, [])
	if arr.is_empty():
		return null
	var p := _free_player()
	p.stream = arr.pick_random()
	p.pitch_scale = clampf(pitch, 0.3, 4.0)
	p.volume_db = vol
	p.play()
	return p


func chime(step: int) -> void:
	var arr: Array = streams.get("chime", [])
	if arr.is_empty() or not Game.save.sound:
		return
	var p := _free_player()
	p.stream = arr[clampi(step, 0, arr.size() - 1)]
	p.pitch_scale = 1.0 + 0.12 * maxi(0, step - arr.size() + 1)
	p.volume_db = -3.0
	p.play()


func fuse(on: bool) -> void:
	if fuse_player.stream == null:
		return
	if on and Game.save.sound:
		if not fuse_player.playing:
			fuse_player.play()
	elif fuse_player.playing:
		fuse_player.stop()


const TRACKS := {"chipnese": "music_chipnese.ogg", "tropical": "music_tropical.ogg", "swords": "music_swords.mp3"}
var track := ""


## Switches the soundtrack (menus + worlds 1/3/4: chipnese, worlds 2/5/6: tropical, bosses: swords).
func set_track(name: String) -> void:
	if name == track or not TRACKS.has(name):
		return
	var path: String = A + TRACKS[name]
	if not ResourceLoader.exists(path):
		return
	track = name
	var m = load(path)
	if m == null:
		return
	m.loop = true
	var was := music.playing
	music.stop()
	music.stream = m
	if was or (_music_started and Game.save.music):
		music.play()


## Browsers block audio until the first user gesture: call this from an input event.
func start_music() -> void:
	_music_started = true
	update_music()


func update_music() -> void:
	if music.stream == null:
		return
	if Game.save.music and _music_started:
		if not music.playing:
			music.play()
	else:
		music.stop()


func duck(on: bool) -> void:
	var t := create_tween()
	t.tween_property(music, "volume_db", -22.0 if on else -11.0, 0.4)
