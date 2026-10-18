# Download proxy (optional)

The hosted site plays games it hosts itself (`site/games.tsv`) and links to games it cannot redistribute
(`site/links.tsv`). A linked game that has a direct download (a GitHub release, say) can be played from the
catalog in one click, but browsers only allow that download when its host sends CORS headers, and GitHub,
Codeberg and itch.io do not. This Cloudflare Worker fetches those downloads for the page.

- It only fetches the `download` addresses in the site's own `games.json`, so it is not an open proxy.
- It only answers the site's own origin.
- The game comes from the author's own release, unchanged; nothing is stored apart from Cloudflare's cache.

Without it, the catalog shows a "Play" button that reports the host refused, and the "Source and license" link
leads to the author's page, from which the game can be downloaded and opened in the page by hand.

## Setting it up

1. Edit `wrangler.toml`: `CATALOG` is the address of the site's `games.json`, `ORIGIN` the site's origin.
2. `npx wrangler deploy` (a free Cloudflare account is enough).
3. Set `"proxy": "https://cranked-poc-downloads.<account>.workers.dev/?url="` in `site/site.json`.

Proxying is still distributing a copy, even if it is the author's own file: only list games whose licenses allow
redistribution, or whose authors agreed. See `site/links.tsv`.
