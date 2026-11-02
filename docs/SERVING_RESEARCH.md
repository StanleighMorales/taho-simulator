# Making the serving hands-on — research and proposals

Written 2026-11-03, after M1. The brief: *"a more accurate experience with the whole
scooping, putting things more hands on."*

This document is in two halves. §1–2 are what the real thing involves and where the game
currently diverges from it. §3–5 are the diagnosis of why it does not feel hands-on and
what to change, ranked. §6 is what not to do.

---

## 1. How taho is actually served

Sourced below. Where sources disagree or are thin, it says so — the point of this section
is to be checkable, not confident.

### The kit
- **Two containers on a bamboo shoulder pole** (*pingga*). The **larger holds the tofu
  base and nothing else**; the **smaller holds the arnibal, the sago, and the cash box**.
  Described variously as aluminium or stainless, and as insulated.
- **The tofu bucket has a hinged lid in the centre.**
- **Two tools, not one.** A **wide, shallow metal scoop** for the tofu, and a **long, thin
  metal ladle with a tiny bowl** for the sago and the arnibal.
- **Plastic cups in two sizes**, plastic spoons, sometimes straws.

### The act
1. The scoop **skims the surface** of the tofu, **lifting thin layers**, and excess liquid
   is tossed out rather than poured into the cup.
2. Thin layers go into the cup. Soft/silken tofu only — firm is too dense to lift in
   sheets, and keeping the sheets intact is the whole skill.
3. **Sago, then arnibal**, both from the small bucket with the thin ladle.
4. **A quick swirl** with the ladle to loosely mix — *loosely* is the word the sources use.
5. Eaten with a spoon, sipped through a straw, or drunk straight from the cup.

Sources split on whether the layers **alternate** (tofu, syrup, sago, repeat) or whether
the cup is filled with tofu and then topped. Vendor-observation accounts lean toward
fill-then-top; home recipes lean toward alternating. Both are defensible.

### The day
Vendors prepare **before dawn**, walk a **regular route on a regular schedule**, call
*"Tahooo"*, and work until dusk or until supplies run out. Taho is **served warm**, though
some prefer it cold.

