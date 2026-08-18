# Slimer — website

The public page for the game: a WebGL explainer, the playable browser build, and
the desktop downloads. Plain static files — no framework, no build step, no
dependencies, and no network requests to anything but this origin.

```
site/
├── index.html          the explainer, one long scroll
├── play/index.html     click-to-load gate for the Godot web export
├── play/engine/        generated — copy of ../build/web
├── css/site.css
├── js/
│   ├── gl.js           WebGL2 instanced-sprite renderer + scene lifecycle
│   ├── data.js         game constants, transcribed from game/data/*.gd
│   ├── config.js       download URLs — the one place to edit after a release
│   ├── site.js         page wiring
│   └── scenes/         hero, roster, telegraph, forestgen (WebGL); budget (2D)
├── assets/             generated — atlas, screenshots, icons, music
├── tools/
│   ├── build_site.py   regenerates everything under assets/ and play/engine/
│   └── serve.py        local dev server, caching disabled
└── vercel.json         wasm MIME type and cache headers
```

## Working on it

```bash
python3 site/tools/build_site.py     # regenerate assets (safe to re-run)
python3 site/tools/serve.py 8181     # http://localhost:8181
```

`build_site.py` reads from `../game/assets/`, `../build/web/` and the visual-pass
screenshots in
`~/Library/Application Support/Godot/app_userdata/Slimer/shots`. It only ever
writes to `site/assets/` and `site/play/engine/`. If the screenshots are missing,
regenerate them:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game --resolution 1600x900 -- visual
```

Use `serve.py` rather than `python3 -m http.server`: the stock server honours
`If-Modified-Since`, so an edited module keeps serving from the browser cache and
you end up debugging a stale page.

## Deploying

```bash
cd site && vercel deploy --prod
```

About 60 MB, almost all of it `play/engine/index.wasm` (42 MB, ~12 MB after the
edge's brotli). The desktop builds are **not** in the deploy — they are ~240 MB
and live as GitHub release assets instead. After tagging a new release, update
`VERSION` and the sizes in `js/config.js`.

The web export was built with thread support off, so **no COOP/COEP headers are
required** for the browser build to run.

## Two things to know before editing

**`js/data.js` is a transcription, not a source of truth.** Every number on the
page comes from the game's real data tables (`game/data/*.gd`). If the game is
retuned, that file has to be re-checked — each block names where it came from.
Note that `game/GAME_GUIDE.md` has a few stale counts that contradict the code;
the code wins.

**The enemy cards are drawn over a shared canvas.** `.enemy`'s background
gradient in `site.css` is what lets each mini-sim show through, and it must stay
fully transparent across the whole band the actors move in — see `SIM_BAND` in
`js/scenes/roster.js`. Darken it and the sims silently vanish behind the cards.

## Licensing

The page displays art derived from GDQuest's *Your First 2D Game With Godot 4*
pack, which is **CC BY-NC-SA 4.0**. The attribution block in the footer is
required, is copied verbatim from `../game/LICENSE-ASSETS.md`, and must not be
trimmed. NonCommercial covers modified assets too, so this site must never carry
ads, affiliate links, a paid tier, or a buy button. The site's own code is MIT.
