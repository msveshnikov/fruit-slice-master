extends Node
## Global state: worlds, levels (generated deterministically), blades, save file, texts, command-line flags.

const SAVE_PATH := "user://save.json"
const LEVELS_PER_WORLD := 20

const FRUITS := ["apple", "orange", "lemon", "lime", "watermelon", "pineapple", "banana", "pear", "kiwi", "peach",
	"coconut", "strawberry", "plum", "mango", "dragonfruit", "grapefruit"]
const SPECIALS := ["goldapple", "frostberry", "starfruit", "pomegranate"]

const WORLDS := [
	{"id": "bamboo", "bg": "w1_bamboo", "color": Color(0.45, 0.8, 0.3), "fx": "petals",
		"fruits": ["apple", "orange", "banana", "watermelon", "lemon", "pear"], "specials": ["goldapple"],
		"boss": "watermelon", "light": Color(1.0, 0.92, 0.78), "ambient": Color(0.75, 0.8, 0.7)},
	{"id": "lagoon", "bg": "w2_lagoon", "color": Color(1.0, 0.55, 0.3), "fx": "sparkles",
		"fruits": ["pineapple", "coconut", "mango", "lime", "banana", "watermelon", "orange"], "specials": ["goldapple", "frostberry"],
		"boss": "coconut", "light": Color(1.0, 0.8, 0.6), "ambient": Color(0.85, 0.7, 0.7)},
	{"id": "market", "bg": "w3_market", "color": Color(1.0, 0.35, 0.3), "fx": "lanterns",
		"fruits": ["strawberry", "plum", "dragonfruit", "peach", "apple", "grapefruit", "mango"], "specials": ["goldapple", "frostberry", "starfruit"],
		"boss": "dragonfruit", "light": Color(1.0, 0.78, 0.55), "ambient": Color(0.55, 0.5, 0.75)},
	{"id": "frost", "bg": "w4_frost", "color": Color(0.45, 0.8, 1.0), "fx": "snow",
		"fruits": ["kiwi", "grapefruit", "pear", "plum", "lime", "lemon", "apple", "strawberry"], "specials": ["goldapple", "frostberry", "starfruit", "pomegranate"],
		"boss": "grapefruit", "light": Color(0.85, 0.92, 1.0), "ambient": Color(0.6, 0.7, 0.9)},
	{"id": "volcano", "bg": "w5_volcano", "color": Color(1.0, 0.4, 0.1), "fx": "embers",
		"fruits": FRUITS, "specials": ["goldapple", "frostberry", "starfruit", "pomegranate"],
		"boss": "pomegranate", "light": Color(1.0, 0.7, 0.5), "ambient": Color(0.8, 0.5, 0.45)},
	{"id": "sky", "bg": "w6_sky", "color": Color(0.7, 0.45, 1.0), "fx": "stars",
		"fruits": FRUITS, "specials": ["goldapple", "frostberry", "starfruit", "pomegranate"],
		"boss": "starfruit", "light": Color(0.9, 0.85, 1.0), "ambient": Color(0.6, 0.55, 0.85)},
]

## Blade trails: unlocked by total stars.
const BLADES := [
	{"id": "steel", "stars": 0, "core": Color(1, 1, 1), "glow": Color(0.6, 0.85, 1.0)},
	{"id": "fire", "stars": 12, "core": Color(1, 0.95, 0.6), "glow": Color(1.0, 0.35, 0.05)},
	{"id": "ice", "stars": 30, "core": Color(0.9, 1, 1), "glow": Color(0.2, 0.75, 1.0)},
	{"id": "jade", "stars": 55, "core": Color(0.9, 1, 0.9), "glow": Color(0.15, 0.9, 0.4)},
	{"id": "neon", "stars": 85, "core": Color(1, 0.85, 1), "glow": Color(1.0, 0.15, 0.8)},
	{"id": "gold", "stars": 120, "core": Color(1, 1, 0.85), "glow": Color(1.0, 0.75, 0.1)},
	{"id": "rainbow", "stars": 170, "core": Color(1, 1, 1), "glow": Color(1, 0.3, 0.3)},
	{"id": "void", "stars": 240, "core": Color(1, 1, 1), "glow": Color(0.45, 0.1, 0.9)},
]

