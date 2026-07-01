# llmproxy — a tiny local endpoint-hiding proxy

A single-file, zero-dependency reverse proxy for the Anthropic / Claude API
(works for any HTTP(S) API, really).

Some agents read `ANTHROPIC_BASE_URL` and can tell which router/endpoint you
use. This proxy fixes that: you point the agent at `127.0.0.1`, and the proxy —
which is the only thing that knows your real endpoint — relays every request
upstream. The agent only ever sees localhost.

```
agent  ->  http://127.0.0.1:8787  (llmproxy)  ->  https://your-router
```

## Requirements

- Python 3.7+ (already on every modern Mac as `python3`)
- No `pip install` needed — pure standard library.

## Quick start

```bash
# 1. Start the proxy, pointing it at your real endpoint:
python3 proxy.py --upstream https://your-router.example.com -v

# 2. In the shell where your agent runs:
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
```

That's it. The agent talks to localhost; the proxy relays to your router.

## Options

| Flag | Env var | Default | Meaning |
|------|---------|---------|---------|
| `--upstream` | `LLMPROXY_UPSTREAM` | `https://api.anthropic.com` | Real upstream base URL to relay to. May include a path prefix (e.g. `https://host/anthropic`). |
| `--host` | `LLMPROXY_HOST` | `127.0.0.1` | Local bind address. Keep it on `127.0.0.1` so nothing off your machine can reach it. |
| `--port` | `LLMPROXY_PORT` | `8787` | Local port to listen on. |
| `--api-key` | `LLMPROXY_API_KEY` | *(none)* | Optional. If set, the proxy injects this as the upstream credential (`x-api-key` **and** `Authorization: Bearer …`), so the agent never has to hold your real key either. |
| `-v`, `--verbose` | — | off | Log each proxied request to stderr. |

Example hiding both the endpoint *and* the key from the agent:

```bash
export LLMPROXY_UPSTREAM="https://your-router.example.com"
export LLMPROXY_API_KEY="sk-your-real-key"
python3 proxy.py -v
# agent side — no real key, no real URL:
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
export ANTHROPIC_API_KEY="unused-placeholder"
```

## What it passes through

Method, path, query string, request/response bodies, and headers are forwarded
untouched, **except**:

- The `Host` header is rewritten to the upstream host (so the agent's snooped
  host value never reaches — or comes from — your router).
- Hop-by-hop headers (`Connection`, `Transfer-Encoding`, etc.) are dropped per
  HTTP spec.
- If `--api-key` is set, the upstream credential is injected here.

Streaming responses (Server-Sent Events, used by the Messages API when
`stream: true`) are relayed live, chunk by chunk — nothing is buffered.

## Run it automatically at login (macOS `launchd`)

1. Edit the paths and your upstream URL below, save as
   `~/Library/LaunchAgents/com.local.llmproxy.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key>
     <string>com.local.llmproxy</string>
     <key>ProgramArguments</key>
     <array>
       <string>/usr/bin/python3</string>
       <string>/ABSOLUTE/PATH/TO/local-api-proxy/proxy.py</string>
       <string>--upstream</string>
       <string>https://your-router.example.com</string>
     </array>
     <key>EnvironmentVariables</key>
     <dict>
       <key>LLMPROXY_API_KEY</key>
       <string>sk-your-real-key</string>
     </dict>
     <key>RunAtLoad</key>
     <true/>
     <key>KeepAlive</key>
     <true/>
     <key>StandardErrorPath</key>
     <string>/tmp/llmproxy.log</string>
   </dict>
   </plist>
   ```

2. Load it:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.local.llmproxy.plist
   ```

   To stop: `launchctl unload ~/Library/LaunchAgents/com.local.llmproxy.plist`.

> Putting the API key in a plaintext plist is convenient but not secure. If you
> care, drop `EnvironmentVariables` and export `LLMPROXY_API_KEY` from your
> shell profile, or leave the key with the agent instead.

## Notes & limits

- **Localhost only by design.** Binding to `127.0.0.1` means no other device can
  reach the proxy. Don't expose it on `0.0.0.0` unless you know what you're doing.
- **No timeout on responses** so long-idle SSE streams aren't cut off.
- One process handles concurrent requests via threads; it's meant for a single
  user on one machine, not high load.
- The upstream TLS certificate is verified using your Mac's system trust store
  (standard `urllib` behavior).
