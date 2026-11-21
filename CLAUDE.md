# GameSpice Browser

The server browser half: a query client that speaks DQP over UDP, DQP over a WebSocket and A2S, plus a list model with sources, filters, sorting, favourites and history. It ships no window.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/gs_browser/`.** It requires [GameSpice Core](../gs-core) and nothing else (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored). It never names gs-server-query's classes or gs-auth's client.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing a codec, the fan-out, sorting, sources or the WebSocket client: the duplicated DQP codec and its golden fixtures, A2S bots, the fan-out, the decisions that look arbitrary, where it runs, the listing, what is deliberately not here |

## Layout

| Path | What |
| --- | --- |
| `core/gs_browser_target.gd` | `GSBrowserTarget`: an address and a `Protocol` (`AUTO`, DQP, WebSocket, A2S); `is_plausible_host` |
| `core/gs_browser_entry.gd` | `GSBrowserEntry`: one row, in DQP's field names whatever answered |
| `core/gs_browser_filter.gd` | `GSBrowserFilter`: local filtering |
| `query/gs_browser_query.gd` | `GSBrowserQuery`: the base class with `poll(now_ms)` |
| `query/gs_browser_dqp.gd`, `_dqp_client.gd` | `GSBrowserDqp` (the second DQP codec), `GSBrowserDqpClient` (UDP) |
| `query/gs_browser_ws_client.gd` | `GSBrowserWsClient`: DQP over WebSocket; never upgrades the scheme |
| `query/gs_browser_a2s.gd`, `_a2s_client.gd` | `GSBrowserA2s` (`parse_info` subtracts bots), `GSBrowserA2sClient` |
| `runtime/gs_browser.gd` | `GSBrowser`: the node; `concurrency`, refresh, sorting |
| `runtime/gs_browser_favourites.gd` | favourites and history on disk |
| `sources/` | `GSBrowserSource` (`attached(browser)` hook), `GSBrowserSourceList`, `GSBrowserSourceBackbone` + `GSBrowserBackboneConfig` (website-city's `/api/content/server/list`, anonymous HTTP, off with no URL) |
| `examples/browser_selftest.tscn` | the suite; its last section runs the browser against a DQP server on the loopback |
| `examples/backbone_listing.tscn` | the round trip against a real site: reads the listing, queries every row; `--expect=host:port` |

Paths except `examples/` are in `addons/gs_browser/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/browser_selftest.tscn`.

## Rules that bite

- The golden DQP fixtures come from GameSpice Server Query's `GSQueryProtocol`; regenerate them there, never from this codec. [design](docs/design.md#the-deliberate-duplication-and-how-it-is-kept-honest)
- A2S `players` is humans: subtract bots, clamp at zero, and use DQP's field names. [design](docs/design.md#a2s-counts-bots-as-players)
- No compressed A2S multi-packet. [design](docs/design.md#a2s-counts-bots-as-players)
- Fan out with `poll` objects and the `_active`/`_pending` counter, never awaited per-worker signals; check `_refreshing` after `_fill_active()`. [design](docs/design.md#the-fan-out)
- Identity is the game port; a timeout keeps the old counts; unmeasured ping is -1 and sorts last; every sort has a stable tie-break; `unchanged` applies nothing. [design](docs/design.md#decisions-that-look-arbitrary-and-are-not)
- AUTO falls back to A2S on a timeout or parse failure, never on a refusal, and picks WebSocket from `GSPlatform.has_udp()`. [design](docs/design.md#where-it-runs)
- Never upgrade `ws://` to `wss://` from `is_secure_context()`. [design](docs/design.md#where-it-runs)
- Discard every field a listing carries; ask the server. [design](docs/design.md#sources-and-the-sites-listing)
- The backbone source is anonymous HTTP, never GameSpice Auth's client (it prefixes the integration path and sends a server token). [design](docs/design.md#sources-and-the-sites-listing)
- A UDP socket takes only an IP: the UDP clients resolve a name first (`lookup_begin`/`lookup_poll`, IPv4 preferred); an override of `close()` calls `lookup_cancel()`. [design](docs/design.md#sources-and-the-sites-listing)

Deliberately not here: a window, a master server, LAN discovery, connecting. [design](docs/design.md#deliberately-not-here)
