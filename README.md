# push-kitchen

After subscribing, the screen makes no tool call; the server says the queue moved and the screen re-reads it.

Article: [the-screen-that-never-asks](https://makemind.dev/en/build/the-screen-that-never-asks)

## What is here

- `kitchen_server/` — Dart MCP server (`mcp_server` from pub.dev). It holds the data and the tools and serves the app's pages as `ui://` resources.
- `kitchen.mbd/` — the app as a folder of JSON: `manifest.json` and the pages under `ui/`. No build step.
- `captures/` — screenshots taken from AppPlayer by `verify.py`.
- `verify.py`, `verify.sh` — the check.

## Open it in AppPlayer

Start the server in shared mode: `dart run bin/server.dart --http=8767` in `kitchen_server/`. Add a server app with URL `http://localhost:8767/mcp` (streamable HTTP). More than one player can join the same server; that is the point of this sample.

## Verify

```bash
bash verify.sh
```

Needs AppPlayer with the debug MCP on (see `tools/README.md`). The script builds what needs building, drives the player through the screens above, asserts the claim at the top of this file, and writes `captures/`.
