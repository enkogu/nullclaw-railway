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

to_uint_or_default() {
  val="$1"
  def="$2"
  case "$val" in
    ''|*[!0-9]*) printf '%s' "$def" ;;
    *) printf '%s' "$val" ;;
  esac
}

json_string_or_null() {
  val="$1"
  if [ -n "$val" ]; then
    printf '"%s"' "$(json_escape "$val")"
  else
    printf 'null'
  fi
}

provider_key_for_name() {
  provider_name_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$provider_name_lc" in
    openai) printf '%s' "${OPENAI_API_KEY:-}" ;;
    anthropic) printf '%s' "${ANTHROPIC_OAUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}" ;;
    openrouter) printf '%s' "${OPENROUTER_API_KEY:-}" ;;
    openai-codex) printf '' ;;
    gemini) printf '%s' "${GEMINI_API_KEY:-}" ;;
    groq) printf '%s' "${GROQ_API_KEY:-}" ;;
    xai|grok) printf '%s' "${XAI_API_KEY:-}" ;;
    deepseek) printf '%s' "${DEEPSEEK_API_KEY:-}" ;;
    cohere) printf '%s' "${COHERE_API_KEY:-}" ;;
    mistral) printf '%s' "${MISTRAL_API_KEY:-}" ;;
    perplexity) printf '%s' "${PERPLEXITY_API_KEY:-}" ;;
    together-ai|together) printf '%s' "${TOGETHER_API_KEY:-}" ;;
    brave) printf '%s' "${BRAVE_API_KEY:-}" ;;
    firecrawl) printf '%s' "${FIRECRAWL_API_KEY:-}" ;;
    tavily) printf '%s' "${TAVILY_API_KEY:-}" ;;
    exa) printf '%s' "${EXA_API_KEY:-}" ;;
    jina) printf '%s' "${JINA_API_KEY:-}" ;;
    *) printf '' ;;
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

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ACCOUNT_ID="${TELEGRAM_ACCOUNT_ID:-main}"
TELEGRAM_ALLOW_FROM_CSV="${TELEGRAM_ALLOW_FROM:-*}"
TELEGRAM_GROUP_ALLOW_FROM_CSV="${TELEGRAM_GROUP_ALLOW_FROM:-}"
TELEGRAM_GROUP_POLICY="${TELEGRAM_GROUP_POLICY:-allowlist}"

OPENAI_CODEX_ACCESS_TOKEN="${OPENAI_CODEX_ACCESS_TOKEN:-}"
OPENAI_CODEX_REFRESH_TOKEN="${OPENAI_CODEX_REFRESH_TOKEN:-}"
OPENAI_CODEX_EXPIRES_AT="${OPENAI_CODEX_EXPIRES_AT:-0}"
OPENAI_CODEX_TOKEN_TYPE="${OPENAI_CODEX_TOKEN_TYPE:-Bearer}"

NULLCLAW_AUDIO_ENABLED_JSON="$(to_json_bool "${NULLCLAW_AUDIO_ENABLED:-true}")"
NULLCLAW_AUDIO_PROVIDER="${NULLCLAW_AUDIO_PROVIDER:-groq}"
NULLCLAW_AUDIO_MODEL="${NULLCLAW_AUDIO_MODEL:-whisper-large-v3}"
NULLCLAW_AUDIO_LANGUAGE="${NULLCLAW_AUDIO_LANGUAGE:-}"
NULLCLAW_AUDIO_BASE_URL="${NULLCLAW_AUDIO_BASE_URL:-}"
NULLCLAW_AUDIO_API_KEY="${NULLCLAW_AUDIO_API_KEY:-}"