var fruit_meta := {}
var levels: Array = []
var save := {
	"stars": {}, "best": {}, "modes": {"classic": 0, "arcade": 0, "zen": 0},
	"blade": "steel", "sound": true, "music": true, "lang": "", "tutorial": false, "sliced": 0, "last_world": 0,
}
var lang := "en"
var args := {}


func _ready() -> void:
	_parse_args()
	var f := FileAccess.open("res://assets/models/fruits.json", FileAccess.READ)
	if f:
		fruit_meta = JSON.parse_string(f.get_as_text())
	_build_levels()
	load_game()
	if args.has("fresh"):
		save.stars = {}
		save.best = {}
		save.tutorial = false
	if args.has("lang"):
		save.lang = args.lang
	lang = save.lang if save.lang != "" else ("ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk"] else "en")


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i]
		if k.begins_with("--"):
			k = k.substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				args[k] = a[i + 1]
				i += 1
			else:
				args[k] = true
		i += 1


# ------------------------------------------------------------------ levels

## Goal kinds: count (slice N, miss limit), score (S points in T s), type (slice N of one fruit),
## combo (K combos of 3+ in T s), survive (T s, miss limit, many bombs), perfect (N fruit, no miss), boss.
const PATTERN := ["count", "score", "type", "count", "combo", "survive", "score", "type", "perfect", "count",
	"combo", "score", "type", "survive", "count", "perfect", "score", "combo", "survive", "boss"]


func _build_levels() -> void:
	levels.clear()
	var r := RandomNumberGenerator.new()
	for w in WORLDS.size():
		var world: Dictionary = WORLDS[w]
		for i in LEVELS_PER_WORLD:
			var n := w * LEVELS_PER_WORLD + i
			r.seed = 7919 * (n + 11)
			var d := float(n) / float(WORLDS.size() * LEVELS_PER_WORLD - 1)
			var di := float(i) / float(LEVELS_PER_WORLD - 1)
			var goal: String = PATTERN[i]
			if n == 0:
				goal = "count"
			var L := {
				"index": n, "world": w, "num": i + 1, "goal": goal,
				"speed": 0.9 + 0.38 * d + 0.06 * di,
				"interval": lerpf(1.7, 0.75, d) - 0.15 * di,
				"wave": [1, 2 + int(round(3.0 * d + di))],
				"bombs": 0.0 if n < 3 else clampf(0.05 + 0.14 * d + 0.03 * di, 0, 0.22),
				"special": 0.0 if n < 2 else 0.05 + 0.03 * d,
				"fruits": world.fruits,
				"specials": world.specials,
				"misses": 3,
			}
			match goal:
				"count":
					L.target = int(14 + 30 * d + 8 * di)
					L.misses = 3 if d < 0.5 else 4
				"score":
					L.target = int(round((180 + 700 * d + 150 * di) / 10.0) * 10)
					L.time = 45
					L.bombs = maxf(L.bombs, 0.04 if n > 1 else 0.0)
				"type":
					var pool: Array = world.fruits
					L.fruit = pool[r.randi() % pool.size()]
					L.target = int(7 + 12 * d + 3 * di)
					L.misses = 5
				"combo":
					L.target = int(3 + 6 * d + 2 * di)
					L.time = 60
					L.wave = [2, 3 + int(round(3.0 * d + di))]
				"survive":
					L.time = int(35 + 30 * d)
					L.bombs = clampf(L.bombs + 0.12, 0, 0.35)
					L.misses = 3
				"perfect":
					L.target = int(10 + 18 * d)
					L.misses = 1
					L.bombs *= 0.6
				"boss":
					L.boss = world.boss
					L.target = int(30 + 45 * d)
					L.time = 50
					L.bombs = clampf(L.bombs, 0.08, 0.22)
			levels.append(L)