### Two things this game asserts that the research does not confirm
- **"Whey."** The game's step 1 and its comments call the liquid on top whey. Sources
  describe "excess water" or "excess liquid" being skimmed off and discarded; none of them
  says whey. Taho is made from silken tofu, where the curd is set in its own liquid. The
  *mechanic* (skim the surface, toss the liquid, don't dig into the tofu) is confirmed; the
  *word* is not. Worth softening in the comments to "the water on top".
- **The single bucket.** There is no single-bucket vendor in any source. The game's
  serving scene has one bucket doing all three jobs.

---

## 2. Where the game diverges

| The real thing | `serving_view.tscn` today |
|---|---|
| Two buckets on the ground, one tofu, one sago + arnibal + cash | One bucket on a table |
| Hinged lid, opened to start | No lid |
| Two tools: wide flat scoop, thin small ladle | One ladle for everything |
| Sago and arnibal come **out of the small bucket** | Sago and arnibal come from nowhere |
| Cash box lives in the small bucket | No cash handling at all |
| The bucket empties over the day | Resets to full every customer |
| Served warm | No steam, no heat |
| Two cup sizes | One cup |
| Loosely mixed, by eye | Mixed to a target on a gauge |

The order of operations the game already has — skim, tofu, sago, arnibal, swirl, serve —
**matches the vendor accounts**. That part is right and should not be touched.

---

## 3. Why it does not feel hands-on

This is the actual answer to the question. The six steps are well-built; the problem is
not polish, it is that **the player is not manipulating objects, they are performing
gestures that are being graded.** Four specific causes, in order of how much they matter.

### 3.1 The ladle is a cursor, not an object
`serving_view.gd`'s `set_ladle(active, u, depth)` teleports the ladle to wherever the
pointer is, every frame, exactly. There is no mass, no lag, no follow-through, no
resistance when it enters the liquid. The pointer *is* the ladle, so there is nothing
between the player's hand and the result — and therefore nothing to feel.

Game-feel writing identifies exactly this: the tactile impression comes from how objects
"collide, rebound, deform, or resist movement". The current ladle does none of the four.

**This single thing is most of the answer.** A tool that lags the pointer by 60–90ms,
gets heavier as it fills, and visibly drags through the liquid will feel hands-on even
with no other change.

### 3.2 The material is a number, not a substance
`ShaveStep` reads `absf(rel.x)` and converts speed into `fill`. The tofu in the bucket is
one cylinder that scales; the tofu in the cup is another cylinder that scales. Nothing is
*taken from* anywhere and *put* anywhere else.

So the player cannot form a mental model of the stuff. They cannot scoop from the near
side because the far side is running low; they cannot see the trench their last scoop
left. The action has no consequence in the world, only in a score.

### 3.3 The buckets forget
`_start_customer()` calls `_reset_visuals()`, which sets the water back to 1.0 and the cup
back to empty. Meanwhile `GameState.tofu` counts cups down from 12. **The two are not
connected.** The bucket you are looking at is not the bucket you are carrying.

This is a free win: the real difficulty curve of a taho round is that the level drops all
day, you reach further and further down, and the last cup out of a load is genuinely
awkward to lift. That is the same kind of difficulty as the rebuilt step 1 — difficulty
that comes from the physical situation rather than a tuning constant, which §11 of the
plan already identifies as the better kind.

### 3.4 The information is on the HUD, not in the cup
Every step publishes a `gauge()` and a `gauge_target()`. The player watches a bar at the
bottom of the screen and stops when the marker lines up. They are not looking at the taho.

The fix is **not** to delete the HUD. A study that stripped the HUD from *Battlefield 3*
found it was not a universal improvement and that expert players sometimes preferred
having it. The useful framing from diegetic-UI writing is: **list every piece of
information the player needs and ask where it would live in the fiction.** Then put it
there, and let the HUD fade as the player stops needing it.

- Fill level → the cup is transparent. It is already visible. Delete that gauge.
- Sago amount → the pearls are visible on the surface. Delete that gauge.
- Arnibal level → the colour of the stream and the darkening of the cup.
- Swirl → the marbling shader *is* the gauge. This is the one that most obviously should
  not have a bar next to it.
- Water remaining → already readable, since the puddle shrinks and uncovers white tofu.

Per the plan's difficulty ramp, day 1 keeps the bars as a tutorial and they fade out over
days 2–3. That satisfies both the immersion argument and the study's caution.

---

## 4. The changes, ranked

Ranked by felt-improvement per hour of work. The first three are the ones that answer the
question as asked.

### 1. Give the tools weight — ✅ **done, 2026-11-03**
Make `set_ladle` drive a **target** that the ladle chases, instead of a position it
snaps to.

- Critically-damped spring toward the pointer, ~60–90ms to settle.
- The ladle **tilts** into the direction of travel and lags behind on the turn.
- **Drag in the liquid**: below the surface, the chase is slower and the tilt is larger.
  Entering and leaving the liquid is the moment that should feel like something.
- A full scoop is **heavier** than an empty one — more lag on the way out than the way in.
- Shaving tofu **resists**: the stroke slows slightly as it bites, which is what makes a
  smooth stroke feel earned instead of measured.

Everything here lives in `serving_view.gd`. The steps keep reading the pointer and stay
testable; what changes is the gap between the pointer and the thing.

**What shipped.** A critically damped spring (the closed form, so a 40ms browser frame
cannot destabilise it) drives the tool toward the pointer: ~55ms in air, nearly three
times that through material, plus more again as the scoop fills — so lifting a full scoop
out costs more than dipping an empty one in. It leans into the turn with its leading edge
up, the way a ladle planes rather than ploughs, and comes level when it stops.
`tests/feel_tests.tscn` locks all of that in by comparing trials, not by pinning numbers.

**Three things building it turned up:**
- **The ladle was being positioned in the wrong space.** `set_ladle` wrote a *global* y
  into a *local* position. Harmless while the serving view sat at the origin, and badly
  broken the moment M1 instanced it into the town at an offset — the tool was 60m under
  the map, and `ServeStep`'s cup drag was solving against a plane 60m above the table.
  Fixed by putting the view back at the origin (the town is hidden while serving anyway,
  so the offset bought nothing) *and* by making `set_ladle` local-space correct.
- **A submerged tool is invisible.** Below the water line the scoop is behind the
  bucket's near wall, so during the step that is *about* the tool you cannot see it. This
  is an argument for item 2 — a real tofu surface the scoop sits *on* — and for a
  shallower camera angle.
- **Weight you cannot see is worth nothing.** The ladle was a 1.7cm grey disc; several
  degrees of lean on a disc is invisible. It is now a wide shallow metal scoop with a
  handle — which is what the vendor accounts describe anyway — and the handle is what
  makes the lean legible.

### 2. Make the tofu a surface, not a cylinder
Replace the bucket's tofu cylinder with a **heightfield** — a modest grid, 16×16 is plenty
— that the scoop actually lowers where it passes.

- Scoop across the near side and the near side goes down. The trench stays.
- The next scoop from the same place gets less, so you learn to work the bucket evenly.
- The cup fills with **discrete slabs**, not a scaling cylinder: each stroke lays one
  visible sheet, and you can see four or five of them stacked. That is the single most
  recognisable image in taho and the game does not currently show it.
- Scoring falls out of the simulation: evenness of the remaining surface is a better
  measure of a good vendor than frame-to-frame jerk, and it is one the player can see.

This is the expensive one. It is also the one that turns "gesture" into "material".

### 3. Two buckets, two tools, one lid — ✅ **done, 2026-11-03**
Straight accuracy, and each piece adds a verb.

- **Open the lid** to start the order. One drag. It is the moment the steam comes out, it
  tells the player the taho is warm, and it is how a real serve begins.
- **The big bucket** is tofu only. **The small bucket** holds sago and arnibal in their own
  compartments, and the cash box.
- **Two tools**: the wide flat scoop for steps 1–2, the thin small ladle for steps 3–5.
  Picking up the right one is a real choice with a real cost in time.
- **Reaching into the small bucket for the sago** is more hands-on than sago appearing in
  the cup because you tapped.

**What shipped.** The table now holds both buckets: the big one is tofu and a hinged lid,
the small one has sago and arnibal in their own compartments and the cash box sitting in
front of it. Opening the lid is a new step 0 — one upward drag, ungraded on purpose
(`Grading.WEIGHTS` gives it 0.0, because opening a lid is not a skill and scoring it would
only add noise) — and it is the moment the steam comes out, which is the only way the
player learns the taho is warm. The weight work from item 1 moved into a `ToolBody` class
so there can be two tools with different numbers: the wide scoop for steps 1–2, and a thin
dipper for the sago, the arnibal and the swirl, which is quicker in the hand and barely
weighs anything full. The pour stream now falls from wherever the dipper is instead of
from a fixed spout, and the small bucket's two levels are read from `GameState`, so a heavy
hand on one customer is visible to the next.

**What building it turned up:**
- **Steps 3, 4 and 5 had no tool on screen at all** — the same gap the shave step had
  before item 1. You were adding sago, pouring syrup and stirring with an invisible hand.
- **`amount_ratio` is GPU-particles only.** The steam is CPU particles, because those are
  the ones certain to work in Compatibility on the web, so the intended burst-then-settle
  is not available — changing `amount` restarts the system and pops. It is a steady wisp
  for now; a proper burst wants a second one-shot emitter.
- **Billboarded flat cards render wrong as CPU particles** here — one came out as an
  opaque black square. A six-segment sphere costs nothing at twelve particles and has no
  orientation to get wrong.
- **A lid stopped anywhere near upright is a 27cm disc across the camera.** It has to fold
  right back behind the bucket, which is also what a hinged lid does.

### 4. Connect the big bucket to the inventory
*(The small bucket's sago and arnibal already do this, as of item 3. What is left is the
tofu.)*
`set_bucket_water` / the tofu level should read from `GameState.tofu`, not reset per
customer. Twelve cups out of a load means the surface is visibly lower on cup 11 than on
cup 2, and the refill at home becomes something you can *see* the need for rather than
read in a number.

Cheap. Large effect on the roaming loop as well as the serving one.

### 5. Hold the cup
The player never touches the cup until step 6. In reality it is in your other hand the
whole time, and you tilt it toward the ladle.

With one pointer, the honest version is: the cup sits where your off-hand holds it, and it
**reacts** — it tips slightly toward the ladle as you bring tofu over, it settles when you
let go, it rings when the ladle taps the rim. Not a second control, just a second thing
that is alive.

### 6. Let the steps bleed into each other
Drop the hard `1/6` gating and the forced order. Let the player add a little more arnibal
after they have started swirling, the way anyone actually would. The grade is already
computed from per-step scores, so the scoring survives; what changes is that the player is
doing a task rather than clearing stages.

Keep the step *titles* as coaching on day 1, then let them go quiet.

### 7. Warmth, and the things that come with it
Steam from the open bucket, heavier in the first second after the lid comes off.
Condensation on the cup. The cup warming the hand. This is cheap and it is most of what
"served warm" means to a player.

### 8. Make change
The cash box is in the small bucket. Counting out coins is a hands-on verb the game has no
version of, and §5 of the plan already wants the kid counting exact coins. A drawer with
coins in it that you pick from is a better ending to an order than a number going up.

---

## 5. What this buys per pillar

- **"The pour is the game."** 1, 2 and 5 are all about making the pour feel like matter.
- **"Short sessions."** None of this lengthens an order; weight and resistance cost
  milliseconds, not seconds.
- **"Runs on a cheap laptop."** The heightfield is the only item with a real cost. A 16×16
  grid is 256 verts — nothing. Keep it off `MultiMesh` and on a single `ArrayMesh` that is
  rewritten on change, not per frame.
- **"Warm, not grim."** The lid, the steam and the coin drawer are all warmth.

---

## 6. What not to do

- **Do not delete the HUD wholesale.** Fade it with the difficulty ramp instead. The
  evidence on HUD removal is genuinely mixed and it depends on player expertise.
- **Do not add a second simultaneous pointer.** It breaks the phone, which §1 of the plan
  treats as non-negotiable.
- **Do not simulate fluid.** Arnibal needs to *look* thick and lag the release; it does not
  need particles. The current drip model already gets the important part right.
- **Do not reorder the steps.** The current order matches the vendor accounts.
- **Do not make it harder.** Every item above is about *feel*, not difficulty. Pillar 3
  says you can have a bad day but cannot lose; weight and resistance must not become a
  precision test.
- **Do not do item 2 before item 1.** The heightfield is a week; the spring is an evening,
  and it may turn out to be most of what was missing.

---

## 7. Sources

- [Taho — Wikipedia](https://en.wikipedia.org/wiki/Taho) — two containers, hinged centre
  lid on the tofu bucket, the thin ladle, loose mixing, served warm, spoon/straw.
- [Taho — wikidoc](https://www.wikidoc.org/index.php/Taho) and
  [Taho facts for kids — Kiddle](https://kids.kiddle.co/Taho) — the wide shallow scoop
  skimming the surface, the long thin ladle with a tiny bowl.
- [Taho Vendor in Manila — travelbubu](https://travelbubu.com/spots/taho-vendor/) —
  insulated buckets on a bamboo pole, one for tofu and one for toppings.
- [What Is Taho? — Studio Tributes](https://blog.studiotributes.com/post/what-is-taho) —
  larger bucket for the tofu base, smaller for arnibal, sago and cash box; preparation
  before dawn, regular route.
- [Good Morning, Good Taho! — juancarlo.ph](https://juancarlo.ph/good-morning-taho/) and
  [Food Trip: Taho](https://www.thebackpackadventures.com/2013/07/food-trip-taho.html) —
  vendor-observed order of assembly, the quick swirl, cup sizes.
- [Taho — The Little Epicurean](https://www.thelittleepicurean.com/taho/) and
  [Deliciously Rushed](https://deliciouslyrushed.com/taho/) — lifting thin intact sheets,
  layering, keeping the scoop wet.
- [Mikha Eats](https://mikhaeats.com/filipino-taho-recipe/) — silken only, firm is too
  dense.
- [Game feel — Wikipedia](https://en.wikipedia.org/wiki/Game_feel) — collide, rebound,
  deform, resist; test the most basic mechanic on its own.
- [Removing the HUD: non-diegetic elements and expertise](https://eprints.whiterose.ac.uk/id/eprint/130581/1/Diegesis_and_immersion_final.pdf)
  — HUD removal is not a universal improvement and interacts with expertise.
- [Beyond the HUD — Wayline](https://www.wayline.io/blog/diegetic-interfaces-game-design)
  — list every piece of information and ask where it would live in the fiction.
- [Hakka Kitchen (arXiv)](https://arxiv.org/html/2607.26183v1) — controller mediation
  disconnects players from direct physical practice; hand tracking and physics-based
  manipulation instead.
- [Designing Controlled Chaos — BarStuds](https://barstuds-studios.itch.io/cover-my-buns/devlog/1489732/designing-controlled-chaos-building-a-physical-cooking-game-that-fights-back)
  — removing automation so small mistakes escalate; friction as the gameplay.
