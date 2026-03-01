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
4. Add environment variables (minimum: `NULLCLAW_API_KEY`).

### Required environment variable

- `NULLCLAW_API_KEY`: your provider key (for default provider `openrouter`, OpenRouter key works)

### Optional environment variables

- `NULLCLAW_PROVIDER` (default: `openrouter`)
- `NULLCLAW_MODEL` (default: `anthropic/claude-sonnet-4.6`)
- `NULLCLAW_GATEWAY_HOST` (default: `0.0.0.0`)
- `NULLCLAW_ALLOW_PUBLIC_BIND` (default: `true`)
- `NULLCLAW_REQUIRE_PAIRING` (default: `false`)
- `NULLCLAW_REWRITE_CONFIG` (default: `false`)

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
- If you switch providers, set both `NULLCLAW_PROVIDER` and `NULLCLAW_API_KEY`, and optionally adjust `NULLCLAW_MODEL`.
