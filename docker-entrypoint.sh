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
MODEL="${NULLCLAW_MODEL:-anthropic/claude-sonnet-4.6}"
HOST="${NULLCLAW_GATEWAY_HOST:-0.0.0.0}"
PORT="${PORT:-3000}"

ALLOW_PUBLIC_BIND_JSON="$(to_json_bool "${NULLCLAW_ALLOW_PUBLIC_BIND:-true}")"
REQUIRE_PAIRING_JSON="$(to_json_bool "${NULLCLAW_REQUIRE_PAIRING:-false}")"
REWRITE_CONFIG="$(to_json_bool "${NULLCLAW_REWRITE_CONFIG:-false}")"

# Use generic key first, then default OpenRouter variable as fallback.
API_KEY="${NULLCLAW_API_KEY:-${OPENROUTER_API_KEY:-}}"

if [ "${MODEL#${PROVIDER}/}" != "$MODEL" ]; then
  PRIMARY_MODEL="$MODEL"
else
  PRIMARY_MODEL="${PROVIDER}/${MODEL}"
fi

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

if [ ! -f "$CONFIG_PATH" ] || [ "$REWRITE_CONFIG" = "true" ]; then
  if [ -z "$API_KEY" ]; then
    echo "ERROR: Missing API key. Set NULLCLAW_API_KEY (or OPENROUTER_API_KEY)." >&2
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

exec nullclaw gateway --host "$HOST" --port "$PORT"
