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
| GitHub (public) | https://github.com/msveshnikov/fruit-slice-master (remote `origin`, branch `master`); release v2.0.1 with `FruitSliceMaster.exe` + `FruitSliceMaster.apk` (`releases/latest/download/...` is linked from maxims.top). The old Cordova repo `msveshnikov/fruitninja` is untouched. |
| Google Play | app «Fruit Slice Master», package `com.maxsoft.fruit`, Play Console app id 4975566050373032307 (dev 5957945224586801272). Listings en-US (default) + ru-RU «Мастер нарезки: фрукты 3D»; texts `store/listing.md`, graphics `store/play/` (all marked AI-made: ChatGPT art). 2.0.1 (20001) is live. |
| Trailer | https://youtu.be/fqI1H9Syqaw (channel Manga TV, public), file `store/trailer_en.mp4`; also the Play promo video |
| maxims.top portal card | source `C:\My-progs\Godot\maxims\index.html` + `img/fruit.jpg` (from `-- --cardshot 4` at `--resolution 1100x619`, frame `renders/card4/land_card_5.png`) |
| Android APK | https://maxims.top/fruit/FruitSliceMaster.apk — package `com.maxsoft.fruit` (same as the Cordova app). Site/GitHub APK = RELEASE build re-signed with the Play upload key `~/.android/fruit-cordova.keystore` (store and key passwords differ, see `fruit-cordova.txt`); never ship a debug-signed APK (Play Protect warns) |
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
Memory soak: `-- --soak 6` (bot plays level after level for 6 min, counters every 20 s to `user://soak.log`; process
memory from outside). On a phone put the flags in `user://cmdline.txt`:
`adb shell "run-as com.maxsoft.fruit sh -c 'echo \"--soak 8\" > files/cmdline.txt'"` (read once, then deleted).
MSAA must stay off on mobile/web (`msaa_3d.mobile/web=0` + guard in `Game._ready`): on the Compatibility renderer it
leaks in Mali GL drivers and Android kills the game with out-of-memory after ~10 levels.

## Rebuild assets

```
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P blender/scripts/build_fruits.py   # ~1 min, add -- --only apple,kiwi / --no-render
python tools/make_textures.py
python tools/make_sfx.py
python tools/make_icons.py
```

## Store shots and trailer

```
"$G" --path . --resolution 1080x1920 --quit-after 60000 -- --storeshots --lang en --size 1080x1920   # renders/game/s*.png (repeat with --lang ru)
# copy to renders/play/raw/<lang>_<name>.png, then:
python tools/play_store.py                                    # captions + feature graphics -> renders/play/
printf '[display]

window/size/window_width_override=1280
window/size/window_height_override=720
' > override.cfg
"$G" --path . --fixed-fps 30 --quit-after 1400 --write-movie renders/video/raw_en.avi -- --trailer --lang en; rm override.cfg
ffmpeg -i renders/video/raw_en.avi -vf "fade=t=in:st=0:d=0.4,fade=t=out:st=29:d=1,format=yuv420p" -af "afade=t=in:st=0:d=0.3,afade=t=out:st=28.5:d=1.5,loudnorm=I=-14:TP=-1.5" -c:v libx264 -crf 19 -c:a aac -b:a 192k -movflags +faststart trailer_en.mp4
```
`--size WxH` makes a borderless window taller than the monitor (Windows clamps titled windows); capture modes keep the
window always-on-top because an occluded window stops rendering and Movie Maker then repeats one frame.
Uploads from the built-in browser: `python <scratch>/cors_server.py renders` on 127.0.0.1:8765. Play Console can fetch it
(patch `HTMLInputElement.prototype.click`, queue URLs). YouTube Studio cannot reach localhost: carry the file in ~1.2 MB
chunks through `renders/hop.html` → `studio.youtube.com/robots.txt#claudechunk=k|n|b64` → IndexedDB, then set the upload
input from the assembled Blob.

## Build and deploy

```
"$G" --headless --path . --export-release "Windows Desktop" build/windows/FruitSliceMaster.exe
"$G" --headless --path . --export-release "Web" build/web/index.html
# APK for the site/GitHub: release export with any keystore, then re-sign with the upload key
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.android/debug.keystore GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android   "$G" --headless --path . --export-release "Android" build/android/FruitSliceMaster.apk
"$LOCALAPPDATA/Android/Sdk/build-tools/36.1.0/apksigner.bat" sign --ks ~/.android/fruit-cordova.keystore --ks-key-alias <alias> --ks-pass env:KS_PASS --key-pass env:KEY_PASS build/android/FruitSliceMaster.apk
# AAB for Google Play: preset "Android Play" (Gradle; template in android/, git-ignored, unzip android_source.zip from
# the 4.7.2 export templates if missing), exported unsigned, then jarsigner (Godot can't pass two different passwords)
"$G" --headless --path . --export-release "Android Play" build/google-play/FruitSliceMaster.aab
jarsigner -sigalg SHA256withRSA -digestalg SHA-256 -keystore ~/.android/fruit-cordova.keystore -storepass:env KS_PASS -keypass:env KEY_PASS build/google-play/FruitSliceMaster.aab <alias>
scp -o BatchMode=yes build/web/* build/android/FruitSliceMaster.apk ubuntu@severance.lol:/var/www/maxims/fruit/
curl -sI https://maxims.top/fruit/index.pck
```
Bump `version/code` in BOTH Android presets for every release. Play: Release > Production > Create release, upload the AAB
(the production track keeps the old Cordova 17002 bundle for 32-bit phones — leave it), notes in `<en-US>`/`<ru-RU>` tags,
Save, then Publishing overview > Send for review. The browser pane must be visible or Play Console doesn't render uploads.

GitHub release (milestones): `"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y.Z build/windows/FruitSliceMaster.exe build/android/FruitSliceMaster.apk --target master --title "Fruit Slice Master X.Y.Z" --notes-file notes.md` — the exe must stay a bare asset with exactly that name (the portal links to it).
