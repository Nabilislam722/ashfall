import { handleHemiApi } from "./hemiRewards.js";

// the Hemi Exchange ledger (a Durable Object class must be exported from the Worker)
export { ExchangeLedger } from "./ledger.js";

const GAME_PREFIX = "/game";
// the exchange API sits next to the page: /game/api/hemi/, or /api/hemi/ when
// the page is opened at the site root (static files are served there too)
const API_PATH = /^(?:\/game)?\/api\/hemi\//;

export default {
  async fetch(request, env) {
    const requestUrl = new URL(request.url);

    const api = requestUrl.pathname.match(API_PATH);
    if (api) {
      const route = requestUrl.pathname.slice(api[0].length);
      try {
        return await handleHemiApi(request, env, route);
      } catch (error) {
        console.error(error);
        return new Response(JSON.stringify({ ok: false, error: "Server error" }), {
          status: 500,
          headers: { "content-type": "application/json" }
        });
      }
    }

    if (!requestUrl.pathname.startsWith(GAME_PREFIX)) {
      return new Response("Not found", { status: 404 });
    }

    requestUrl.pathname = requestUrl.pathname.slice(GAME_PREFIX.length) || "/";
    const assetRequest = new Request(requestUrl, request);
    const assetResponse = await env.ASSETS.fetch(assetRequest);
    const headers = new Headers(assetResponse.headers);
    headers.set("Cross-Origin-Opener-Policy", "same-origin");
    headers.set("Cross-Origin-Embedder-Policy", "require-corp");
    // the page and game files change on every deploy: always check for a new copy
    if (/(\/|\.html|\.css|\.js|\.love)$/.test(requestUrl.pathname)) {
      headers.set("Cache-Control", "no-cache");
    }

    return new Response(assetResponse.body, {
      status: assetResponse.status,
      statusText: assetResponse.statusText,
      headers
    });
  }
};