NULLCLAW_MEMORY_BACKEND="${NULLCLAW_MEMORY_BACKEND:-sqlite}"
NULLCLAW_MEMORY_PROFILE="${NULLCLAW_MEMORY_PROFILE:-}"
NULLCLAW_MEMORY_CITATIONS="${NULLCLAW_MEMORY_CITATIONS:-auto}"
NULLCLAW_MEMORY_AUTO_SAVE_JSON="$(to_json_bool "${NULLCLAW_MEMORY_AUTO_SAVE:-true}")"
NULLCLAW_MEMORY_SEARCH_ENABLED_JSON="$(to_json_bool "${NULLCLAW_MEMORY_SEARCH_ENABLED:-true}")"
NULLCLAW_MEMORY_SEARCH_PROVIDER="${NULLCLAW_MEMORY_SEARCH_PROVIDER:-none}"
NULLCLAW_MEMORY_SEARCH_MODEL="${NULLCLAW_MEMORY_SEARCH_MODEL:-text-embedding-3-small}"
NULLCLAW_MEMORY_SEARCH_FALLBACK_PROVIDER="${NULLCLAW_MEMORY_SEARCH_FALLBACK_PROVIDER:-none}"
NULLCLAW_MEMORY_HYBRID_ENABLED_JSON="$(to_json_bool "${NULLCLAW_MEMORY_HYBRID_ENABLED:-false}")"
NULLCLAW_MEMORY_API_KEY="${NULLCLAW_MEMORY_API_KEY:-}"
NULLCLAW_MEMORY_BASE_URL="${NULLCLAW_MEMORY_BASE_URL:-}"

NULLCLAW_HTTP_ENABLED_JSON="$(to_json_bool "${NULLCLAW_HTTP_ENABLED:-true}")"
NULLCLAW_HTTP_MAX_RESPONSE_SIZE="$(to_uint_or_default "${NULLCLAW_HTTP_MAX_RESPONSE_SIZE:-1000000}" "1000000")"
NULLCLAW_HTTP_TIMEOUT_SECS="$(to_uint_or_default "${NULLCLAW_HTTP_TIMEOUT_SECS:-30}" "30")"
NULLCLAW_HTTP_ALLOWED_DOMAINS_CSV="${NULLCLAW_HTTP_ALLOWED_DOMAINS:-}"
NULLCLAW_WEB_SEARCH_BASE_URL="${NULLCLAW_WEB_SEARCH_BASE_URL:-}"
NULLCLAW_WEB_SEARCH_PROVIDER="${NULLCLAW_WEB_SEARCH_PROVIDER:-auto}"
NULLCLAW_WEB_SEARCH_FALLBACK_CSV="${NULLCLAW_WEB_SEARCH_FALLBACK_PROVIDERS:-}"

NULLCLAW_BROWSER_ENABLED_JSON="$(to_json_bool "${NULLCLAW_BROWSER_ENABLED:-false}")"
NULLCLAW_BROWSER_BACKEND="${NULLCLAW_BROWSER_BACKEND:-agent_browser}"
NULLCLAW_BROWSER_NATIVE_HEADLESS_JSON="$(to_json_bool "${NULLCLAW_BROWSER_NATIVE_HEADLESS:-true}")"
NULLCLAW_BROWSER_NATIVE_WEBDRIVER_URL="${NULLCLAW_BROWSER_NATIVE_WEBDRIVER_URL:-http://127.0.0.1:9515}"
NULLCLAW_BROWSER_NATIVE_CHROME_PATH="${NULLCLAW_BROWSER_NATIVE_CHROME_PATH:-}"
NULLCLAW_BROWSER_SESSION_NAME="${NULLCLAW_BROWSER_SESSION_NAME:-}"
NULLCLAW_BROWSER_ALLOWED_DOMAINS_CSV="${NULLCLAW_BROWSER_ALLOWED_DOMAINS:-}"

NULLCLAW_AUTONOMY_LEVEL="${NULLCLAW_AUTONOMY_LEVEL:-supervised}"
NULLCLAW_WORKSPACE_ONLY_JSON="$(to_json_bool "${NULLCLAW_WORKSPACE_ONLY:-true}")"
NULLCLAW_MAX_ACTIONS_PER_HOUR="$(to_uint_or_default "${NULLCLAW_MAX_ACTIONS_PER_HOUR:-20}" "20")"
NULLCLAW_REQUIRE_APPROVAL_MEDIUM_JSON="$(to_json_bool "${NULLCLAW_REQUIRE_APPROVAL_FOR_MEDIUM_RISK:-true}")"
NULLCLAW_BLOCK_HIGH_RISK_JSON="$(to_json_bool "${NULLCLAW_BLOCK_HIGH_RISK_COMMANDS:-true}")"
NULLCLAW_ALLOWED_COMMANDS_CSV="${NULLCLAW_ALLOWED_COMMANDS:-}"
NULLCLAW_ALLOWED_PATHS_CSV="${NULLCLAW_ALLOWED_PATHS:-}"

