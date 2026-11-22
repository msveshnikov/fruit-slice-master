# Decisions (made without asking)

- **Full remake in Godot 4.7 3D** (GL Compatibility for Web/Android). The old Cordova game (2D canvas, emoji fruit)
  moved to `legacy_cordova/` untouched; its PWA keystore was backed up to `~/.android/fruit-cordova.keystore` (+ `.txt`).
- **Name kept**: "Fruit Slice Master" / «Мастер нарезки» (ru). Original identity: painted fantasy worlds, no
  ninja/samurai branding or characters.
- **3D fruit with real halves**: each fruit is a parametric surface in Blender, bisected at z=0 with a filled,
  hand-painted (numpy) cross-section. In Godot the halves are oriented so the cut plane follows the swipe and is
  tilted ~50° toward the camera, so the flesh is visible while they tumble.
- **Conventions**: Blender Z up → Godot Y up; fruit axis = Z; cut normal +Z; half offsets stored in
  `assets/models/fruits.json` (Godot coordinates); glb per fruit with nodes `whole`, `top`, `bot`.
- **Backdrops are painted (ChatGPT) on a far quad**, with 3D ambient particles in front (petals, snow, embers…),
  slight camera sway and a shader that dims/vignettes the painting so fruit pops. Juice splats land on a plane
  between the fruit and the backdrop.
- **Blade** = 2D ribbon over the 3D view (additive glow + white core, sparks), 8 colour skins unlocked by stars.
- **Slicing** = segment-vs-projected-circle test on every pointer move; a stroke ends after 0.28 s without a cut;
  3+ fruit in one stroke = combo (+5/fruit), 5+ adds slow motion.
- **Levels generated in code** (deterministic) instead of JSON: 6 worlds × 20 levels, goal pattern per world
  ending with a boss; ramps of speed, wave size, bomb chance and specials across all 120 levels.
- **Bomb = level failed** (like the old game's core rule); in Arcade a bomb only costs 15 points.
- **Drops**: only count/type/survive/perfect levels and Classic count dropped fruit; power-up fruit never count.
- **Boss levels**: a giant fruit (scaled to ~60 % of the screen width) drifts, takes 1 HP per swipe contact
  (0.11 s cooldown), spits fruit and bombs sideways; fresh boss bombs can't be hit for 0.45 s (fairness).
- **Music**: three CC0 tracks from OpenGameArt (menus/worlds 1,3,4: "Chipnese"; worlds 2,5,6: "Tropical Fantasy";
  bosses: "Prepare your swords"). Suno was not used (no download credits left).
- **Sounds**: the old game's own sword/power-up sounds are reused; whoosh/squish/launch/fuse/freeze/miss/thump are
  synthesized by `tools/make_sfx.py`; the rest are CC0 packs already used in the sibling games.
- **Analytics**: the Web build keeps the old game's Google Analytics tag (G-L4KLPWXQ75) for continuity.
- **Android**: package `com.maxsoft.fruit` (same as the Cordova app), version 2.0.0 / code 20000 (old was 17002),
  signed with `~/.android/debug.keystore` like the other remakes.
- **Landscape**: the UI is designed for 720×1280 portrait; on wide windows `content_scale_factor` scales it up
  (×0.95 of the aspect, max 1.7), the 3D view simply gets wider.
- **Autotest bot**: the same "ghost blade" that plays the title-screen demo can play levels (it avoids bombs
  by checking their current and predicted screen positions against each swipe segment).
