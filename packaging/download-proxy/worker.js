// A download proxy for the hosted site, as a Cloudflare Worker (the free plan is enough). Most hosts of game
// downloads (GitHub releases, Codeberg, itch.io) do not send the CORS headers a browser needs to download a file for
// another site, so the page asks this proxy for those games: GET <worker>/?url=<encoded download address>.
//
// It only fetches the "download" addresses listed in the site's own game list (CATALOG), so it is not an open proxy,
// and it only answers pages from the site (ORIGIN). Each game comes from its author's own release, unchanged.
//
// Settings (Worker variables): CATALOG, the address of the site's games.json (https://<user>.github.io/<repo>/
// games.json); ORIGIN, the site's origin (https://<user>.github.io). Then set "proxy" in site/site.json to
// "https://<worker>.workers.dev/?url=".

const MAX_BYTES = 64 * 1024 * 1024;
const CATALOG_SECONDS = 600;

let allowed = null, allowedAt = 0;
async function allowedDownloads(env) {
  if (allowed && Date.now() - allowedAt < CATALOG_SECONDS * 1000) return allowed;
  const r = await fetch(env.CATALOG, { cf: { cacheTtl: CATALOG_SECONDS } });
  if (!r.ok) throw new Error("the game list could not be read: " + r.status);
  const list = await r.json();
  allowed = new Set((list.games || []).map(g => g && g.download).filter(u => typeof u === "string"));
  allowedAt = Date.now();
  return allowed;
}

function answer(status, body, env, headers = {}) {
  return new Response(body, { status, headers: { "Access-Control-Allow-Origin": env.ORIGIN, "Vary": "Origin", ...headers } });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return answer(204, null, env, { "Access-Control-Allow-Methods": "GET" });
    if (request.method !== "GET") return answer(405, "GET only", env);
    const origin = request.headers.get("Origin");
    if (origin && origin !== env.ORIGIN) return answer(403, "not for this site", env);
    const url = new URL(request.url).searchParams.get("url");
    let list;
    try { list = await allowedDownloads(env); } catch (e) { return answer(502, e.message, env); }
    if (!url || !list.has(url)) return answer(403, "not a game in the site's list", env);

    const r = await fetch(url, { redirect: "follow", cf: { cacheEverything: true, cacheTtl: 86400 } });
    if (!r.ok) return answer(502, "the game's host answered " + r.status, env);
    const size = +r.headers.get("Content-Length") || 0;
    if (size > MAX_BYTES) return answer(413, "too large", env);
    const headers = { "Content-Type": "application/zip", "Cache-Control": "public, max-age=86400" };
    if (size) headers["Content-Length"] = String(size);
    return answer(200, r.body, env, headers);
  },
};
