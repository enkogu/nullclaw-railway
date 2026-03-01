#!/bin/sh
set -eu

json_escape() {
  # Minimal JSON escaping for env-provided strings.
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

to_json_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

csv_to_json_array() {
  csv="$1"
  printf '%s' "$csv" | awk -F',' '
    BEGIN { printf "["; n = 0 }
    {
      for (i = 1; i <= NF; i++) {
        v = $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (v == "") continue
        gsub(/\\/, "\\\\", v)
        gsub(/"/, "\\\"", v)
        if (n > 0) printf ", "
        printf "\"%s\"", v
        n++
      }
    }
    END { printf "]" }
  '
}

NULLCLAW_HOME="${NULLCLAW_HOME:-/data}"
CONFIG_DIR="${NULLCLAW_HOME}/.nullclaw"
CONFIG_PATH="${CONFIG_DIR}/config.json"
WORKSPACE_DIR="${NULLCLAW_WORKSPACE:-${CONFIG_DIR}/workspace}"

PROVIDER="${NULLCLAW_PROVIDER:-openrouter}"
HOST="${NULLCLAW_GATEWAY_HOST:-0.0.0.0}"
PORT="${PORT:-3000}"

ALLOW_PUBLIC_BIND_JSON="$(to_json_bool "${NULLCLAW_ALLOW_PUBLIC_BIND:-true}")"
REQUIRE_PAIRING_JSON="$(to_json_bool "${NULLCLAW_REQUIRE_PAIRING:-false}")"
REWRITE_CONFIG="$(to_json_bool "${NULLCLAW_REWRITE_CONFIG:-false}")"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ACCOUNT_ID="${TELEGRAM_ACCOUNT_ID:-main}"
TELEGRAM_ALLOW_FROM_CSV="${TELEGRAM_ALLOW_FROM:-*}"
TELEGRAM_GROUP_ALLOW_FROM_CSV="${TELEGRAM_GROUP_ALLOW_FROM:-}"
TELEGRAM_GROUP_POLICY="${TELEGRAM_GROUP_POLICY:-allowlist}"
OPENAI_CODEX_ACCESS_TOKEN="${OPENAI_CODEX_ACCESS_TOKEN:-}"
OPENAI_CODEX_REFRESH_TOKEN="${OPENAI_CODEX_REFRESH_TOKEN:-}"
OPENAI_CODEX_EXPIRES_AT="${OPENAI_CODEX_EXPIRES_AT:-0}"
OPENAI_CODEX_TOKEN_TYPE="${OPENAI_CODEX_TOKEN_TYPE:-Bearer}"

provider_key=""
provider_lc="$(printf '%s' "$PROVIDER" | tr '[:upper:]' '[:lower:]')"
case "$provider_lc" in
  openai) provider_key="${OPENAI_API_KEY:-}" ;;
  anthropic) provider_key="${ANTHROPIC_OAUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}" ;;
  openrouter) provider_key="${OPENROUTER_API_KEY:-}" ;;
  openai-codex) provider_key="" ;;
  gemini) provider_key="${GEMINI_API_KEY:-}" ;;
  groq) provider_key="${GROQ_API_KEY:-}" ;;
  xai|grok) provider_key="${XAI_API_KEY:-}" ;;
  deepseek) provider_key="${DEEPSEEK_API_KEY:-}" ;;
  cohere) provider_key="${COHERE_API_KEY:-}" ;;
  mistral) provider_key="${MISTRAL_API_KEY:-}" ;;
  perplexity) provider_key="${PERPLEXITY_API_KEY:-}" ;;
  together-ai|together) provider_key="${TOGETHER_API_KEY:-}" ;;
esac

# Preferred: NULLCLAW_API_KEY. Fallback: provider-specific key env var.
# Final fallback checks common vars in case provider/env names are mismatched.
API_KEY="${NULLCLAW_API_KEY:-${provider_key:-${OPENROUTER_API_KEY:-${OPENAI_API_KEY:-${ANTHROPIC_OAUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}}}}}"

MODEL="${NULLCLAW_MODEL:-}"
if [ -z "$MODEL" ]; then
  case "$provider_lc" in
    openai) MODEL="gpt-5.2" ;;
    anthropic) MODEL="claude-opus-4-6" ;;
    openrouter) MODEL="anthropic/claude-sonnet-4.6" ;;
    openai-codex) MODEL="gpt-5.3-codex" ;;
    gemini) MODEL="gemini-2.5-pro" ;;
    *) MODEL="anthropic/claude-sonnet-4.6" ;;
  esac
fi

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

AUTH_PATH="${CONFIG_DIR}/auth.json"
IS_OAUTH_PROVIDER=false
if [ "$provider_lc" = "openai-codex" ]; then
  IS_OAUTH_PROVIDER=true
fi

