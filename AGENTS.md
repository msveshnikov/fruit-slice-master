# AGENTS.md — Fruit Slice Master (Мастер нарезки)

3D fruit-slicing arcade in Godot 4.7: swipe across glossy Blender-built fruit flying in front of painted worlds.
6 worlds × 20 levels (boss at the end of each world) + Classic / Arcade / Zen modes, 8 unlockable blades.
Remake of the old HTML/Cordova game (kept untouched in `legacy_cordova/`); design doc:
`Fruit Slice Master — concept art and tasks.md`, choices in `decisions.md`.

## Where everything is

| What | Where |
|---|---|
| Project (Godot 4.7, GL Compatibility) | `C:\My-progs\Godot\fruitninja` |
| Live web build | https://maxims.top/fruit/ (server folder `ubuntu@severance.lol:/var/www/maxims/fruit/`) |
| Android APK | https://maxims.top/fruit/FruitSliceMaster.apk — package `com.maxsoft.fruit` (same as the Cordova app), signed with `~/.android/debug.keystore` via `.godot/export_credentials.cfg` (not in git) |
| Old Cordova PWA keystore | `~/.android/fruit-cordova.keystore` + `.txt` (never commit) |
| Godot exe | `C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe` |
| Blender exe | `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe` |
| Fruit models + icons | `blender/scripts/build_fruits.py` → `assets/models/fruits/*.glb`, `assets/models/fruits.json`, `assets/ui/fruits/*.png` |
| Effect textures | `python tools/make_textures.py` → `assets/textures/fx/` |
| Synth sounds | `python tools/make_sfx.py` → `assets/audio/*.wav` |
| App icons | `python tools/make_icons.py` (from `concept/ui/icon_chatgpt.png`) |
| Backgrounds (ChatGPT) | originals `concept/worlds/*.png`, game copies `assets/backgrounds/*.jpg` |
| Credits | `assets/CREDITS.md` |
| Save file | `user://save.json` |
| Autotest output | `renders/game/*.png`, `renders/autotest.log` |

## Code map

| File | Role |
|---|---|
| `scripts/game.gd` (autoload `Game`) | worlds, level generator (120 levels), blades, save, ru/en texts, command-line flags |
| `scripts/sfx.gd` (autoload `Sfx`) | sound groups, combo chimes, bomb fuse loop, per-world music tracks |
| `scripts/arena.gd` | 3D field: camera, lights, backdrop, ambient FX, spawning, ballistic flight, slicing, halves, juice, splats, popups, power-ups, bombs, boss, ghost blade (title demo + autotest bot) |
| `scripts/blade_trail.gd` | blade ribbon (glow + core + sparks) |
| `scripts/main.gd` | screens (title, modes, levels, blades, settings, pause, results), match rules + HUD, autotest |
| `scripts/ui_kit.gd` | fonts, buttons, vector icons, stars, panels |
| `shaders/backdrop.gdshader` | painted backdrop: sway, dim, vignette, freeze tint |

## Test

```
G="/c/Users/msves/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe"
"$G" --headless --path . --import
"$G" --path . --quit-after 60000 -- --autotest                                  # portrait
"$G" --path . --resolution 1280x720 --quit-after 60000 -- --autotest --lang en  # landscape (land_*.png)
```
Pass = last line of `renders/autotest.log` is `AUTOTEST DONE fails=0` (exit code alone is not enough).
The bot wins level 1 and the world-1 boss, a sliced bomb fails a level, each power-up fruit works, a 4-fruit swipe
is a combo, Classic ends after 3 drops, pause works; screenshots of every screen and every world.
Other flags: `-- --level N` (start level N), `-- --fresh`, `-- --lang en|ru`, `-- --unlock`.

## Rebuild assets

```
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P blender/scripts/build_fruits.py   # ~1 min, add -- --only apple,kiwi / --no-render
python tools/make_textures.py
python tools/make_sfx.py
python tools/make_icons.py
```

## Build and deploy

```
"$G" --headless --path . --export-release "Windows Desktop" build/windows/FruitSliceMaster.exe
"$G" --headless --path . --export-release "Web" build/web/index.html
"$G" --headless --path . --export-debug "Android" build/android/FruitSliceMaster.apk
scp -o BatchMode=yes build/web/* build/android/FruitSliceMaster.apk ubuntu@severance.lol:/var/www/maxims/fruit/
curl -sI https://maxims.top/fruit/index.pck
```
Bump `version/code` in the Android preset for every APK that must install over an older one.
