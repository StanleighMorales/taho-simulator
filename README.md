# Taho Simulator

A 3D browser game. You play **Lolo Ben**, an old taho vendor working a Metro Manila
neighbourhood for 7 days to save up for his granddaughter's graduation photo.

Walk the street, find whoever is shouting for taho, set the buckets down on the pavement
and serve them: pick the P10, P20 or P50 cup they asked for and open the lid, then work the
two buckets in any order you like. The scoop goes where your hand pushes it: drag down
and it goes down through the water easily, then all but stops when it meets the tofu.
It takes whatever it touches: water while there is water on top, sheets of tofu once
there is not, and pushing down while you sweep bites deeper, which fills it faster but
rougher. Pull up (or off the side of the bucket) to lift it out, and let go where you
want it tipped. Go back for more tofu after the syrup if the cup looks short.
The order ends when you drag the cup to the customer, who tells you what was wrong with
it. When the buckets run dry, walk home and refill.

**Controls:** WASD / arrows to walk, or tap the ground to walk there · drag to look ·
`E` (or tap a customer you are standing next to) to serve. Everything in the serving
minigame is press / drag / release, so it plays the same with a mouse or a finger.

**Play it: https://stanleighmorales.github.io/taho-simulator/**

See **[docs/GAME_PLAN.md](docs/GAME_PLAN.md)** for the full design and technical plan.

## Requirements

- Godot **4.7.2-stable** (this machine: `F:\Download\Godot_v4.7.2-stable_win64.exe\`)
- Web export templates for 4.7.2 (installed in `%APPDATA%\Godot\export_templates\4.7.2.stable\`)
- Python 3 (only for the local test server)

## Run the tests

```sh
godot --headless --script res://tests/run_step_tests.gd
```

```sh
godot --headless res://tests/town_tests.tscn
```

```sh
godot --headless res://tests/feel_tests.tscn
```

The first is 111 assertions covering the tofu surface, every tool's mechanic, the free-order
routing, and the grading. They assert the *intent* of each mechanic (smooth beats jerky,
water on the street beats water in the cup, stopping at full beats piling on, a P50 cup is
more trips than a P10, tofu can still go in after the sago), so a tuning change that breaks
the point of one fails the suite.

The third is 17 assertions on how the tools *feel* — that the ladle lags the hand,
drags in material, gets heavier as it fills and leans into the turn. Each one compares two
runs of the same movement rather than pinning a number, so tuning stays free to move while
the intent does not.

The second is 27 assertions over the roaming layer: the town builds, customers appear,
standing next to one offers a sale, the switch into the serving view and back works, and
the money and supplies move the right way. It runs as a **scene**, not with `--script` —
a custom main loop does not register the `GameState` autoload that both it and the code
under test need. The feel tests run as a scene for the same reason and because the springs
integrate in `_process`, so they need real frames.

## Build and run the web export

```sh
godot --headless --export-release "Web" build/web/index.html
python tools/serve_web.py          # then open http://127.0.0.1:8060/
```

A Godot web build cannot be opened over `file://` — it must be served over HTTP.

## Non-negotiable project settings

Two settings are load-bearing for "anyone can play it in a browser". Don't change them
without reading §1 of the plan:

- **Renderer must be Compatibility** (`gl_compatibility`). Forward+ and Mobile do not
  export to web at all.
- **Thread support must stay off** (`variant/thread_support=false` in `export_presets.cfg`).
  Thread-enabled builds require `COOP`/`COEP` response headers, which GitHub Pages cannot
  set.

## Deployment

`.github/workflows/deploy-web.yml` builds and publishes to GitHub Pages on every push to
`main`. For itch.io, zip the contents of `build/web/` with `index.html` at the root.
