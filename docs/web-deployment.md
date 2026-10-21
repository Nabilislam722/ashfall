# Browser deployment

The game remains a normal LÖVE 11.5 project. The web build uses the upstream
`2dengine/love.js` runtime and packages the same Lua, assets, maps, fonts, and
audio into a `.love` ZIP archive.

## Build

From the repository root in PowerShell:

```powershell
pwsh -File scripts/build-web.ps1 -LoveOnly
pwsh -File scripts/build-web.ps1
```

The first command creates `web/game.love`. The second creates that package and
downloads the pinned LÖVE 11.5 runtime files into `web/`.

Both commands also stamp a new build number (`?b=`) onto the style and script
links in `web/index.html`, so browsers fetch the new page files after a
deploy. Always deploy the whole `web/` folder, not only `game.love`: the ☰ menu
lives in the page's top bar (`index.html`, `style.css`, `menu.js`,
`bridge.js`). If an older page without that menu is served, the game draws its
own ☰ in the top-right corner of the canvas instead.

The script pins the upstream `love.js` commit in its `LoveJsRef` parameter. A
runtime update can be tested explicitly with `-LoveJsRef <commit>`.

## Local testing

Do not open the HTML with `file://`. After building, serve the deployment
directory over HTTP:

```powershell
python -m http.server 8000 --directory web
```

Open http://localhost:8000/ in Chrome, Firefox, or Edge. Audio starts after a
browser input gesture, as required by browser autoplay policy.

For production, deploy the contents of `web/` at the placeholder URL
`https://YOUR_DOMAIN/game/`.

## Cloudflare Workers

This repository includes a Wrangler Static Assets configuration. It uploads
`web/` and serves it through the Worker at `/game/`, so the expected public
URL is `https://YOUR_DOMAIN/game/`.

Install Wrangler and authenticate once:

```powershell
npm install --global wrangler
wrangler login
```

Build the browser files and deploy them:

```powershell
pwsh -File scripts/build-web.ps1
wrangler deploy
```

Wrangler reads [wrangler.jsonc](../wrangler.jsonc), uploads `web/`, and uses
[cloudflare/worker.js](../cloudflare/worker.js) to strip the `/game` prefix
before looking up static assets. The Worker adds the required
`Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers only to
the game path.

By default, Wrangler deploys to a `workers.dev` hostname. To use a custom
domain, configure a Worker route or custom domain in the Cloudflare dashboard
and point it at this Worker. Keep the `/game/*` route mapping if the game is
hosted under an existing site; a dedicated hostname such as
`game.YOUR_DOMAIN` can instead serve the same Worker at `/` after changing
`GAME_PREFIX` and the asset URL mapping.

For a repeatable CI deployment, install Wrangler in the CI environment and
run `wrangler deploy` with a Cloudflare API token supplied as the
`CLOUDFLARE_API_TOKEN` secret. Do not commit API tokens to this repository.

## Nginx

Apply the cross-origin isolation headers only to the game location. The MIME
type for WebAssembly must also be present.

```nginx
location /game/ {
    alias /srv/www/legend-of-lua/web/;
    index index.html;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    types {
        application/wasm wasm;
    }
    try_files $uri $uri/ /game/index.html;
}
```

The `love.js` distribution may require `unsafe-eval` in a site-specific
Content-Security-Policy. Review that tradeoff before adding it; do not apply a
site-wide policy solely for this game.

## Expanded map flow

The current map flow now includes:

```text
whispering woods <-> meadow (test) <-> village (Willowbrook) <-> dungeon
```

The new maps are `maps/village.lua` and `maps/dungeon.lua`. The village has two
merchant NPCs, loot, a chest, house collision footprints, and the dungeon
entrance. The dungeon is dark, contains skeletons, bats, chests, and a return
transition. The existing `test.tmx` source also contains the new village exit;
the generated Lua map is what the game loads at runtime.

## Compatibility notes

- `conf.lua` uses a fixed 1920x1080 logical window and disables LÖVE window
  resizing, while CSS scales the canvas responsively.
- Desktop fullscreen and quit actions are skipped when
  `love.system.getOS() == "Web"`.
- Save files continue to use `love.filesystem`; `love.js` persists them in
  browser IndexedDB.
- Asset references are package-relative paths, so they remain valid inside the
  `.love` archive. No absolute filesystem paths are used.
- The project uses WebGL shaders. Shader behavior still depends on browser
  WebGL support, and the upstream runtime is slower than desktop LuaJIT.

## Web3 boundary (Hemi)

`src/utilities/webBridge.lua` is the Lua-facing boundary and `web/bridge.js` is
the browser-facing boundary. They power the Hemi Exchange (gold for HEMI),
on-chain saves at checkpoints, and veHEMI staking at the Mana Well, all through
the player's browser wallet. The Worker also serves the exchange API under
`/game/api/hemi/` (and `/api/hemi/` when the page is opened at the site root).
These need the Worker: to play locally with them, run `npx wrangler dev` and open
http://localhost:8001/ (a plain file server such as `python -m http.server`
serves the game, but the exchange then reports that it is offline). Setup, the
security model and the contracts are described in [hemi-rewards.md](hemi-rewards.md).