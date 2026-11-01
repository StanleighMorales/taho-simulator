# Taho Simulator — Game & Technical Plan

A 3D browser game. You are **Lolo Ben**, an old taho vendor pushing through a Metro Manila
neighbourhood for 7 days, saving up for his granddaughter's graduation photo package.

Status: **M0 complete** — the web pipeline is proven end to end (see §10). Godot
**4.7.2-stable**, Compatibility renderer, single-threaded web export.

---

## 0. Design pillars

Four rules. When a decision is unclear, the pillar wins.

1. **The pour is the game.** The serving minigame must feel good enough that the player
   wants another customer. Audio and motion first, scoring second.
2. **Warm, not grim.** Day 1–6 are funny and gentle. The sadness is earned in one place
   only (day 7). No misery grinding.
3. **Short sessions, no fail state.** A day is 4–6 minutes. You can have a bad day; you
   cannot lose. Pressure comes from the savings jar, never a game-over.
4. **It must run on a cheap laptop in a browser tab.** Any feature that threatens 60fps at
   720p on integrated graphics is cut or faked.

Target: **~35–45 minutes** of content for the full 7 days, replayable for score.

---

## 1. Hard web constraints

These shape everything, so settle them before building content.

| Constraint | Decision |
|---|---|
| Renderer | **Compatibility** (WebGL 2). Forward+ and Mobile do **not** export to web. Change this *now* — switching later means re-authoring every material and light. |
| Threads / SharedArrayBuffer | Export **without** thread support. Thread builds need `COOP`/`COEP` HTTP headers, which GitHub Pages cannot set. A single-threaded build runs anywhere, including itch.io and mobile Safari. |
| Lighting | **No realtime shadows** except (optionally) one low-res directional shadow. No SSAO, no SDFGI, no volumetrics, no reflection probes. Bake the mood into vertex colours and the texture atlas. |
| Download size | Budget **≤ 25 MB** gzipped total. Measured empty-project baseline: **9.73 MB gzipped** (37.7 MB raw wasm). That leaves roughly **15 MB** for all art and audio, which is why the art direction below is flat-shaded low-poly on one atlas. |
| Save data | `user://` maps to IndexedDB in browser. Write a save at **end of day and after every upgrade purchase** — never rely on a save at window close, browsers don't guarantee it. |
| Audio | Browsers require a user gesture before audio starts. The title screen's "Play" button is that gesture; don't autoplay anything before it. |
| Input | Design **every** interaction as pointer-down / drag / release. That gives mouse and touch for free, so the game works on phones with no extra work. Keyboard WASD for roaming as a bonus. |

### Prove the pipeline on day one
Before any gameplay work: install the **Web export template**, export an empty scene with a
spinning cube, and deploy it to itch.io *and* GitHub Pages. Confirm it loads on desktop
Chrome, desktop Safari/Firefox, and one phone. Web export failures are infuriating to debug
later with a full project; find them while the project is empty.

Serve with **precompressed `.wasm.gz`/`.br`** where the host allows it.

---

## 2. Art direction (chosen to be cheap)

- **Low-poly, flat-shaded, single shared texture atlas.** One 1024×1024 atlas for the entire
  city plus props; one unlit/simple material. This collapses the whole street into a handful
  of draw calls, which is the single biggest web perf win available.
- **Colour does the work.** Warm late-afternoon palette, long orange light, blue-grey shade.
  Bake ambient occlusion into vertex colours by hand rather than computing it.
- **Characters:** stylised, ~800–1500 tris, no fingers, big silhouettes. Lolo Ben reads by
  shape alone: bent back, wide hat, two buckets on a yoke pole.
- **Jeepneys, sari-sari stores, tangled wires, basketball court, laundry on lines, karaoke
  sign.** Specificity is the charm. Repeat props with `MultiMeshInstance3D`.
- No normal maps, no PBR metal/rough textures, no post-processing except a light vignette
  and optional mild glow on the sunset.

---

## 3. Core loop

```
ROAM the street
  → hear "Taho poooo!" (spatial audio + floating icon + screen-edge arrow)
  → walk into the customer's radius
  → SET DOWN the buckets   (camera eases into the serving view)
  → SERVE  (the 6-step minigame — see §4)
  → reaction, payment, maybe a tip
  → pick buckets back up
  → supplies drop; when low, walk home to REFILL
  → day timer ends → EVENING at home → jar progress → next day
```

Two resources create the roaming decisions:

- **Supplies** — tofu / sago / arnibal each have their own meter. Overpouring arnibal on one
  customer genuinely costs you later. Refill at home (free, costs walking time) — this is
  what makes the city a place with a route rather than a corridor.
- **Time** — each day is a fixed wall-clock (4–6 min). Walking is the cost of everything.

Upgrades (bought in the evening) are the long-term progression: sturdier ladle (steadier
pour), insulated bucket (freshness lasts longer → better tips), tsinelas → shoes (walk
speed), umbrella (rain days), bigger buckets (fewer refill trips), louder voice (customers
notice you from further away).

