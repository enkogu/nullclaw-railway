# nullclaw-railway

Railway-ready repository for running [nullclaw](https://github.com/nullclaw/nullclaw) as a long-lived gateway service.

This repo builds `nullclaw` from source in Docker, bootstraps a valid `~/.nullclaw/config.json` from environment variables, and starts:

```bash
nullclaw gateway --host 0.0.0.0 --port $PORT
```

## What this deploys

- Upstream source: `https://github.com/nullclaw/nullclaw`
- Default pinned ref: `v2026.2.26` (change via Docker build arg `NULLCLAW_REF`)
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
  - `ANTHROPIC_API_KEY`

### Optional environment variables

- `NULLCLAW_PROVIDER` (default: `openrouter`)
- `NULLCLAW_MODEL` (optional; defaults are provider-specific)
- `NULLCLAW_GATEWAY_HOST` (default: `0.0.0.0`)
- `NULLCLAW_ALLOW_PUBLIC_BIND` (default: `true`)
- `NULLCLAW_REQUIRE_PAIRING` (default: `false`)
- `NULLCLAW_REWRITE_CONFIG` (default: `false`)

### Telegram (optional)

Set these env vars to auto-configure Telegram channel on startup:

- `TELEGRAM_BOT_TOKEN` (required for Telegram)
- `TELEGRAM_ALLOW_FROM` (default: `*`; comma-separated usernames or user IDs)
- `TELEGRAM_ACCOUNT_ID` (default: `main`)
- `TELEGRAM_GROUP_ALLOW_FROM` (optional, comma-separated)
- `TELEGRAM_GROUP_POLICY` (default: `allowlist`; allowed: `allowlist`, `open`, `disabled`)

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
