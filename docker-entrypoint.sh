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

provider_key=""
provider_lc="$(printf '%s' "$PROVIDER" | tr '[:upper:]' '[:lower:]')"
case "$provider_lc" in
  openai) provider_key="${OPENAI_API_KEY:-}" ;;
  anthropic) provider_key="${ANTHROPIC_API_KEY:-}" ;;
  openrouter) provider_key="${OPENROUTER_API_KEY:-}" ;;
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
API_KEY="${NULLCLAW_API_KEY:-${provider_key:-${OPENROUTER_API_KEY:-${OPENAI_API_KEY:-${ANTHROPIC_API_KEY:-}}}}}"

MODEL="${NULLCLAW_MODEL:-}"
if [ -z "$MODEL" ]; then
  case "$provider_lc" in
    openai) MODEL="gpt-5.2" ;;
    anthropic) MODEL="claude-opus-4-6" ;;
    openrouter) MODEL="anthropic/claude-sonnet-4.6" ;;
    gemini) MODEL="gemini-2.5-pro" ;;
    *) MODEL="anthropic/claude-sonnet-4.6" ;;
  esac
fi

if [ "${MODEL#${PROVIDER}/}" != "$MODEL" ]; then
  PRIMARY_MODEL="$MODEL"
else
  PRIMARY_MODEL="${PROVIDER}/${MODEL}"
fi

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

if [ ! -f "$CONFIG_PATH" ] || [ "$REWRITE_CONFIG" = "true" ]; then
  if [ -z "$API_KEY" ]; then
    echo "ERROR: Missing API key. Set NULLCLAW_API_KEY or provider key env (e.g. OPENAI_API_KEY / ANTHROPIC_API_KEY / OPENROUTER_API_KEY)." >&2
    exit 1
  fi

  API_KEY_ESC="$(json_escape "$API_KEY")"
  PROVIDER_ESC="$(json_escape "$PROVIDER")"
  PRIMARY_MODEL_ESC="$(json_escape "$PRIMARY_MODEL")"
  WORKSPACE_ESC="$(json_escape "$WORKSPACE_DIR")"
  HOST_ESC="$(json_escape "$HOST")"

  cat > "$CONFIG_PATH" <<EOF_CONFIG
{
  "workspace": "$WORKSPACE_ESC",
  "default_temperature": 0.7,
  "models": {
    "providers": {
      "$PROVIDER_ESC": { "api_key": "$API_KEY_ESC" }
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
  }
}
EOF_CONFIG
fi

export HOME="$NULLCLAW_HOME"
export NULLCLAW_WORKSPACE="$WORKSPACE_DIR"

echo "Starting nullclaw gateway on ${HOST}:${PORT} with provider=${PROVIDER} model=${PRIMARY_MODEL}"
exec nullclaw gateway --host "$HOST" --port "$PORT"