---

## 4. The serving minigame — the heart

Six steps, one continuous flow, **15–25 seconds** total. Every step is one pointer gesture.
Each is graded, and the grades combine into a *Sarap* (deliciousness) score that sets price
and tip.

| # | Step | Gesture | Feel / failure |
|---|---|---|---|
| 1 | **Drain the whey** | Drag to tilt the bucket; a sweet-zone meter fills | Tilt too far and tofu slides toward the lip — comedy gasp, small penalty. Satisfying slosh. |
| 2 | **Shave the tofu** | Hold and sweep a flat arc with the ladle, repeatedly | Thin, smooth, confident arcs = intact silky layers. Jerky arcs = crumbled tofu. Fill to the cup's target line. |
| 3 | **Sago pearls** | Scoop, drag over the cup, release | Pearls plop in with individual sounds. A ring gauge shows the target amount. |
| 4 | **Arnibal** | Press and hold to pour, release at the right level | A thick, stretchy, slow syrup stream. The most ASMR moment in the game. Overflow is funny and costly. |
| 5 | **Swirl** | Circular pointer motion | Arnibal marbles into the white tofu via a shader. Just right = beautiful marbling. Over-mixed = flat muddy brown, lower score. **The skill here is stopping.** |
| 6 | **Serve** | Drag the cup to the customer | They drink. Reaction line, payment, sometimes a tip, sometimes a small story beat. |

**Juice checklist** (this is the work that makes it worth playing):
sound for every single interaction, layered; slight slow-motion on a perfect step; cup
squash-and-stretch; steam wisps; the ladle's wet scrape; a stamped grade card on serve
(`SARAP!` / `Ayos` / `Hmm…`); the customer's audible `Ahhhh`; a coin-drop sound pitched up
with streaks.

**Difficulty is added one layer per day**, never all at once:

- Day 1 — guided, generous windows, prompts on screen. Tutorial.
- Day 2 — sago precision matters; first modifier (*"konti lang asukal"*).
- Day 3 — rush hour: two customers queued, a visible patience meter.
- Day 4 — rain: fewer customers, umbrella juggling, slippery arc on step 2.
- Day 5 — batch orders: five construction workers, one bucket, shared supplies.
- Day 6 — night market, best earnings day, the jar nearly fills.
- Day 7 — one quiet customer across the highway. (See §6.)

---

## 5. Content & comedy (the variety problem)

Content comes from **combinations**, not from new systems. Three cheap axes:

**Customer types** — each is a portrait, two voice lines and one rule:
the picky tita (strict arnibal tolerance), the kid counting exact coins (slow, pays in
tens, adorable), the jeepney driver (timer: the light turns green), the student paying by
QR code (Lolo squints at the phone), the night guard (lonely, tips well, chats), the
*balut* vendor rival (banter), the nun (blesses you, +luck), the 6am drunk (incoherent
order you must interpret), the dog (wants taho, gets water, follows you for the rest of the
day).

**Order modifiers** — multiply every customer: extra sago · no arnibal · half cup · double
sweet · *"to-go"* (adds a seventh step: knot the plastic bag) · *"para sa anak ko"* (two cups).

**Street gags** — small interruptions during serving, 1-in-5 chance, each ~2 seconds:
wind steals the hat (click to catch it) · a fly lands on the cup (swat) · a pigeon perches
on the bucket lid · a kid dips a finger in the arnibal · a motorbike splashes a puddle ·
the neighbour's karaoke goes flat on a high note · the *barangay tanod* shoos you off your
spot (you must move 20m).

**Evening scene at home** — 30–60 seconds, each day: the savings jar, the granddaughter
doing homework, one short exchange, one upgrade purchase. This is the whole emotional
throughline, and it's why day 7 lands. Keep it light. She teases him about his hat.

---

## 6. Day 7 — the ending (stub it, build it last)

A scripted sequence, not a system: a customer waves from across the highway, the player
crosses, a horn, cut to black. Then the flashback cutscene about the photo package, and the
granddaughter in the hospital corridor with the jar.

**Build this last.** For now create `scenes/story/day7.tscn` as a placeholder that fades to
black and prints a TODO, so day progression can be tested end-to-end from the start.

---

## 7. Technical architecture

```
res://
  autoload/      GameState.gd  EventBus.gd  AudioDirector.gd  SaveSystem.gd
  player/        player.tscn  player.gd  camera_rig.gd
  city/          blocks/  props/  city.tscn  spawn_points.gd
  npc/           npc.tscn  npc_brain.gd  customer_types/*.tres
  serving/       serving_view.tscn  steps/{drain,shave,sago,arnibal,swirl,serve}.gd
                 grading.gd  cup.gd
  story/         evening.tscn  day7.tscn  dialogue/*.json
  ui/            hud.tscn  day_summary.tscn  upgrades.tscn  title.tscn
  art/           atlas.png  models/  anim/
  audio/         sfx/  music/
  docs/          GAME_PLAN.md
```

