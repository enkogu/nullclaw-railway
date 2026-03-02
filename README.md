# nullclaw-railway

Railway-ready repository for running [nullclaw](https://github.com/nullclaw/nullclaw) as a long-lived gateway service.

This repo builds `nullclaw` from source in Docker, bootstraps `~/.nullclaw/config.json` from environment variables, and starts:

```bash
nullclaw gateway --host 0.0.0.0 --port $PORT
```

## What this deploys

- Upstream source: `https://github.com/nullclaw/nullclaw`
- Default pinned ref: `4101f63` (change with Docker build arg `NULLCLAW_REF`)
- Applies local patch: `patches/0001-subagent-wakeup.patch`
  - subagent completion wakes the main session
  - reply is routed back to the original channel/chat (including Telegram)
  - subagent execution uses the provider runtime stack (fixes `ProviderError` on Anthropic-style providers)
- Health endpoint: `/health`

## Deploy on Railway

1. Create a new Railway project from this GitHub repository.
2. Add environment variables (see below).
3. Deploy.
4. Optional but recommended: mount a volume at `/data`.

Reference template for full browser + web-search config:
- `config.browser-web.example.json`

Railway env formatting:
- Use raw values without quotes in the Railway Variables UI.
- Example: `NULLCLAW_PROVIDER=anthropic` (not `"anthropic"`).

## Required env

Use one:

- `NULLCLAW_API_KEY`
- or provider-specific key matching `NULLCLAW_PROVIDER`:
  - `OPENROUTER_API_KEY`
  - `OPENAI_API_KEY`
  - `ANTHROPIC_API_KEY` / `ANTHROPIC_OAUTH_TOKEN`

Common:

- `NULLCLAW_PROVIDER` (default: `openrouter`)
- `NULLCLAW_MODEL` (optional)
- `PORT` (default: `3000`)
- `NULLCLAW_REWRITE_CONFIG` (`true` to regenerate config once, then set back to `false`)

## Claude/OpenAI subscription auth

### Anthropic subscription token

- `NULLCLAW_PROVIDER=anthropic`
- `ANTHROPIC_OAUTH_TOKEN=sk-ant-oat01-...`

Notes:
- `sk-ant-oat01-...` OAuth tokens can work with nullclaw Anthropic provider.
- Token validity is quota/rate-limit dependent; if you hit `error.RateLimited`, refresh token or use fallback providers.

### OpenAI Codex OAuth flow

- `NULLCLAW_PROVIDER=openai-codex`
- `OPENAI_CODEX_ACCESS_TOKEN=...`
- `OPENAI_CODEX_REFRESH_TOKEN=...` (recommended)
- `OPENAI_CODEX_EXPIRES_AT=<unix_epoch_seconds>` (optional)

## Feature packs

### Telegram + audio

- `TELEGRAM_BOT_TOKEN=...`
- `TELEGRAM_ALLOW_FROM=*` (or CSV allowlist)
- `TELEGRAM_ACCOUNT_ID=main`
- `TELEGRAM_GROUP_ALLOW_FROM=...` (optional CSV)
- `TELEGRAM_GROUP_POLICY=allowlist|open|disabled`

Audio:

- `NULLCLAW_AUDIO_ENABLED=true`
- `NULLCLAW_AUDIO_PROVIDER=groq|openai`
- `NULLCLAW_AUDIO_API_KEY=...` (or provider key env var)
- Optional: `NULLCLAW_AUDIO_MODEL`, `NULLCLAW_AUDIO_LANGUAGE`, `NULLCLAW_AUDIO_BASE_URL`

### Memory

- `NULLCLAW_MEMORY_BACKEND=sqlite|markdown|postgres|none` (default in this repo: `sqlite`)
- `NULLCLAW_MEMORY_AUTO_SAVE=true|false`
- `NULLCLAW_MEMORY_PROFILE=...` (optional)
- `NULLCLAW_MEMORY_SEARCH_ENABLED=true|false`
- `NULLCLAW_MEMORY_SEARCH_PROVIDER=none|openai|...`
- `NULLCLAW_MEMORY_SEARCH_MODEL=text-embedding-3-small` (optional)
- `NULLCLAW_MEMORY_API_KEY=...` (optional override)

### Web search + HTTP tool

- `NULLCLAW_HTTP_ENABLED=true|false` (default: `true`)
- `NULLCLAW_WEB_SEARCH_PROVIDER=auto|searxng|duckduckgo|brave|firecrawl|tavily|perplexity|exa|jina`
- `NULLCLAW_WEB_SEARCH_BASE_URL=https://...` (optional, for SearXNG)
- `NULLCLAW_WEB_SEARCH_FALLBACK_PROVIDERS=provider1,provider2` (optional CSV)
- `NULLCLAW_HTTP_ALLOWED_DOMAINS=domain1,domain2` (optional CSV)

Provider API keys (when relevant): `BRAVE_API_KEY`, `FIRECRAWL_API_KEY`, `TAVILY_API_KEY`, `PERPLEXITY_API_KEY`, `EXA_API_KEY`, `JINA_API_KEY`.

### Browser tool

- `NULLCLAW_BROWSER_ENABLED=true|false`
- `NULLCLAW_BROWSER_BACKEND=agent_browser|...`
- `NULLCLAW_BROWSER_NATIVE_HEADLESS=true|false`
- `NULLCLAW_BROWSER_NATIVE_WEBDRIVER_URL=http://127.0.0.1:9515`
- `NULLCLAW_BROWSER_NATIVE_CHROME_PATH=/path/to/chrome` (optional)
- `NULLCLAW_BROWSER_SESSION_NAME=...` (optional)
- `NULLCLAW_BROWSER_ALLOWED_DOMAINS=example.com,openai.com` (CSV; enables `browser_open` allowlist)

Important:
- Built-in `browser` tool supports `open` and `read`.
- `click`/`type`/`scroll` require a CDP-capable backend (not built into this nullclaw version).

### PinchTab + noVNC (Human Login + Agent Reuse)

This image runs PinchTab inside the same container as nullclaw:

- PinchTab API/dashboard: `:9867`
- noVNC (browser login UI): `:6080` (`/vnc.html`)
- nullclaw gateway: `:3000` (or proxied through `caddy` for single-port platforms)

Recommended env:

- `PINCHTAB_ENABLED=true`
- `PINCHTAB_BIND=0.0.0.0`
- `PINCHTAB_PORT=9867`
- `PINCHTAB_STATE_DIR=/data/.pinchtab` (persist with mounted volume)
- `PINCHTAB_HEADLESS_DEFAULT=true`
- `PINCHTAB_NOVNC_ENABLED=true`
- `PINCHTAB_DISPLAY=:99`
- `PINCHTAB_SCREEN=1280x720x24`
- `PINCHTAB_VNC_PORT=5900`
- `PINCHTAB_NOVNC_PORT=6080`
- `PINCHTAB_NOVNC_PUBLIC_PATH=/novnc` (recommended on Railway/single public port)
- Optional security:
  - `PINCHTAB_TOKEN=<api-token>`
  - `PINCHTAB_VNC_PASSWORD=<vnc-password>`

Profile-based login flow (headed -> headless with preserved sessions):

```bash
# 1) Start profile instance in headed mode
curl -X POST http://localhost:9867/instances/start \
  -H "Content-Type: application/json" \
  -d '{"profileId":"user-123","mode":"headed"}'

# 2) User opens noVNC and logs in manually
# Direct port:   http://<host>:6080/vnc.html?autoconnect=1&resize=scale
# Railway proxy: https://<host>/novnc/vnc.html?autoconnect=1&resize=scale

# 3) Stop headed instance
curl -X POST http://localhost:9867/instances/<instance-id>/stop

# 4) Start same profile in headless mode (session reused)
curl -X POST http://localhost:9867/instances/start \
  -H "Content-Type: application/json" \
  -d '{"profileId":"user-123","mode":"headless"}'

# 5) Agent works with already logged-in session
TAB_ID=$(curl -s -X POST http://localhost:9867/instances/<instance-id>/tabs/open \
  -H "Content-Type: application/json" \
  -d '{"url":"https://web.telegram.org"}' | jq -r '.tabId')

curl "http://localhost:9867/tabs/${TAB_ID}/snapshot?format=compact&filter=interactive"
```

Helper client (`scripts/pinchtab-client.sh`):

- `scripts/pinchtab-client.sh start user-123 headed`
- `scripts/pinchtab-client.sh novnc-url <host>`
- `scripts/pinchtab-client.sh switch-mode user-123 headless`
- `scripts/pinchtab-client.sh navigate @user-123 https://web.telegram.org`
- `scripts/pinchtab-client.sh snapshot @user-123`

Note:
- If `PINCHTAB_NOVNC_PUBLIC_PATH` is set (defaulted to `/novnc` when noVNC is enabled), entrypoint starts `caddy`:
  - `/<novnc-path>/*` -> noVNC (`PINCHTAB_NOVNC_PORT`)
  - all other paths -> nullclaw gateway (`PORT`)

### Playwright MCP (Legacy / Optional)

Playwright MCP env keys remain supported in config generation, but this image now targets PinchTab-first browser operations.

### Shell access / autonomy

- `NULLCLAW_AUTONOMY_LEVEL=supervised|full|...`
- `NULLCLAW_ALLOWED_COMMANDS=*` (CSV; set `*` for wildcard)
- `NULLCLAW_ALLOWED_PATHS=*` (CSV; set `*` for wildcard)
- `NULLCLAW_WORKSPACE_ONLY=true|false`
- `NULLCLAW_REQUIRE_APPROVAL_FOR_MEDIUM_RISK=true|false`
- `NULLCLAW_BLOCK_HIGH_RISK_COMMANDS=true|false`
- Optional tool limits:
  - `NULLCLAW_SHELL_TIMEOUT_SECS`
  - `NULLCLAW_SHELL_MAX_OUTPUT_BYTES`
  - `NULLCLAW_MAX_FILE_SIZE_BYTES`
  - `NULLCLAW_WEB_FETCH_MAX_CHARS`

### Provider reliability / fallback

- `NULLCLAW_RELIABILITY_PROVIDER_RETRIES=2`
- `NULLCLAW_RELIABILITY_PROVIDER_BACKOFF_MS=500`
- `NULLCLAW_RELIABILITY_FALLBACK_PROVIDERS=openrouter,groq` (CSV provider names configured in `models.providers`)
- `NULLCLAW_RELIABILITY_API_KEYS=...` (optional CSV key rotation for primary provider)
- `NULLCLAW_RELIABILITY_MODEL_FALLBACK_SOURCE=claude-sonnet-4-6`
- `NULLCLAW_RELIABILITY_MODEL_FALLBACKS=groq/llama-3.3-70b-versatile` (CSV)

Use this when Anthropic/OpenAI temporarily rate-limit requests.

### Web relay / browser channel

- `NULLCLAW_WEB_ENABLED=true`
- `NULLCLAW_WEB_TRANSPORT=local|relay`
- `NULLCLAW_WEB_LISTEN=127.0.0.1`
- `NULLCLAW_WEB_PORT=32123`
- `NULLCLAW_WEB_PATH=/ws`
- `NULLCLAW_WEB_MESSAGE_AUTH_MODE=pairing|token`
- `NULLCLAW_WEB_AUTH_TOKEN=...` (optional; also supports `NULLCLAW_WEB_TOKEN` / `NULLCLAW_GATEWAY_TOKEN`)
- `NULLCLAW_WEB_ALLOWED_ORIGINS=http://localhost:5173,chrome-extension://...`

Relay mode:

- `NULLCLAW_WEB_RELAY_URL=wss://...`
- `NULLCLAW_WEB_RELAY_AGENT_ID=default`
- `NULLCLAW_WEB_RELAY_TOKEN=...`
- `NULLCLAW_WEB_RELAY_TOKEN_TTL_SECS=2592000`
- `NULLCLAW_WEB_RELAY_PAIRING_CODE_TTL_SECS=300`
- `NULLCLAW_WEB_RELAY_UI_TOKEN_TTL_SECS=86400`
- `NULLCLAW_WEB_RELAY_E2E_REQUIRED=true|false`

If relay URL/token are left as placeholders, this entrypoint auto-disables the web relay channel to avoid restart loops.

## Verify deploy

- `GET /health` should return `{"status":"ok"}`
- Logs should include `nullclaw gateway runtime started`

## Notes

- Config is generated on first boot. Set `NULLCLAW_REWRITE_CONFIG=true` for one deploy when changing env-driven config structure.
- Runtime image includes `curl`, `git`, `bash`, `ripgrep`, `jq`, `pinchtab`, `chromium`, `Xvfb`, `x11vnc`, and `noVNC` for shared human+agent browser sessions.