NULLCLAW_SHELL_TIMEOUT_SECS="$(to_uint_or_default "${NULLCLAW_SHELL_TIMEOUT_SECS:-60}" "60")"
NULLCLAW_SHELL_MAX_OUTPUT_BYTES="$(to_uint_or_default "${NULLCLAW_SHELL_MAX_OUTPUT_BYTES:-1048576}" "1048576")"
NULLCLAW_MAX_FILE_SIZE_BYTES="$(to_uint_or_default "${NULLCLAW_MAX_FILE_SIZE_BYTES:-10485760}" "10485760")"
NULLCLAW_WEB_FETCH_MAX_CHARS="$(to_uint_or_default "${NULLCLAW_WEB_FETCH_MAX_CHARS:-100000}" "100000")"

NULLCLAW_WEB_ENABLED_JSON="$(to_json_bool "${NULLCLAW_WEB_ENABLED:-false}")"
NULLCLAW_WEB_ACCOUNT_ID="${NULLCLAW_WEB_ACCOUNT_ID:-main}"
NULLCLAW_WEB_TRANSPORT="${NULLCLAW_WEB_TRANSPORT:-local}"
NULLCLAW_WEB_LISTEN="${NULLCLAW_WEB_LISTEN:-127.0.0.1}"
NULLCLAW_WEB_PORT="$(to_uint_or_default "${NULLCLAW_WEB_PORT:-32123}" "32123")"
NULLCLAW_WEB_PATH="${NULLCLAW_WEB_PATH:-/ws}"
NULLCLAW_WEB_MAX_CONNECTIONS="$(to_uint_or_default "${NULLCLAW_WEB_MAX_CONNECTIONS:-10}" "10")"
NULLCLAW_WEB_AUTH_TOKEN="${NULLCLAW_WEB_AUTH_TOKEN:-${NULLCLAW_WEB_TOKEN:-${NULLCLAW_GATEWAY_TOKEN:-${OPENCLAW_GATEWAY_TOKEN:-}}}}"
NULLCLAW_WEB_MESSAGE_AUTH_MODE="${NULLCLAW_WEB_MESSAGE_AUTH_MODE:-pairing}"
NULLCLAW_WEB_ALLOWED_ORIGINS_CSV="${NULLCLAW_WEB_ALLOWED_ORIGINS:-}"
NULLCLAW_WEB_RELAY_URL="${NULLCLAW_WEB_RELAY_URL:-}"
NULLCLAW_WEB_RELAY_AGENT_ID="${NULLCLAW_WEB_RELAY_AGENT_ID:-default}"
NULLCLAW_WEB_RELAY_TOKEN="${NULLCLAW_WEB_RELAY_TOKEN:-${NULLCLAW_RELAY_TOKEN:-}}"
NULLCLAW_WEB_RELAY_TOKEN_TTL_SECS="$(to_uint_or_default "${NULLCLAW_WEB_RELAY_TOKEN_TTL_SECS:-2592000}" "2592000")"
NULLCLAW_WEB_RELAY_PAIRING_CODE_TTL_SECS="$(to_uint_or_default "${NULLCLAW_WEB_RELAY_PAIRING_CODE_TTL_SECS:-300}" "300")"
NULLCLAW_WEB_RELAY_UI_TOKEN_TTL_SECS="$(to_uint_or_default "${NULLCLAW_WEB_RELAY_UI_TOKEN_TTL_SECS:-86400}" "86400")"
NULLCLAW_WEB_RELAY_E2E_REQUIRED_JSON="$(to_json_bool "${NULLCLAW_WEB_RELAY_E2E_REQUIRED:-false}")"

provider_lc="$(printf '%s' "$PROVIDER" | tr '[:upper:]' '[:lower:]')"
provider_key="$(provider_key_for_name "$PROVIDER")"

# Preferred: NULLCLAW_API_KEY. Fallback: provider-specific key env var.
# Final fallback checks common vars in case provider/env names are mismatched.
API_KEY="${NULLCLAW_API_KEY:-${provider_key:-${OPENROUTER_API_KEY:-${OPENAI_API_KEY:-${ANTHROPIC_OAUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}}}}}"

AUDIO_PROVIDER_LC="$(printf '%s' "$NULLCLAW_AUDIO_PROVIDER" | tr '[:upper:]' '[:lower:]')"
AUDIO_PROVIDER_KEY="$(provider_key_for_name "$NULLCLAW_AUDIO_PROVIDER")"
AUDIO_API_KEY="${NULLCLAW_AUDIO_API_KEY:-$AUDIO_PROVIDER_KEY}"

