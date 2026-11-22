# Fruit Slice Master — concept art and tasks

## Pitch
A juicy 3D arcade slicer. Glossy 3D fruit is tossed into the air in front of painted worlds; swipe to slice it
in two, spray juice, chain combos, trigger power-up fruit and never touch a bomb. A journey of **6 worlds × 20
levels** (each world ends with a giant boss fruit) plus three endless modes. Remake of the old HTML/Cordova
"Fruit Slice Master" (kept in `legacy_cordova/`).

- **Genre / camera:** arcade, fixed perspective camera looking at a vertical play plane (fruit flies in real 3D
  depth, halves tumble toward the camera so the cut face shows).
- **Core loop:** fruit launches in waves → swipe → halves + juice + points → combos (3+ in one swipe) →
  goal reached → stars → next level / unlock blades.
- **Player verb:** the swipe (blade trail). Nothing else — one-finger game, phone first.
- **Opponents:** gravity (dropped fruit), bombs, the clock, boss fruit that spits bombs.
- **Progression:** stars per level (3 max) unlock the next level and 8 blade trails (Steel → Void).
- **Platforms:** Web (maxims.top/fruit), Android APK (same package as the old app), Windows exe.

## Style block (pasted at the start of every art prompt)
> vibrant stylized 3D render, glossy and juicy, saturated warm colours, soft volumetric god rays, cinematic
> Pixar-like lighting, painterly depth with strong atmospheric perspective and soft bokeh, rich detail on the
> edges and bottom of the frame, while the CENTRE of the picture stays open, calm and uncluttered (it is the play
> area where fruit flies), no fruit, no characters, no people, no text, no logos, no UI. Vertical portrait 2:3.

## Worlds (concept art in `concept/worlds/`, game copies in `assets/backgrounds/`)
| # | World | Scene prompt (after the style block) | Ambient FX | Boss |
|---|---|---|---|---|
| 1 | Bamboo Garden | serene bamboo garden dojo at golden morning, wooden deck, cherry blossom, lanterns, misty mountains | petals | watermelon |
| 2 | Sunset Lagoon | tropical lagoon at sunset, pier planks, palms, tiki torches, huge sun | sparkles | coconut |
| 3 | Lantern Market | lantern night market, wet cobblestones, hundreds of paper lanterns, bokeh stalls | lantern glows | dragon fruit |
| 4 | Frost Peak | frozen mountain temple at blue hour, pagoda, frozen waterfall, aurora, snow | snow | grapefruit |
| 5 | Volcano Forge | basalt ledge with glowing cracks, lava rivers, erupting volcano, embers | embers | pomegranate |
| 6 | Sky Garden | floating islands, crystal plants, ringed planet, nebula, marble platform | stars | star fruit |
| — | Title | magical orchard dojo at golden hour, sun disc, light beams, sparkles | — | — |

App icon prompt: square icon, watermelon + orange sliced mid-air by a glowing blade swoosh, juice droplets,
warm radial background, no text (`concept/ui/icon_chatgpt.png`).

## Fruit (Blender, `blender/scripts/build_fruits.py`)
16 regular fruit (apple, orange, lemon, lime, watermelon, pineapple, banana, pear, kiwi, peach, coconut,
strawberry, plum, mango, dragon fruit, grapefruit), 4 power-up fruit and the bomb:
- **Golden apple** — double points 8 s · **Frost berry** — time ×0.4 for 4.5 s · **Star fruit** — 3 s frenzy
  from the sides · **Pomegranate** — freezes in the air, every swipe across it is a hit, bursts after 1.8 s.

## Level goals (generated in `scripts/game.gd`, 20 per world, difficulty ramps across all 120)
count (slice N, drop limit) · score (S points in T s) · type (N of one fruit) · combo (K combos in T s) ·
survive (T s with many bombs) · perfect (N fruit, no drop) · boss (HP, time limit, boss spits bombs).
Stars: drops-based for count/type/survive, time-left-based for score/combo/boss, perfect = 3.

## Modes
Classic (3 lives, ramps up, bomb = game over) · Arcade (60 s, bombs cost 15 points, power-ups) · Zen (90 s, no bombs).

## How this run was made (pipeline)
Task 1–2 (assets) = `build_fruits.py`; Task 3–4 (levels/population) = the level generator and spawner tables;
Task 5 = the Godot game. Paper trail: `decisions.md`, `AGENTS.md`, `assets/CREDITS.md`.
