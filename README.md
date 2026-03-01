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
- Health endpoint: `/health`

## Deploy on Railway

1. Create a new Railway project from this GitHub repository.
2. Add environment variables (see below).
3. Deploy.
4. Optional but recommended: mount a volume at `/data`.

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

## Verify deploy

- `GET /health` should return `{"status":"ok"}`
- Logs should include `nullclaw gateway runtime started`

## Notes

- Config is generated on first boot. Set `NULLCLAW_REWRITE_CONFIG=true` for one deploy when changing env-driven config structure.
- Runtime image includes `curl`, `git`, `bash`, and `ripgrep` to improve shell/tool usability.
