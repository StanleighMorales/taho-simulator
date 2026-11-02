# Taho Simulator — Game & Technical Plan

A 3D browser game. You are **Lolo Ben**, an old taho vendor pushing through a Metro Manila
neighbourhood for 7 days, saving up for his granddaughter's graduation photo package.

Status: **M1 + M2 playable** — https://stanleighmorales.github.io/taho-simulator/
You roam a small town, find a customer, serve all six steps, get paid, and walk home to
refill. Godot **4.7.2-stable**, Compatibility renderer, single-threaded web export,
deployed automatically from `main` (see §10, §11 and §12).

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
| 1 | **Skim the water** | Dip the ladle in, sweep across, lift it out — one scoop per gesture | Vendors don't tip the bucket: the whey pools on the tofu and is lifted off. Only the dip depth matters. Go below the water and you bring up tofu. The layer thins as you work, so each scoop must be shallower than the last. |
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
| **M1** | Roaming | ✅ Done. Lolo Ben walks a two-street town carrying buckets, camera follows, placeholder boxes for buildings. See §12. |
| **M2** | **The pour** | ✅ Done. One customer, all six steps, grading, money awarded, on placeholder geometry. |
| **M3** | Day cycle | Day timer, quota, evening scene, save/load, 7 days reachable with day 7 stubbed. |
| **M4** | The city | Partly done in §12 (layout, spawning, shouts, supplies, refill). Left: a real route worth planning, more of the street's specificity, crowd NPCs who are not customers. |
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
| Live URL | https://stanleighmorales.github.io/taho-simulator/ |
| CI | Green — build 37s, deploy 9s. The headless **Linux** export works, not just the Windows one. |
| Framerate | **59–60 fps** on the live build (empty scene, dev machine). A real floor needs a loaded scene on weak hardware. |

**Correction made during M0:** the plan originally specified FXAA. Screen-space AA does
not exist in the Compatibility renderer (Forward+/Mobile only) and Godot warns about it.
Removed; we rely on 3D viewport scaling instead.

### Problems found and fixed during M0
1. **FXAA does not exist in Compatibility.** Removed from the plan and the project.
2. **Godot re-imported its own build output.** `build/` lives inside the project, so the
   exported PNGs were scanned back in as assets and packed into the next build —
   `index.pck` grew 13,028 → 37,152 bytes in one cycle, compounding every export.
   Fixed with a tracked `build/.gdignore`.
3. **`configure-pages` could not create the Pages site.** `enablement: true` failed with
   *Resource not accessible by integration*. Fixed by creating the Pages site once via
   the API (`gh api --method POST repos/.../pages -f build_type=workflow`); the workflow
   now finds the existing site and succeeds.

### Still not verified
- **A real phone.** The pointer model is proven in the exported build, but no touch
  hardware has run it.
- **Framerate under load.** 59–60 fps on an empty scene says the pipeline is healthy; it
  says nothing yet about the §7 budget with a city and NPCs on a weak laptop.
- **itch.io.** The upload zip is built and verified but has not been uploaded.

### How to run it
```
# export
godot --headless --export-release "Web" build/web/index.html

# serve locally (a Godot build cannot run from file://)
python tools/serve_web.py
```

---

## 11. M2 — the serving minigame

Built and playable. One customer at a time, six steps, graded, paid, repeat.

### Code shape
- `scenes/serving/steps/serving_step.gd` — base class. A step reads pointer gestures in
  screen space, drives the view through method calls, and reports a 0..1 score. Steps hold
  **no node references**, which is what makes them testable.
- `scenes/serving/serving_view.gd` — owns every node, runs the step order, draws the HUD.
- `scenes/serving/grading.gd` — weights the step scores into a Sarap rating, then a price.
- `shaders/taho_contents.gdshader` — the marbling. Uses object-space XZ rather than UV so
  it reads on both the top and the sides of a cylinder.
- `tests/run_step_tests.gd` — 27 headless assertions, run with
  `godot --headless --script res://tests/run_step_tests.gd`.

### What the tests lock in
Each step's *intent*, not just that it runs: careful tilting beats reckless tilting; smooth
shaving beats jerky (0.98 vs 0.03); stopping the sago on target beats overloading; releasing
the arnibal early beats holding too long (0.92 vs 0.08); and the swirl sweet spot beats
over-mixing. If a tuning change breaks the *point* of a step, a test fails.

### Problems found and fixed
1. **Camera and both lights pointed the wrong way.** In a `.tscn`, Godot writes a
   `Transform3D` basis **row by row**, not as basis vectors. Written as columns, the pitch
   inverts — the camera stared at empty sky and the scene rendered as an empty background.
   The same bug was in the M0 smoke test, which is why its ground was black.
2. **Sago pearls were invisible**, buried inside the opaque tofu cylinder. They now ride on
   the tofu surface — which is also how taho is actually served.
3. **Contents didn't taper** with the cup, so a near-empty cup showed a disc wider than the
   cup. Now scales in X/Z with fill.
4. **Drain feedback contradicted itself**, showing "Clean" in the warning colour. The spill
   warning now depends on the tilt angle alone.

