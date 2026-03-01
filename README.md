# nullclaw-railway

Railway-ready repository for running [nullclaw](https://github.com/nullclaw/nullclaw) as a long-lived gateway service.

This repo builds `nullclaw` from source in Docker, bootstraps a valid `~/.nullclaw/config.json` from environment variables, and starts:

```bash
nullclaw gateway --host 0.0.0.0 --port $PORT
```

## What this deploys

- Upstream source: `https://github.com/nullclaw/nullclaw`
- Default pinned ref: `v2026.2.26` (change via Docker build arg `NULLCLAW_REF`)
- Applies local patch: `patches/0001-subagent-wakeup.patch` (subagent completion wakes main session and routes reply back to originating chat)
- HTTP health endpoint: `/health`

## 1) Push this repo to GitHub

```bash
git init
git add .
git commit -m "Railway deployment for nullclaw"
git branch -M main
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
```

## 2) Deploy on Railway

1. In Railway, click **New Project** -> **Deploy from GitHub repo**.
2. Select this repository.
3. Railway will build from `Dockerfile` automatically.
4. Add environment variables (minimum: one API key variable).

### Required environment variable

Use one of:

- `NULLCLAW_API_KEY` (works for any selected provider), or
- provider-specific key var matching `NULLCLAW_PROVIDER`:
  - `OPENROUTER_API_KEY`
  - `OPENAI_API_KEY`
  - `ANTHROPIC_OAUTH_TOKEN` (Claude subscription/setup token)
  - `ANTHROPIC_API_KEY`

### Optional environment variables

- `NULLCLAW_PROVIDER` (default: `openrouter`)
- `NULLCLAW_MODEL` (optional; defaults are provider-specific)
- `NULLCLAW_GATEWAY_HOST` (default: `0.0.0.0`)
- `NULLCLAW_ALLOW_PUBLIC_BIND` (default: `true`)
- `NULLCLAW_REQUIRE_PAIRING` (default: `false`)
- `NULLCLAW_REWRITE_CONFIG` (default: `false`)

### Claude Subscription (Anthropic OAuth token)

For Claude Code subscription/setup tokens (`sk-ant-oat01-...`):

- `NULLCLAW_PROVIDER=anthropic`
- `ANTHROPIC_OAUTH_TOKEN=sk-ant-oat01-...`
- Optional model: `NULLCLAW_MODEL=claude-sonnet-4-6`

The image supports this directly.

### OpenAI Subscription (openai-codex OAuth)

For ChatGPT Plus/Pro subscription via `openai-codex`:

- `NULLCLAW_PROVIDER=openai-codex`
- `OPENAI_CODEX_ACCESS_TOKEN=...`
- `OPENAI_CODEX_REFRESH_TOKEN=...` (recommended)
- Optional: `OPENAI_CODEX_EXPIRES_AT=<unix_epoch_seconds>`
- Optional model: `NULLCLAW_MODEL=gpt-5.3-codex`

This writes `/data/.nullclaw/auth.json` for `openai-codex`.

### Telegram (optional)

Set these env vars to auto-configure Telegram channel on startup:

- `TELEGRAM_BOT_TOKEN` (required for Telegram)
- `TELEGRAM_ALLOW_FROM` (default: `*`; comma-separated usernames or user IDs)
- `TELEGRAM_ACCOUNT_ID` (default: `main`)
- `TELEGRAM_GROUP_ALLOW_FROM` (optional, comma-separated)
- `TELEGRAM_GROUP_POLICY` (default: `allowlist`; allowed: `allowlist`, `open`, `disabled`)

### Telegram Audio Messages (voice notes)

Telegram voice/audio messages are transcribed through `tools.media.audio`.
Set transcription env vars:

- `NULLCLAW_AUDIO_ENABLED=true` (default: true)
- `NULLCLAW_AUDIO_PROVIDER=groq` (recommended) or `openai`
- `NULLCLAW_AUDIO_API_KEY=...` (or provider env key like `GROQ_API_KEY` / `OPENAI_API_KEY`)
- Optional: `NULLCLAW_AUDIO_MODEL`, `NULLCLAW_AUDIO_LANGUAGE`, `NULLCLAW_AUDIO_BASE_URL`

If audio key is missing, text chat still works but voice notes are not transcribed.

## 3) (Recommended) add persistent volume

If you want config/workspace to persist across deploys:

1. Add a Railway volume.
2. Mount it at `/data`.

`nullclaw` config and workspace are stored under `/data/.nullclaw`.

## 4) Verify deploy

- Open service URL and check: `GET /health`
- Check Railway logs for: `nullclaw gateway runtime started`

## Notes

- This entrypoint only creates config on first boot (or when `NULLCLAW_REWRITE_CONFIG=true`).
- If you switch providers, set `NULLCLAW_PROVIDER`, corresponding API key variable, and optionally adjust `NULLCLAW_MODEL`.
- If you add Telegram vars after first deploy, set `NULLCLAW_REWRITE_CONFIG=true` for one deploy so config is regenerated, then set it back to `false`.