MEMORY_SEARCH_PROVIDER_LC="$(printf '%s' "$NULLCLAW_MEMORY_SEARCH_PROVIDER" | tr '[:upper:]' '[:lower:]')"
MEMORY_API_KEY="$NULLCLAW_MEMORY_API_KEY"
if [ -z "$MEMORY_API_KEY" ] && [ "$MEMORY_SEARCH_PROVIDER_LC" != "none" ]; then
  MEMORY_API_KEY="$(provider_key_for_name "$NULLCLAW_MEMORY_SEARCH_PROVIDER")"
fi

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

  ADDED_PROVIDERS="|"
  PROVIDER_CONFIG_ENTRIES=""

  add_provider_entry() {
    provider_name="$1"
    provider_api_key="$2"
    provider_base_url="$3"

    case "$ADDED_PROVIDERS" in
      *"|$provider_name|"*) return ;;
    esac

    provider_name_esc="$(json_escape "$provider_name")"
    if [ -n "$provider_api_key" ]; then
      provider_api_key_esc="$(json_escape "$provider_api_key")"
      entry="\"$provider_name_esc\": { \"api_key\": \"$provider_api_key_esc\""
    else
      entry="\"$provider_name_esc\": {"
    fi

    if [ -n "$provider_base_url" ]; then
      provider_base_url_esc="$(json_escape "$provider_base_url")"
      if [ -n "$provider_api_key" ]; then
        entry="$entry, \"base_url\": \"$provider_base_url_esc\""
      else
        entry="$entry \"base_url\": \"$provider_base_url_esc\""
      fi
    fi

    entry="$entry }"

    if [ -n "$PROVIDER_CONFIG_ENTRIES" ]; then
      PROVIDER_CONFIG_ENTRIES="${PROVIDER_CONFIG_ENTRIES},
      $entry"
    else
      PROVIDER_CONFIG_ENTRIES="      $entry"
    fi

    ADDED_PROVIDERS="${ADDED_PROVIDERS}${provider_name}|"
  }

  if [ "$IS_OAUTH_PROVIDER" = "true" ]; then
    add_provider_entry "$provider_lc" "" "${NULLCLAW_PROVIDER_BASE_URL:-}"
  else
    add_provider_entry "$provider_lc" "$API_KEY" "${NULLCLAW_PROVIDER_BASE_URL:-}"
  fi

  if [ "$NULLCLAW_AUDIO_ENABLED_JSON" = "true" ]; then
    if [ -n "$AUDIO_API_KEY" ]; then
      add_provider_entry "$AUDIO_PROVIDER_LC" "$AUDIO_API_KEY" "$NULLCLAW_AUDIO_BASE_URL"
    else
      echo "WARN: NULLCLAW_AUDIO_ENABLED=true but no key found for audio provider '$NULLCLAW_AUDIO_PROVIDER'; voice messages will not be transcribed." >&2
    fi
  fi

  if [ "$NULLCLAW_MEMORY_SEARCH_ENABLED_JSON" = "true" ] && [ "$MEMORY_SEARCH_PROVIDER_LC" != "none" ]; then
    if [ -n "$MEMORY_API_KEY" ]; then
      add_provider_entry "$MEMORY_SEARCH_PROVIDER_LC" "$MEMORY_API_KEY" "$NULLCLAW_MEMORY_BASE_URL"
    else
      echo "WARN: memory.search.provider='$NULLCLAW_MEMORY_SEARCH_PROVIDER' but no API key found; embedding search may fail." >&2
    fi
  fi

  AUDIO_MEDIA_FIELD=""
  if [ "$NULLCLAW_AUDIO_ENABLED_JSON" = "true" ]; then
    AUDIO_PROVIDER_ESC="$(json_escape "$AUDIO_PROVIDER_LC")"
    AUDIO_MODEL_ESC="$(json_escape "$NULLCLAW_AUDIO_MODEL")"

    AUDIO_MODEL_FIELDS="\"provider\": \"$AUDIO_PROVIDER_ESC\", \"model\": \"$AUDIO_MODEL_ESC\""
    if [ -n "$NULLCLAW_AUDIO_BASE_URL" ]; then
      AUDIO_BASE_URL_ESC="$(json_escape "$NULLCLAW_AUDIO_BASE_URL")"
      AUDIO_MODEL_FIELDS="$AUDIO_MODEL_FIELDS, \"base_url\": \"$AUDIO_BASE_URL_ESC\""
    fi
    if [ -n "$NULLCLAW_AUDIO_LANGUAGE" ]; then
      AUDIO_LANGUAGE_ESC="$(json_escape "$NULLCLAW_AUDIO_LANGUAGE")"
      AUDIO_LANGUAGE_FIELD=", \"language\": \"$AUDIO_LANGUAGE_ESC\""
    else
      AUDIO_LANGUAGE_FIELD=""
    fi

    AUDIO_MEDIA_FIELD=$(cat <<EOF_MEDIA
,
    "media": {
      "audio": {
        "enabled": true$AUDIO_LANGUAGE_FIELD,
        "models": [{$AUDIO_MODEL_FIELDS}]
      }
    }
EOF_MEDIA
)
  else
    AUDIO_MEDIA_FIELD=$(cat <<'EOF_MEDIA'
,
    "media": {
      "audio": {
        "enabled": false
      }
    }
EOF_MEDIA
)
  fi

  TOOLS_BLOCK=$(cat <<EOF_TOOLS
,
  "tools": {
    "shell_timeout_secs": $NULLCLAW_SHELL_TIMEOUT_SECS,
    "shell_max_output_bytes": $NULLCLAW_SHELL_MAX_OUTPUT_BYTES,
    "max_file_size_bytes": $NULLCLAW_MAX_FILE_SIZE_BYTES,
    "web_fetch_max_chars": $NULLCLAW_WEB_FETCH_MAX_CHARS$AUDIO_MEDIA_FIELD
  }
EOF_TOOLS
)

  MEMORY_BACKEND_ESC="$(json_escape "$NULLCLAW_MEMORY_BACKEND")"
  MEMORY_CITATIONS_ESC="$(json_escape "$NULLCLAW_MEMORY_CITATIONS")"
  MEMORY_SEARCH_PROVIDER_ESC="$(json_escape "$MEMORY_SEARCH_PROVIDER_LC")"
  MEMORY_SEARCH_MODEL_ESC="$(json_escape "$NULLCLAW_MEMORY_SEARCH_MODEL")"
  MEMORY_SEARCH_FALLBACK_ESC="$(json_escape "$NULLCLAW_MEMORY_SEARCH_FALLBACK_PROVIDER")"
  MEMORY_PROFILE_FIELD=""
  if [ -n "$NULLCLAW_MEMORY_PROFILE" ]; then
    MEMORY_PROFILE_ESC="$(json_escape "$NULLCLAW_MEMORY_PROFILE")"
    MEMORY_PROFILE_FIELD="\"profile\": \"$MEMORY_PROFILE_ESC\", "
  fi

  MEMORY_BLOCK=$(cat <<EOF_MEMORY
,
  "memory": {
    $MEMORY_PROFILE_FIELD"backend": "$MEMORY_BACKEND_ESC",
    "auto_save": $NULLCLAW_MEMORY_AUTO_SAVE_JSON,
    "citations": "$MEMORY_CITATIONS_ESC",
    "search": {
      "enabled": $NULLCLAW_MEMORY_SEARCH_ENABLED_JSON,
      "provider": "$MEMORY_SEARCH_PROVIDER_ESC",
      "model": "$MEMORY_SEARCH_MODEL_ESC",
      "fallback_provider": "$MEMORY_SEARCH_FALLBACK_ESC",
      "query": {
        "hybrid": {
          "enabled": $NULLCLAW_MEMORY_HYBRID_ENABLED_JSON
        }
      }
    }
  }
EOF_MEMORY
)

  HTTP_ALLOWED_DOMAINS_JSON="$(csv_to_json_array "$NULLCLAW_HTTP_ALLOWED_DOMAINS_CSV")"
  WEB_SEARCH_FALLBACK_JSON="$(csv_to_json_array "$NULLCLAW_WEB_SEARCH_FALLBACK_CSV")"
  WEB_SEARCH_PROVIDER_ESC="$(json_escape "$NULLCLAW_WEB_SEARCH_PROVIDER")"
  SEARCH_BASE_FIELD=""
  if [ -n "$NULLCLAW_WEB_SEARCH_BASE_URL" ]; then
    WEB_SEARCH_BASE_ESC="$(json_escape "$NULLCLAW_WEB_SEARCH_BASE_URL")"
    SEARCH_BASE_FIELD=$(cat <<EOF_SEARCH_BASE
,
    "search_base_url": "$WEB_SEARCH_BASE_ESC"
EOF_SEARCH_BASE
)
  fi

  HTTP_REQUEST_BLOCK=$(cat <<EOF_HTTP
,
  "http_request": {
    "enabled": $NULLCLAW_HTTP_ENABLED_JSON,
    "max_response_size": $NULLCLAW_HTTP_MAX_RESPONSE_SIZE,
    "timeout_secs": $NULLCLAW_HTTP_TIMEOUT_SECS,
    "allowed_domains": $HTTP_ALLOWED_DOMAINS_JSON,
    "search_provider": "$WEB_SEARCH_PROVIDER_ESC",
    "search_fallback_providers": $WEB_SEARCH_FALLBACK_JSON$SEARCH_BASE_FIELD
  }
EOF_HTTP
)

  ALLOWED_COMMANDS_JSON="$(csv_to_json_array "$NULLCLAW_ALLOWED_COMMANDS_CSV")"
  ALLOWED_PATHS_JSON="$(csv_to_json_array "$NULLCLAW_ALLOWED_PATHS_CSV")"
  AUTONOMY_LEVEL_ESC="$(json_escape "$NULLCLAW_AUTONOMY_LEVEL")"

  AUTONOMY_BLOCK=$(cat <<EOF_AUTONOMY
,
  "autonomy": {
    "level": "$AUTONOMY_LEVEL_ESC",
    "workspace_only": $NULLCLAW_WORKSPACE_ONLY_JSON,
    "max_actions_per_hour": $NULLCLAW_MAX_ACTIONS_PER_HOUR,
    "require_approval_for_medium_risk": $NULLCLAW_REQUIRE_APPROVAL_MEDIUM_JSON,
    "block_high_risk_commands": $NULLCLAW_BLOCK_HIGH_RISK_JSON,
    "allowed_commands": $ALLOWED_COMMANDS_JSON,
    "allowed_paths": $ALLOWED_PATHS_JSON
  }
EOF_AUTONOMY
)

  BROWSER_BACKEND_ESC="$(json_escape "$NULLCLAW_BROWSER_BACKEND")"
  BROWSER_NATIVE_WEBDRIVER_ESC="$(json_escape "$NULLCLAW_BROWSER_NATIVE_WEBDRIVER_URL")"
  BROWSER_ALLOWED_DOMAINS_JSON="$(csv_to_json_array "$NULLCLAW_BROWSER_ALLOWED_DOMAINS_CSV")"
  BROWSER_SESSION_FIELD=""
  if [ -n "$NULLCLAW_BROWSER_SESSION_NAME" ]; then
    BROWSER_SESSION_ESC="$(json_escape "$NULLCLAW_BROWSER_SESSION_NAME")"
    BROWSER_SESSION_FIELD=$(cat <<EOF_BROWSER_SESSION
,
    "session_name": "$BROWSER_SESSION_ESC"
EOF_BROWSER_SESSION
)
  fi
  BROWSER_CHROME_FIELD=""
  if [ -n "$NULLCLAW_BROWSER_NATIVE_CHROME_PATH" ]; then
    BROWSER_CHROME_ESC="$(json_escape "$NULLCLAW_BROWSER_NATIVE_CHROME_PATH")"
    BROWSER_CHROME_FIELD=$(cat <<EOF_BROWSER_CHROME
,
    "native_chrome_path": "$BROWSER_CHROME_ESC"
EOF_BROWSER_CHROME
)
  fi
  BROWSER_BLOCK=$(cat <<EOF_BROWSER
,
  "browser": {
    "enabled": $NULLCLAW_BROWSER_ENABLED_JSON,
    "backend": "$BROWSER_BACKEND_ESC",
    "native_headless": $NULLCLAW_BROWSER_NATIVE_HEADLESS_JSON,
    "native_webdriver_url": "$BROWSER_NATIVE_WEBDRIVER_ESC",
    "allowed_domains": $BROWSER_ALLOWED_DOMAINS_JSON$BROWSER_SESSION_FIELD$BROWSER_CHROME_FIELD
  }
EOF_BROWSER
)

  CHANNEL_FIELDS=""
  append_channel_field() {
    field="$1"
    if [ -n "$CHANNEL_FIELDS" ]; then
      CHANNEL_FIELDS="${CHANNEL_FIELDS},
$field"
    else
      CHANNEL_FIELDS="$field"
    fi
  }

  if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    TELEGRAM_BOT_TOKEN_ESC="$(json_escape "$TELEGRAM_BOT_TOKEN")"
    TELEGRAM_ACCOUNT_ID_ESC="$(json_escape "$TELEGRAM_ACCOUNT_ID")"
    TELEGRAM_GROUP_POLICY_ESC="$(json_escape "$TELEGRAM_GROUP_POLICY")"
    TELEGRAM_ALLOW_FROM_JSON="$(csv_to_json_array "$TELEGRAM_ALLOW_FROM_CSV")"
    TELEGRAM_GROUP_ALLOW_FROM_JSON="$(csv_to_json_array "$TELEGRAM_GROUP_ALLOW_FROM_CSV")"

    TELEGRAM_CHANNEL_FIELD=$(cat <<EOF_TG
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
EOF_TG
)
    append_channel_field "$TELEGRAM_CHANNEL_FIELD"
  fi

  if [ "$NULLCLAW_WEB_ENABLED_JSON" = "true" ]; then
    WEB_ACCOUNT_ID_ESC="$(json_escape "$NULLCLAW_WEB_ACCOUNT_ID")"
    WEB_TRANSPORT_ESC="$(json_escape "$NULLCLAW_WEB_TRANSPORT")"
    WEB_LISTEN_ESC="$(json_escape "$NULLCLAW_WEB_LISTEN")"
    WEB_PATH_ESC="$(json_escape "$NULLCLAW_WEB_PATH")"
    WEB_MESSAGE_AUTH_MODE_ESC="$(json_escape "$NULLCLAW_WEB_MESSAGE_AUTH_MODE")"
    WEB_ALLOWED_ORIGINS_JSON="$(csv_to_json_array "$NULLCLAW_WEB_ALLOWED_ORIGINS_CSV")"
    WEB_AUTH_TOKEN_JSON="$(json_string_or_null "$NULLCLAW_WEB_AUTH_TOKEN")"
    WEB_RELAY_URL_JSON="$(json_string_or_null "$NULLCLAW_WEB_RELAY_URL")"
    WEB_RELAY_AGENT_ID_ESC="$(json_escape "$NULLCLAW_WEB_RELAY_AGENT_ID")"
    WEB_RELAY_TOKEN_JSON="$(json_string_or_null "$NULLCLAW_WEB_RELAY_TOKEN")"

    WEB_CHANNEL_FIELD=$(cat <<EOF_WEB
    "web": {
      "accounts": {
        "$WEB_ACCOUNT_ID_ESC": {
          "transport": "$WEB_TRANSPORT_ESC",
          "listen": "$WEB_LISTEN_ESC",
          "port": $NULLCLAW_WEB_PORT,
          "path": "$WEB_PATH_ESC",
          "max_connections": $NULLCLAW_WEB_MAX_CONNECTIONS,
          "auth_token": $WEB_AUTH_TOKEN_JSON,
          "message_auth_mode": "$WEB_MESSAGE_AUTH_MODE_ESC",
          "allowed_origins": $WEB_ALLOWED_ORIGINS_JSON,
          "relay_url": $WEB_RELAY_URL_JSON,
          "relay_agent_id": "$WEB_RELAY_AGENT_ID_ESC",
          "relay_token": $WEB_RELAY_TOKEN_JSON,
          "relay_token_ttl_secs": $NULLCLAW_WEB_RELAY_TOKEN_TTL_SECS,
          "relay_pairing_code_ttl_secs": $NULLCLAW_WEB_RELAY_PAIRING_CODE_TTL_SECS,
          "relay_ui_token_ttl_secs": $NULLCLAW_WEB_RELAY_UI_TOKEN_TTL_SECS,
          "relay_e2e_required": $NULLCLAW_WEB_RELAY_E2E_REQUIRED_JSON
        }
      }
    }
EOF_WEB
)
    append_channel_field "$WEB_CHANNEL_FIELD"
  fi

  CHANNELS_BLOCK=""
  if [ -n "$CHANNEL_FIELDS" ]; then
    CHANNELS_BLOCK=$(cat <<EOF_CHANNELS
,
  "channels": {
$CHANNEL_FIELDS
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
$PROVIDER_CONFIG_ENTRIES
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "$PRIMARY_MODEL_ESC" }
    }
  }$TOOLS_BLOCK$MEMORY_BLOCK$HTTP_REQUEST_BLOCK$AUTONOMY_BLOCK$BROWSER_BLOCK,
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