### Step 1 was rebuilt after a reality check
It was first built as "tilt the bucket to pour the whey off", which is not how
taho is sold. Vendors leave the bucket standing and lift the water off the top with
the flat ladle. It is now one scoop per gesture — dip, sweep, lift out — judged only on
how deep you dipped, and the water layer thins as you remove it so every scoop has to be
shallower than the last. The difficulty curve comes from the physical situation rather
than from a tuning constant, which is the better kind.

Two bugs came out of that rebuild:
- A scoop was judged against the water level *after* it had been removed, so a correct
  scoop was penalised. Now judged against the depth at the moment the ladle went in.
- The bucket was a closed, opaque cylinder, so the player could not see the water they
  were skimming — the gauge was the only feedback. The bucket is now open-topped with
  tofu visible underneath, and the puddle shrinks in radius as well as depth, so skimming
  visibly uncovers white tofu.

### Known gaps, honestly
- **No audio at all.** The plan says the pour should be ASMR-satisfying and audio is most of
  that. This is the single biggest thing standing between M2 and "satisfying".
- **The ladle has not been seen in motion** — it is only on screen mid-drag, which the
  automated browser cannot capture.
- **Feel is untuned by a human.** The numbers pass tests; nobody has yet said whether the
  drain takes too long or the swirl is too fussy.
- **The marbling shader has not been seen at a readable size** — only in a small automated
  browser pane. It may need its contrast or spiral frequency adjusted.
- **The handover looks wrong**: the cup tweens into the customer capsule rather than being
  held. Fine on placeholder geometry, needs a hand to attach to later.
- Placeholder geometry throughout: cylinders, a capsule customer, no Lolo Ben.

---

## 12. M1 — the town

A small neighbourhood you walk around, with the serving minigame hanging off it.

### What is there
Two streets crossing, pavements and kerbs, around two dozen shop fronts with awnings,
a barangay court, parked jeepneys, lamp posts, and Lolo Ben's house a few steps off the
cross street. Customers appear on the pavement, shout *"Taho po!"*, and wait. Walk into
one and the buckets go down; the serving view takes the screen; the sale is banked and
the supplies come out of the buckets when you pick them back up. Run dry, walk home,
stand on the porch, refill.

### Code shape
- `scenes/town/town.gd` — builds the whole town **in code**, not in a `.tscn`. See the
  reason below.
- `scenes/player/player.gd` — `CharacterBody3D`, WASD **and** tap-to-walk, drag to look.
  The camera is positioned by hand each frame rather than parented or hung off a
  `SpringArm3D`.
- `scenes/npc/customer.gd` — a silhouette, a shout, and an `Area3D`. Customer types are
  a table in the script for now; §7 wants them as `Resource` files, which is the right
  move as soon as they carry more than a name and a line.
- `scenes/main.gd` — owns the one mode switch. Roaming and serving are two cameras over
  two sets of geometry that both stay loaded.
- `autoload/game_state.gd` — money, supplies, tally. Nothing else.
- `tests/town_tests.tscn` — 25 assertions over all of the above.

### Decisions worth keeping
- **The town is built in code.** A hand-written `.tscn` of `Transform3D` literals is
  exactly where this project lost an afternoon in M2: Godot writes a basis **row by
  row**, so a transform typed as columns silently inverts. `position` and
  `rotation_degrees` cannot go wrong that way, and the layout reads as data.
- **The follow camera is driven by hand.** Same reason: `SpringArm3D` encodes a
  direction convention that is easy to get backwards, and the fix for a camera staring
  at the sky is expensive to find twice.
- **Tap to walk, drag to look**, separated by a 14px threshold. That is the whole mobile
  control scheme, and it costs one `if`.
- **Supplies gate the sale, time does not yet.** Walking home is currently the only
  reason the map has a shape. The day timer in M3 is the other half.

### Problems found and fixed
1. **Buildings on the cross street grew into the road.** The flip that decides which way
   a lot extends was keyed to the wrong side, so the west row crossed the pavement and
   covered the carriageway. The opening view was a wall.
2. **The player started inside a block**, facing the back of a shop with the camera
   jammed against it. Home moved from deep in the block to a few steps off the cross
   street, so the first frame is the town.
3. **Lamp posts sat on the kerb**, which is where the follow camera wants to be — one
   was dead centre of the opening shot. They are at the back of the pavement now. Less
   authentic, considerably more playable.
4. **The town was over-lit.** Sky ambient at 0.9 plus a 1.25 sun washed every facade to
   near white. Now 0.38 / 1.0, and the fog is thinner.
5. **`main` assumed the serving view had already hidden itself.** True by the route a
   player takes, false when anything else ends an order — the integration test caught
   it. Putting the view to sleep is now explicit and safe to do twice.

### Known gaps, honestly
- **Still no audio.** Unchanged from M2, and still the biggest gap.
- **Nobody has walked it with their hands.** The feel of the walk speed, the camera
  distance and the 3.2m serving radius is untested by a human.
- **Not measured in a browser.** ~135 nodes in the town, well inside the §7 draw-call
  budget on paper, but the figure that matters is frames on a weak laptop and that has
  not been taken.
- **The town is a grid.** It reads as a street, but there is no route worth planning in
  it yet — no reason to prefer one block over another. That is what M4 is for.
- **Customers are capsules with a shirt colour.** The types exist as names and lines
  only; none of them has its own rule yet.
- **No day timer, no evening, no save.** M3.