if [ "$IS_OAUTH_PROVIDER" = "true" ]; then
  if [ -n "$OPENAI_CODEX_ACCESS_TOKEN" ]; then
    case "$OPENAI_CODEX_EXPIRES_AT" in
      ''|*[!0-9-]*) OPENAI_CODEX_EXPIRES_AT=0 ;;
    esac
    ACCESS_ESC="$(json_escape "$OPENAI_CODEX_ACCESS_TOKEN")"
    REFRESH_ESC="$(json_escape "$OPENAI_CODEX_REFRESH_TOKEN")"
    TOKEN_TYPE_ESC="$(json_escape "$OPENAI_CODEX_TOKEN_TYPE")"
    if [ -n "$OPENAI_CODEX_REFRESH_TOKEN" ]; then
      REFRESH_FIELD=", \"refresh_token\": \"$REFRESH_ESC\""
    else
      REFRESH_FIELD=""
    fi
    cat > "$AUTH_PATH" <<EOF_AUTH
{
  "openai-codex": {
    "access_token": "$ACCESS_ESC"$REFRESH_FIELD,
    "expires_at": $OPENAI_CODEX_EXPIRES_AT,
    "token_type": "$TOKEN_TYPE_ESC"
  }
}
EOF_AUTH
  elif [ ! -f "$AUTH_PATH" ]; then
    echo "ERROR: Missing OpenAI subscription credentials. Set OPENAI_CODEX_ACCESS_TOKEN (and OPENAI_CODEX_REFRESH_TOKEN) or provide /data/.nullclaw/auth.json." >&2
    exit 1
  fi
fi

if [ "${MODEL#${PROVIDER}/}" != "$MODEL" ]; then
  PRIMARY_MODEL="$MODEL"
else
  PRIMARY_MODEL="${PROVIDER}/${MODEL}"
fi

if [ ! -f "$CONFIG_PATH" ] || [ "$REWRITE_CONFIG" = "true" ]; then
  if [ "$IS_OAUTH_PROVIDER" != "true" ] && [ -z "$API_KEY" ]; then
    echo "ERROR: Missing API key/token. Set NULLCLAW_API_KEY or provider key env (e.g. OPENAI_API_KEY / ANTHROPIC_OAUTH_TOKEN / ANTHROPIC_API_KEY / OPENROUTER_API_KEY)." >&2
    exit 1
  fi

  PROVIDER_ESC="$(json_escape "$PROVIDER")"
  PRIMARY_MODEL_ESC="$(json_escape "$PRIMARY_MODEL")"
  WORKSPACE_ESC="$(json_escape "$WORKSPACE_DIR")"
  HOST_ESC="$(json_escape "$HOST")"
  if [ "$IS_OAUTH_PROVIDER" = "true" ]; then
    PROVIDER_CONFIG_BLOCK="\"$PROVIDER_ESC\": {}"
  else
    API_KEY_ESC="$(json_escape "$API_KEY")"
    PROVIDER_CONFIG_BLOCK="\"$PROVIDER_ESC\": { \"api_key\": \"$API_KEY_ESC\" }"
  fi

  CHANNELS_BLOCK=""
  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    TELEGRAM_BOT_TOKEN_ESC="$(json_escape "$TELEGRAM_BOT_TOKEN")"
    TELEGRAM_ACCOUNT_ID_ESC="$(json_escape "$TELEGRAM_ACCOUNT_ID")"
    TELEGRAM_GROUP_POLICY_ESC="$(json_escape "$TELEGRAM_GROUP_POLICY")"
    TELEGRAM_ALLOW_FROM_JSON="$(csv_to_json_array "$TELEGRAM_ALLOW_FROM_CSV")"
    TELEGRAM_GROUP_ALLOW_FROM_JSON="$(csv_to_json_array "$TELEGRAM_GROUP_ALLOW_FROM_CSV")"
    CHANNELS_BLOCK=$(cat <<EOF_CHANNELS
,
  "channels": {
    "telegram": {
      "accounts": {
        "$TELEGRAM_ACCOUNT_ID_ESC": {
          "bot_token": "$TELEGRAM_BOT_TOKEN_ESC",
          "allow_from": $TELEGRAM_ALLOW_FROM_JSON,
          "group_allow_from": $TELEGRAM_GROUP_ALLOW_FROM_JSON,
          "group_policy": "$TELEGRAM_GROUP_POLICY_ESC"
        }
      }
    }
  }
EOF_CHANNELS
)
  fi

  cat > "$CONFIG_PATH" <<EOF_CONFIG
{
  "workspace": "$WORKSPACE_ESC",
  "default_temperature": 0.7,
  "models": {
    "providers": {
      $PROVIDER_CONFIG_BLOCK
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "$PRIMARY_MODEL_ESC" }
    }
  },
  "gateway": {
    "port": $PORT,
    "host": "$HOST_ESC",
    "allow_public_bind": $ALLOW_PUBLIC_BIND_JSON,
    "require_pairing": $REQUIRE_PAIRING_JSON
  }$CHANNELS_BLOCK
}
EOF_CONFIG
fi

export HOME="$NULLCLAW_HOME"
export NULLCLAW_WORKSPACE="$WORKSPACE_DIR"

echo "Starting nullclaw gateway on ${HOST}:${PORT} with provider=${PROVIDER} model=${PRIMARY_MODEL}"
exec nullclaw gateway --host "$HOST" --port "$PORT"