func level(n: int) -> Dictionary:
	return levels[clampi(n, 0, levels.size() - 1)]


func stars_of(n: int) -> int:
	return int(save.stars.get(str(n), 0))


func total_stars() -> int:
	var t := 0
	for k in save.stars:
		t += int(save.stars[k])
	return t


func unlocked(n: int) -> bool:
	if args.has("unlock"):
		return true
	return n == 0 or save.stars.has(str(n - 1)) or save.stars.has(str(n))


func highest_unlocked() -> int:
	var h := 0
	for n in levels.size():
		if unlocked(n):
			h = n
	return h


func record(n: int, stars: int, score: int) -> bool:
	var k := str(n)
	var improved := stars > stars_of(n)
	save.stars[k] = maxi(stars, stars_of(n))
	save.best[k] = maxi(score, int(save.best.get(k, 0)))
	save_game()
	return improved


func blade() -> Dictionary:
	for b in BLADES:
		if b.id == save.blade:
			return b
	return BLADES[0]


# ------------------------------------------------------------------ save

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			save[k] = d[k]


func save_game() -> void:
	if args.has("autotest"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))


# ------------------------------------------------------------------ texts

const T := {
	"title1": ["Fruit Slice", "Мастер"],
	"title2": ["Master", "нарезки"],
	"play": ["Play", "Играть"],
	"modes": ["Modes", "Режимы"],
	"blades": ["Blades", "Клинки"],
	"campaign": ["Journey", "Путешествие"],
	"classic": ["Classic", "Классика"],
	"arcade": ["Arcade", "Аркада"],
	"zen": ["Zen", "Дзен"],
	"classic_d": ["3 lives. Don't drop fruit, don't touch bombs.", "3 жизни. Не роняй фрукты, не трогай бомбы."],
	"arcade_d": ["60 seconds of combos and power-ups.", "60 секунд комбо и бонусов."],
	"zen_d": ["90 calm seconds. No bombs.", "90 спокойных секунд. Без бомб."],
	"best": ["Best", "Рекорд"],
	"score": ["Score", "Очки"],
	"level": ["Level", "Уровень"],
	"world_bamboo": ["Bamboo Garden", "Бамбуковый сад"],
	"world_lagoon": ["Sunset Lagoon", "Закатная лагуна"],
	"world_market": ["Lantern Market", "Рынок фонарей"],
	"world_frost": ["Frost Peak", "Ледяной пик"],
	"world_volcano": ["Volcano Forge", "Вулканическая кузня"],
	"world_sky": ["Sky Garden", "Небесный сад"],
	"goal_count": ["Slice %d fruit", "Разрежь %d фруктов"],
	"goal_score": ["Score %d in %d s", "Набери %d очков за %d с"],
	"goal_type": ["Slice %d × %s", "Разрежь %d × %s"],
	"goal_combo": ["Make %d combos in %d s", "Сделай %d комбо за %d с"],
	"goal_survive": ["Survive %d s", "Продержись %d с"],
	"goal_perfect": ["Slice %d fruit, drop none", "Разрежь %d, не уронив ни одного"],
	"goal_boss": ["Defeat the giant %s!", "Победи гигантский %s!"],
	"misses": ["Drops allowed: %d", "Можно уронить: %d"],
	"tap_start": ["Swipe to start", "Проведи, чтобы начать"],
	"swipe": ["Swipe across the fruit!", "Проведи по фрукту!"],
	"avoid_bomb": ["Never slice bombs!", "Не режь бомбы!"],
	"combo": ["COMBO", "КОМБО"],
	"great": ["Great!", "Отлично!"],
	"win": ["Level complete!", "Уровень пройден!"],
	"lose": ["Try again!", "Ещё разок!"],
	"lose_bomb": ["Boom! You hit a bomb", "Бум! Ты задел бомбу"],
	"lose_miss": ["Too many fruit dropped", "Слишком много упало"],
	"lose_time": ["Time is up", "Время вышло"],
	"game_over": ["Game over", "Игра окончена"],
	"time_up": ["Time up!", "Время!"],
	"new_best": ["New best!", "Новый рекорд!"],
	"next": ["Next", "Дальше"],
	"retry": ["Retry", "Заново"],
	"levels": ["Levels", "Уровни"],
	"menu": ["Menu", "Меню"],
	"resume": ["Resume", "Продолжить"],
	"paused": ["Paused", "Пауза"],
	"settings": ["Settings", "Настройки"],
	"sound": ["Sound", "Звук"],
	"music": ["Music", "Музыка"],
	"language": ["Language", "Язык"],
	"reset": ["Reset progress", "Сбросить прогресс"],
	"reset_q": ["Erase all stars?", "Стереть все звёзды?"],
	"yes": ["Yes", "Да"],
	"no": ["No", "Нет"],
	"close": ["Close", "Закрыть"],
	"locked": ["Collect %d ★", "Собери %d ★"],
	"selected": ["Selected", "Выбран"],
	"select": ["Select", "Выбрать"],
	"stars_total": ["Stars: %d", "Звёзды: %d"],
	"frenzy": ["FRENZY!", "ФРУКТОПАД!"],
	"freeze": ["FREEZE!", "ЗАМОРОЗКА!"],
	"double": ["DOUBLE POINTS!", "ДВОЙНЫЕ ОЧКИ!"],
	"hits": ["%d HITS!", "%d УДАРОВ!"],
	"boss_hp": ["Boss", "Босс"],
	"blade_steel": ["Steel", "Сталь"],
	"blade_fire": ["Fire", "Огонь"],
	"blade_ice": ["Ice", "Лёд"],
	"blade_jade": ["Jade", "Нефрит"],
	"blade_neon": ["Neon", "Неон"],
	"blade_gold": ["Gold", "Золото"],
	"blade_rainbow": ["Rainbow", "Радуга"],
	"blade_void": ["Void", "Бездна"],
	"fruit_apple": ["apples", "яблок"], "fruit_orange": ["oranges", "апельсинов"], "fruit_lemon": ["lemons", "лимонов"],
	"fruit_lime": ["limes", "лаймов"], "fruit_watermelon": ["watermelons", "арбузов"], "fruit_pineapple": ["pineapples", "ананасов"],
	"fruit_banana": ["bananas", "бананов"], "fruit_pear": ["pears", "груш"], "fruit_kiwi": ["kiwis", "киви"],
	"fruit_peach": ["peaches", "персиков"], "fruit_coconut": ["coconuts", "кокосов"], "fruit_strawberry": ["strawberries", "клубник"],
	"fruit_plum": ["plums", "слив"], "fruit_mango": ["mangoes", "манго"], "fruit_dragonfruit": ["dragon fruits", "питай"],
	"fruit_grapefruit": ["grapefruits", "грейпфрутов"],
	"boss_watermelon": ["watermelon", "арбуз"], "boss_coconut": ["coconut", "кокос"], "boss_dragonfruit": ["dragon fruit", "питайю"],
	"boss_grapefruit": ["grapefruit", "грейпфрут"], "boss_pomegranate": ["pomegranate", "гранат"], "boss_starfruit": ["star fruit", "карамболу"],
}


func tr_(key: String) -> String:
	var v = T.get(key)
	if v == null:
		return key
	return v[1] if lang == "ru" else v[0]


func goal_text(L: Dictionary) -> String:
	match L.goal:
		"count":
			return tr_("goal_count") % L.target
		"score":
			return tr_("goal_score") % [L.target, L.time]
		"type":
			return tr_("goal_type") % [L.target, tr_("fruit_" + L.fruit)]
		"combo":
			return tr_("goal_combo") % [L.target, L.time]
		"survive":
			return tr_("goal_survive") % L.time
		"perfect":
			return tr_("goal_perfect") % L.target
		"boss":
			return tr_("goal_boss") % tr_("boss_" + L.boss)
	return ""
