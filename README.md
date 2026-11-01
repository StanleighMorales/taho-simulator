# Taho Simulator

A 3D browser game. You play **Lolo Ben**, an old taho vendor working a Metro Manila
neighbourhood for 7 days to save up for his granddaughter's graduation photo.

See **[docs/GAME_PLAN.md](docs/GAME_PLAN.md)** for the full design and technical plan.

## Requirements

- Godot **4.7.2-stable** (this machine: `F:\Download\Godot_v4.7.2-stable_win64.exe\`)
- Web export templates for 4.7.2 (installed in `%APPDATA%\Godot\export_templates\4.7.2.stable\`)
- Python 3 (only for the local test server)

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