- **Autoloads stay thin.** `GameState` holds money, day, supplies, upgrades. `EventBus` is
  signals only — no logic — so systems never reach into each other.
- **Data, not code, for content.** Customer types, modifiers and dialogue are `Resource`
  files / JSON. Adding the nun must not require touching a script. This is what makes §5
  cheap to expand.
- **Serving steps share one interface** (`begin()`, `handle_pointer()`, `score() -> float`)
  so steps can be reordered, skipped per modifier, or added.
- **One scene swap** between roaming and serving: keep the city loaded, move the camera,
  disable player input. Don't unload and reload the street.
- **Player controller:** `CharacterBody3D`, no ragdoll, no complex physics. Jolt is already
  configured but 3D physics here is basically capsule-vs-wall.

### Performance guardrails
Enforce these in code review of yourself, not after it's slow.

- ≤ 150 draw calls, ≤ 60k tris visible
- ≤ 20 animated characters visible; crowd NPCs beyond 25m freeze their animation
- One directional light, zero or one shadow map (2048, 30m range)
- 3D viewport scaling 0.75–0.85. MSAA off; **FXAA/screen-space AA does not exist in Compatibility** (Forward+/Mobile only), so rely on viewport scaling and flat art, and consider MSAA 2x only if edges read badly
- Audio: ≤ 12 simultaneous voices, OGG mono 96 kbps for music
- Profile in the **browser**, not the editor. Editor framerate lies about web.

---

## 8. Milestones

Each milestone ends in something playable. Don't start the next until the current one runs
in a browser.

| # | Milestone | Done when |
|---|---|---|
| **M0** | Web pipeline | Spinning cube live on itch.io + GH Pages, loads on a phone. Renderer switched to Compatibility. |
| **M1** | Roaming | Lolo Ben walks one street block carrying buckets, camera follows, placeholder boxes for buildings. |
| **M2** | **The pour** | One customer, all six steps, grading, money awarded. *This is the make-or-break milestone — if it isn't fun here, change the minigame, not the city.* |
| **M3** | Day cycle | Day timer, quota, evening scene, save/load, 7 days reachable with day 7 stubbed. |
| **M4** | The city | Full street layout, NPC spawning, the "Taho po!" shout system, supplies + refill-at-home economy. |
| **M5** | Content | Customer types, modifiers, street gags, upgrades, difficulty ramp per day. |
| **M6** | Juice & perf | Full audio pass, animation polish, grade cards, browser perf pass to the §7 budget. |
| **M7** | The ending | Day 7 sequence, cutscene, music, credits. |

Suggested first session: **M0 end to end.** It's unglamorous and it de-risks the entire
project.

---

## 9. Open questions

1. **Phones?** Designing every gesture as pointer-drag means mobile is nearly free, but it
   constrains the HUD (bigger buttons, no hover, no keyboard). Worth committing to now.
2. **Language.** Filipino voice barks (`"Tahooo!"`, `"Salamat po!"`) with English UI text is
   my recommendation — authentic and cheap, since barks need no translation.
3. **Where does it live?** itch.io is the best default for reach and it supports larger
   builds; GitHub Pages as a free mirror.
4. **Art source.** Hand-modelled in Blender vs. bought low-poly city kit. A kit would get
   M4 done far faster; the characters probably need to be custom either way.

---

## 10. M0 — verified results

Completed 2026-11-01. The pipeline works; everything below was measured, not assumed.

| Check | Result |
|---|---|
| Godot | 4.7.2-stable (`F:\Download\Godot_v4.7.2-stable_win64.exe\`) |
| Renderer | `gl_compatibility` — confirmed in-browser as `OpenGL ES 3.0 (WebGL 2.0)` |
| Build config | `single-threaded, no GDExtension support` (the no-threads template) |
| Download size | **9.73 MB gzipped** / 38 MB raw |
| Pointer input | Verified in the exported build — drag reports live coordinates and a drag count, so the touch model works |
| Export command | `godot --headless --export-release "Web" build/web/index.html` |

**Correction made during M0:** the plan originally specified FXAA. Screen-space AA does
not exist in the Compatibility renderer (Forward+/Mobile only) and Godot warns about it.
Removed; we rely on 3D viewport scaling instead.

### Not yet verified
- **Real framerate.** The automated browser pane throttles `requestAnimationFrame` to
  ~2 fps when it isn't being actively watched, so the on-screen `fps` readout from that
  environment is meaningless. Open the build yourself to get a true number.
- **A real phone.** The pointer model is proven; actual touch hardware is not.
- **itch.io and GitHub Pages deploys.** The CI workflow is written but has never run,
  because the project has no remote yet.

### How to run it
```
# export
godot --headless --export-release "Web" build/web/index.html

# serve locally (a Godot build cannot run from file://)
python tools/serve_web.py
```
