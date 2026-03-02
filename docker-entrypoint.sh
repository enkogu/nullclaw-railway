#!/bin/sh
set -eu

json_escape() {
  # Minimal JSON escaping for env-provided strings.
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

json_escape_multiline() {
  # JSON escaping with newline preservation for prompt blocks.
  printf '%s' "$1" | awk '
    BEGIN { first = 1 }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      if (!first) printf "\\n"
      printf "%s", $0
      first = 0
    }
  '
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

strip_wrapping_quotes() {
  val="$1"
  case "$val" in
    \"*\")
      val="${val#\"}"
      val="${val%\"}"
      ;;
    \'*\')
      val="${val#\'}"
      val="${val%\'}"
      ;;
  esac
  printf '%s' "$val"
}

is_placeholder_value() {
  val="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$val" in
    '' ) return 1 ;;
    *your-*|*replace-with*|*example.com*|*example.org*|*placeholder*|*\<*|*\>* ) return 0 ;;
    *://your-*|wss://relay.nullclaw.io/ws/agent ) return 0 ;;
    *) return 1 ;;
  esac
}

sanitize_env_var() {
  name="$1"
  eval "is_set=\${$name+x}"
  [ -n "${is_set:-}" ] || return 0
  eval "raw=\${$name}"
  cleaned="$(strip_wrapping_quotes "$raw")"
  eval "$name=\$cleaned"
  export "$name"
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

wait_for_http_health() {
  url="$1"
  timeout_secs="$2"
  service_name="$3"
  auth_token="${4:-}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout_secs" ]; do
    if [ -n "$auth_token" ]; then
      if curl -fsS -H "Authorization: Bearer ${auth_token}" "$url" >/dev/null 2>&1; then
        return 0
      fi
    elif curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    elapsed=$((elapsed + 1))
    sleep 1
  done
  echo "ERROR: ${service_name} failed health check at ${url} after ${timeout_secs}s." >&2
  return 1
}

cleanup_stale_chromium_locks() {
  profiles_dir="$1"

  [ -d "$profiles_dir" ] || return 0

  # Do not touch lock files while Chromium may still be alive.
  if ps aux | grep -E '[c]hrom(e|ium)' >/dev/null 2>&1; then
    echo "Skipping Chromium lock cleanup: active Chromium process detected."
    return 0
  fi

  find "$profiles_dir" -maxdepth 4 \
    \( -name 'SingletonLock' -o -name 'SingletonSocket' -o -name 'SingletonCookie' -o -name 'LOCK' -o -name 'DevToolsActivePort' \) \
    -print 2>/dev/null | while IFS= read -r lock_path; do
      [ -n "$lock_path" ] || continue
      rm -f "$lock_path" 2>/dev/null || true
  done
}

upsert_marked_block() {
  target_file="$1"
  marker_start="$2"
  marker_end="$3"
  block_content="$4"

  mkdir -p "$(dirname "$target_file")"
  [ -f "$target_file" ] || : > "$target_file"

  tmp_file="${target_file}.tmp.$$"
  awk -v start="$marker_start" -v end="$marker_end" '
    BEGIN { skipping = 0 }
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    skipping == 0 { print }
  ' "$target_file" > "$tmp_file"

  {
    cat "$tmp_file"
    printf '\n%s\n' "$marker_start"
    printf '%s\n' "$block_content"
    printf '%s\n' "$marker_end"
  } > "${tmp_file}.new"

  mv "${tmp_file}.new" "$target_file"
  rm -f "$tmp_file"
}

write_workspace_browser_docs() {
  workspace_root="$1"
  novnc_url="$2"
  novnc_password="$3"
  pinchtab_api="$4"
  pinchtab_api_public="$5"
  pinchtab_token="$6"
  novnc_port="$7"

  tools_file="${workspace_root}/TOOLS.md"
  agents_file="${workspace_root}/AGENTS.md"

  tools_block=$(cat <<EOF_TOOLS_BLOCK
## Railway Browser Session (PinchTab + noVNC)

- noVNC URL: ${novnc_url}
- noVNC password: ${novnc_password}
- noVNC port (internal): ${novnc_port}
- PinchTab API (internal): ${pinchtab_api}
- PinchTab API (public): ${pinchtab_api_public}
- PinchTab token (internal): ${pinchtab_token}

Execution rule for authenticated websites (Telegram/Instagram/etc):
1. Tell user to log in via noVNC first.
2. Wait for user message: "done".
3. Use PinchTab commands (same browser/profile as noVNC):
   - PINCHTAB_BASE_URL=${pinchtab_api} PINCHTAB_TOKEN=${pinchtab_token} pinchtab-client.sh list-instances
   - PINCHTAB_BASE_URL=${pinchtab_api} PINCHTAB_TOKEN=${pinchtab_token} pinchtab-client.sh navigate @default https://web.telegram.org
   - PINCHTAB_BASE_URL=${pinchtab_api} PINCHTAB_TOKEN=${pinchtab_token} pinchtab-client.sh snapshot @default
   - PINCHTAB_BASE_URL=${pinchtab_api} PINCHTAB_TOKEN=${pinchtab_token} pinchtab-client.sh text @default

Important:
- Do not ask user for noVNC port.
- Do not ask user to paste account password in chat.
- Do not ask user for PinchTab token; use the internal runtime token.
- Do not use separate built-in browser for authenticated sessions.
- If PinchTab API call returns unauthorized on one endpoint, retry once using the other endpoint (public <-> internal) with the same token.
EOF_TOOLS_BLOCK
)

  agents_block=$(cat <<EOF_AGENTS_BLOCK
## Browser Control Rule (Railway)

When user asks to read data from authenticated web apps:
- Always start with noVNC login handoff.
- After user confirms "done", operate only through PinchTab session commands from TOOLS.md.
- Never ask for noVNC port; it is fixed at ${novnc_port} (internal) and exposed via the noVNC URL in TOOLS.md.
EOF_AGENTS_BLOCK
)

  upsert_marked_block "$tools_file" "<!-- NULLCLAW_RAILWAY_BROWSER_START -->" "<!-- NULLCLAW_RAILWAY_BROWSER_END -->" "$tools_block"
  upsert_marked_block "$agents_file" "<!-- NULLCLAW_RAILWAY_BROWSER_START -->" "<!-- NULLCLAW_RAILWAY_BROWSER_END -->" "$agents_block"
}

# Railway users often paste quoted values (KEY="value"). Normalize selected envs
# so booleans/numbers/provider names and tokens are parsed correctly.
for _env_name in \
  NULLCLAW_PROVIDER NULLCLAW_MODEL NULLCLAW_API_KEY \
  NULLCLAW_GATEWAY_HOST NULLCLAW_ALLOW_PUBLIC_BIND NULLCLAW_REQUIRE_PAIRING NULLCLAW_REWRITE_CONFIG PORT \
  TELEGRAM_BOT_TOKEN TELEGRAM_ACCOUNT_ID TELEGRAM_ALLOW_FROM TELEGRAM_GROUP_ALLOW_FROM TELEGRAM_GROUP_POLICY \
  OPENAI_CODEX_ACCESS_TOKEN OPENAI_CODEX_REFRESH_TOKEN OPENAI_CODEX_EXPIRES_AT OPENAI_CODEX_TOKEN_TYPE \
  NULLCLAW_AUDIO_ENABLED NULLCLAW_AUDIO_PROVIDER NULLCLAW_AUDIO_MODEL NULLCLAW_AUDIO_LANGUAGE NULLCLAW_AUDIO_BASE_URL NULLCLAW_AUDIO_API_KEY \
  NULLCLAW_MEMORY_BACKEND NULLCLAW_MEMORY_PROFILE NULLCLAW_MEMORY_CITATIONS NULLCLAW_MEMORY_AUTO_SAVE NULLCLAW_MEMORY_SEARCH_ENABLED NULLCLAW_MEMORY_SEARCH_PROVIDER NULLCLAW_MEMORY_SEARCH_MODEL NULLCLAW_MEMORY_SEARCH_FALLBACK_PROVIDER NULLCLAW_MEMORY_HYBRID_ENABLED NULLCLAW_MEMORY_API_KEY NULLCLAW_MEMORY_BASE_URL \
  NULLCLAW_HTTP_ENABLED NULLCLAW_HTTP_MAX_RESPONSE_SIZE NULLCLAW_HTTP_TIMEOUT_SECS NULLCLAW_HTTP_ALLOWED_DOMAINS NULLCLAW_HTTP_ALLOW_PRIVATE_HOSTS NULLCLAW_WEB_SEARCH_BASE_URL NULLCLAW_WEB_SEARCH_PROVIDER NULLCLAW_WEB_SEARCH_FALLBACK_PROVIDERS \
  NULLCLAW_BROWSER_ENABLED NULLCLAW_BROWSER_BACKEND NULLCLAW_BROWSER_NATIVE_HEADLESS NULLCLAW_BROWSER_NATIVE_WEBDRIVER_URL NULLCLAW_BROWSER_NATIVE_CHROME_PATH NULLCLAW_BROWSER_SESSION_NAME NULLCLAW_BROWSER_ALLOWED_DOMAINS \
  NULLCLAW_AUTONOMY_LEVEL NULLCLAW_WORKSPACE_ONLY NULLCLAW_MAX_ACTIONS_PER_HOUR NULLCLAW_REQUIRE_APPROVAL_FOR_MEDIUM_RISK NULLCLAW_BLOCK_HIGH_RISK_COMMANDS NULLCLAW_ALLOWED_COMMANDS NULLCLAW_ALLOWED_PATHS \
  NULLCLAW_RELIABILITY_PROVIDER_RETRIES NULLCLAW_RELIABILITY_PROVIDER_BACKOFF_MS NULLCLAW_RELIABILITY_FALLBACK_PROVIDERS NULLCLAW_RELIABILITY_API_KEYS NULLCLAW_RELIABILITY_MODEL_FALLBACK_SOURCE NULLCLAW_RELIABILITY_MODEL_FALLBACKS \
  NULLCLAW_SHELL_TIMEOUT_SECS NULLCLAW_SHELL_MAX_OUTPUT_BYTES NULLCLAW_MAX_FILE_SIZE_BYTES NULLCLAW_WEB_FETCH_MAX_CHARS \
  NULLCLAW_WEB_ENABLED NULLCLAW_WEB_ACCOUNT_ID NULLCLAW_WEB_TRANSPORT NULLCLAW_WEB_LISTEN NULLCLAW_WEB_PORT NULLCLAW_WEB_PATH NULLCLAW_WEB_MAX_CONNECTIONS NULLCLAW_WEB_AUTH_TOKEN NULLCLAW_WEB_TOKEN NULLCLAW_GATEWAY_TOKEN OPENCLAW_GATEWAY_TOKEN NULLCLAW_WEB_MESSAGE_AUTH_MODE NULLCLAW_WEB_ALLOWED_ORIGINS NULLCLAW_WEB_RELAY_URL NULLCLAW_WEB_RELAY_AGENT_ID NULLCLAW_WEB_RELAY_TOKEN NULLCLAW_RELAY_TOKEN NULLCLAW_WEB_RELAY_TOKEN_TTL_SECS NULLCLAW_WEB_RELAY_PAIRING_CODE_TTL_SECS NULLCLAW_WEB_RELAY_UI_TOKEN_TTL_SECS NULLCLAW_WEB_RELAY_E2E_REQUIRED \
  NULLCLAW_AGENT_RUNBOOK_PATH \
  NULLCLAW_MCP_PLAYWRIGHT_ENABLED NULLCLAW_MCP_PLAYWRIGHT_NAME NULLCLAW_MCP_PLAYWRIGHT_COMMAND NULLCLAW_MCP_PLAYWRIGHT_PACKAGE NULLCLAW_MCP_PLAYWRIGHT_HEADLESS NULLCLAW_MCP_PLAYWRIGHT_ISOLATED NULLCLAW_MCP_PLAYWRIGHT_BROWSER NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT NULLCLAW_MCP_PLAYWRIGHT_CDP_HEADER NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_HOSTS NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_ORIGINS NULLCLAW_MCP_PLAYWRIGHT_IGNORE_HTTPS_ERRORS NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR NULLCLAW_MCP_PLAYWRIGHT_OUTPUT_DIR NULLCLAW_MCP_PLAYWRIGHT_SAVE_SESSION NULLCLAW_MCP_PLAYWRIGHT_SHARED_BROWSER_CONTEXT NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX \
  PINCHTAB_ENABLED PINCHTAB_BIND PINCHTAB_PORT PINCHTAB_TOKEN PINCHTAB_HEADLESS_DEFAULT PINCHTAB_STATE_DIR PINCHTAB_PROFILE PINCHTAB_STEALTH PINCHTAB_BLOCK_ADS PINCHTAB_BLOCK_IMAGES PINCHTAB_BLOCK_MEDIA PINCHTAB_DEBUG PINCHTAB_LOG_LEVEL PINCHTAB_NO_DASHBOARD PINCHTAB_CHROME_BINARY PINCHTAB_CHROME_FLAGS PINCHTAB_NOVNC_ENABLED PINCHTAB_DISPLAY PINCHTAB_SCREEN PINCHTAB_VNC_PORT PINCHTAB_NOVNC_PORT PINCHTAB_NOVNC_WEB_DIR PINCHTAB_NOVNC_PUBLIC_PATH PINCHTAB_API_PUBLIC_PATH PINCHTAB_VNC_PASSWORD PINCHTAB_VNC_VIEW_ONLY PINCHTAB_STARTUP_TIMEOUT_SECS NULLCLAW_GATEWAY_INTERNAL_PORT \
  PINCHTAB_NOVNC_AUTOSTART_HEADED PINCHTAB_NOVNC_AUTOSTART_PROFILE PINCHTAB_NOVNC_AUTOSTART_URL \
  BRIDGE_BIND BRIDGE_PORT BRIDGE_TOKEN BRIDGE_HEADLESS BRIDGE_STATE_DIR BRIDGE_PROFILE BRIDGE_STEALTH BRIDGE_BLOCK_ADS BRIDGE_BLOCK_IMAGES BRIDGE_BLOCK_MEDIA BRIDGE_DEBUG BRIDGE_LOG_LEVEL BRIDGE_NO_DASHBOARD CHROME_BINARY CHROME_FLAGS DISPLAY \
  OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY ANTHROPIC_OAUTH_TOKEN GROQ_API_KEY GEMINI_API_KEY XAI_API_KEY DEEPSEEK_API_KEY COHERE_API_KEY MISTRAL_API_KEY PERPLEXITY_API_KEY TOGETHER_API_KEY BRAVE_API_KEY FIRECRAWL_API_KEY TAVILY_API_KEY EXA_API_KEY JINA_API_KEY
do
  sanitize_env_var "$_env_name"
done

NULLCLAW_HOME="${NULLCLAW_HOME:-/data}"
CONFIG_DIR="${NULLCLAW_HOME}/.nullclaw"
CONFIG_PATH="${CONFIG_DIR}/config.json"
WORKSPACE_DIR="${NULLCLAW_WORKSPACE:-${CONFIG_DIR}/workspace}"

PROVIDER="${NULLCLAW_PROVIDER:-openrouter}"
HOST="${NULLCLAW_GATEWAY_HOST:-0.0.0.0}"
PORT="${PORT:-3000}"
PUBLIC_PORT="$(to_uint_or_default "$PORT" "3000")"
NULLCLAW_GATEWAY_PORT="$PUBLIC_PORT"

ALLOW_PUBLIC_BIND_JSON="$(to_json_bool "${NULLCLAW_ALLOW_PUBLIC_BIND:-true}")"
REQUIRE_PAIRING_JSON="$(to_json_bool "${NULLCLAW_REQUIRE_PAIRING:-false}")"
REWRITE_CONFIG="$(to_json_bool "${NULLCLAW_REWRITE_CONFIG:-true}")"

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
NULLCLAW_HTTP_ALLOW_PRIVATE_HOSTS="${NULLCLAW_HTTP_ALLOW_PRIVATE_HOSTS:-true}"
export NULLCLAW_HTTP_ALLOW_PRIVATE_HOSTS
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

NULLCLAW_MCP_PLAYWRIGHT_ENABLED_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_ENABLED:-false}")"
NULLCLAW_MCP_PLAYWRIGHT_NAME="${NULLCLAW_MCP_PLAYWRIGHT_NAME:-playwright}"
NULLCLAW_MCP_PLAYWRIGHT_COMMAND="${NULLCLAW_MCP_PLAYWRIGHT_COMMAND:-npx}"
NULLCLAW_MCP_PLAYWRIGHT_PACKAGE="${NULLCLAW_MCP_PLAYWRIGHT_PACKAGE:-@playwright/mcp}"
NULLCLAW_MCP_PLAYWRIGHT_HEADLESS_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_HEADLESS:-true}")"
NULLCLAW_MCP_PLAYWRIGHT_ISOLATED_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_ISOLATED:-true}")"
NULLCLAW_MCP_PLAYWRIGHT_BROWSER="${NULLCLAW_MCP_PLAYWRIGHT_BROWSER:-}"
NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT="${NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT:-}"
NULLCLAW_MCP_PLAYWRIGHT_CDP_HEADER="${NULLCLAW_MCP_PLAYWRIGHT_CDP_HEADER:-}"
NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_HOSTS="${NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_HOSTS:-}"
NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_ORIGINS="${NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_ORIGINS:-}"
NULLCLAW_MCP_PLAYWRIGHT_IGNORE_HTTPS_ERRORS_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_IGNORE_HTTPS_ERRORS:-false}")"
NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH="${NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH:-}"
NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR="${NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR:-}"
NULLCLAW_MCP_PLAYWRIGHT_OUTPUT_DIR="${NULLCLAW_MCP_PLAYWRIGHT_OUTPUT_DIR:-}"
NULLCLAW_MCP_PLAYWRIGHT_SAVE_SESSION_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_SAVE_SESSION:-false}")"
NULLCLAW_MCP_PLAYWRIGHT_SHARED_BROWSER_CONTEXT_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_SHARED_BROWSER_CONTEXT:-false}")"
NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX_JSON="$(to_json_bool "${NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX:-false}")"

NULLCLAW_AUTONOMY_LEVEL="${NULLCLAW_AUTONOMY_LEVEL:-full}"
NULLCLAW_WORKSPACE_ONLY_JSON="$(to_json_bool "${NULLCLAW_WORKSPACE_ONLY:-false}")"
NULLCLAW_MAX_ACTIONS_PER_HOUR="$(to_uint_or_default "${NULLCLAW_MAX_ACTIONS_PER_HOUR:-100000}" "100000")"
NULLCLAW_REQUIRE_APPROVAL_MEDIUM_JSON="$(to_json_bool "${NULLCLAW_REQUIRE_APPROVAL_FOR_MEDIUM_RISK:-false}")"
NULLCLAW_BLOCK_HIGH_RISK_JSON="$(to_json_bool "${NULLCLAW_BLOCK_HIGH_RISK_COMMANDS:-false}")"
NULLCLAW_ALLOWED_COMMANDS_CSV="${NULLCLAW_ALLOWED_COMMANDS:-*}"
NULLCLAW_ALLOWED_PATHS_CSV="${NULLCLAW_ALLOWED_PATHS:-*}"
NULLCLAW_RELIABILITY_PROVIDER_RETRIES="$(to_uint_or_default "${NULLCLAW_RELIABILITY_PROVIDER_RETRIES:-2}" "2")"
NULLCLAW_RELIABILITY_PROVIDER_BACKOFF_MS="$(to_uint_or_default "${NULLCLAW_RELIABILITY_PROVIDER_BACKOFF_MS:-500}" "500")"
NULLCLAW_RELIABILITY_FALLBACK_PROVIDERS_CSV="${NULLCLAW_RELIABILITY_FALLBACK_PROVIDERS:-}"
NULLCLAW_RELIABILITY_API_KEYS_CSV="${NULLCLAW_RELIABILITY_API_KEYS:-}"
NULLCLAW_RELIABILITY_MODEL_FALLBACK_SOURCE="${NULLCLAW_RELIABILITY_MODEL_FALLBACK_SOURCE:-}"
NULLCLAW_RELIABILITY_MODEL_FALLBACKS_CSV="${NULLCLAW_RELIABILITY_MODEL_FALLBACKS:-}"

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

PINCHTAB_ENABLED_JSON="$(to_json_bool "${PINCHTAB_ENABLED:-true}")"
PINCHTAB_BIND="${PINCHTAB_BIND:-${BRIDGE_BIND:-127.0.0.1}}"
PINCHTAB_PORT="$(to_uint_or_default "${PINCHTAB_PORT:-${BRIDGE_PORT:-9867}}" "9867")"
PINCHTAB_TOKEN="${PINCHTAB_TOKEN:-${BRIDGE_TOKEN:-}}"
PINCHTAB_HEADLESS_DEFAULT_JSON="$(to_json_bool "${PINCHTAB_HEADLESS_DEFAULT:-${BRIDGE_HEADLESS:-true}}")"
PINCHTAB_STATE_DIR="${PINCHTAB_STATE_DIR:-${BRIDGE_STATE_DIR:-${NULLCLAW_HOME}/.pinchtab}}"
PINCHTAB_PROFILE="${PINCHTAB_PROFILE:-${BRIDGE_PROFILE:-default}}"
PINCHTAB_STEALTH="${PINCHTAB_STEALTH:-${BRIDGE_STEALTH:-light}}"
PINCHTAB_BLOCK_ADS_JSON="$(to_json_bool "${PINCHTAB_BLOCK_ADS:-${BRIDGE_BLOCK_ADS:-false}}")"
PINCHTAB_BLOCK_IMAGES_JSON="$(to_json_bool "${PINCHTAB_BLOCK_IMAGES:-${BRIDGE_BLOCK_IMAGES:-false}}")"
PINCHTAB_BLOCK_MEDIA_JSON="$(to_json_bool "${PINCHTAB_BLOCK_MEDIA:-${BRIDGE_BLOCK_MEDIA:-false}}")"
PINCHTAB_DEBUG_JSON="$(to_json_bool "${PINCHTAB_DEBUG:-${BRIDGE_DEBUG:-false}}")"
PINCHTAB_LOG_LEVEL="${PINCHTAB_LOG_LEVEL:-${BRIDGE_LOG_LEVEL:-info}}"
PINCHTAB_NO_DASHBOARD_JSON="$(to_json_bool "${PINCHTAB_NO_DASHBOARD:-${BRIDGE_NO_DASHBOARD:-false}}")"
PINCHTAB_CHROME_BINARY="${PINCHTAB_CHROME_BINARY:-${CHROME_BINARY:-}}"
PINCHTAB_CHROME_FLAGS="${PINCHTAB_CHROME_FLAGS:-${CHROME_FLAGS:---no-sandbox --disable-gpu --disable-dev-shm-usage}}"
PINCHTAB_NOVNC_ENABLED_JSON="$(to_json_bool "${PINCHTAB_NOVNC_ENABLED:-true}")"
PINCHTAB_DISPLAY="${PINCHTAB_DISPLAY:-${DISPLAY:-:99}}"
PINCHTAB_SCREEN="${PINCHTAB_SCREEN:-1280x720x24}"
PINCHTAB_VNC_PORT="$(to_uint_or_default "${PINCHTAB_VNC_PORT:-5900}" "5900")"
PINCHTAB_NOVNC_PORT="$(to_uint_or_default "${PINCHTAB_NOVNC_PORT:-6080}" "6080")"
PINCHTAB_NOVNC_WEB_DIR="${PINCHTAB_NOVNC_WEB_DIR:-/usr/share/novnc}"
PINCHTAB_NOVNC_PUBLIC_PATH="${PINCHTAB_NOVNC_PUBLIC_PATH:-}"
PINCHTAB_API_PUBLIC_PATH="${PINCHTAB_API_PUBLIC_PATH:-}"
PINCHTAB_VNC_PASSWORD="${PINCHTAB_VNC_PASSWORD:-}"
PINCHTAB_VNC_VIEW_ONLY_JSON="$(to_json_bool "${PINCHTAB_VNC_VIEW_ONLY:-false}")"
PINCHTAB_STARTUP_TIMEOUT_SECS="$(to_uint_or_default "${PINCHTAB_STARTUP_TIMEOUT_SECS:-30}" "30")"
PINCHTAB_NOVNC_AUTOSTART_HEADED_JSON="$(to_json_bool "${PINCHTAB_NOVNC_AUTOSTART_HEADED:-true}")"
PINCHTAB_NOVNC_AUTOSTART_PROFILE="${PINCHTAB_NOVNC_AUTOSTART_PROFILE:-${PINCHTAB_PROFILE:-default}}"
PINCHTAB_NOVNC_AUTOSTART_URL="${PINCHTAB_NOVNC_AUTOSTART_URL:-https://example.com}"
NULLCLAW_GATEWAY_INTERNAL_PORT="$(to_uint_or_default "${NULLCLAW_GATEWAY_INTERNAL_PORT:-3001}" "3001")"
NULLCLAW_AGENT_RUNBOOK_PATH="${NULLCLAW_AGENT_RUNBOOK_PATH:-/opt/nullclaw/AGENT_BROWSER_NOVNC.md}"
RAILWAY_PUBLIC_DOMAIN="$(strip_wrapping_quotes "${RAILWAY_PUBLIC_DOMAIN:-}")"

PUBLIC_GATEWAY_PROXY_ENABLED=false
NOVNC_PUBLIC_PATH=""
PINCHTAB_API_PUBLIC_PATH_NORM=""
if [ "$PINCHTAB_ENABLED_JSON" = "true" ] && [ "$PINCHTAB_NOVNC_ENABLED_JSON" = "true" ] && [ -n "$PINCHTAB_NOVNC_PUBLIC_PATH" ]; then
  NOVNC_PUBLIC_PATH="$PINCHTAB_NOVNC_PUBLIC_PATH"
  if [ "${NOVNC_PUBLIC_PATH#/}" = "$NOVNC_PUBLIC_PATH" ]; then
    NOVNC_PUBLIC_PATH="/${NOVNC_PUBLIC_PATH}"
  fi
  if [ "$NOVNC_PUBLIC_PATH" != "/" ]; then
    NOVNC_PUBLIC_PATH="${NOVNC_PUBLIC_PATH%/}"
  fi
  case "$NOVNC_PUBLIC_PATH" in
    ''|'/')
      echo "ERROR: PINCHTAB_NOVNC_PUBLIC_PATH must not be empty or '/' when noVNC is enabled." >&2
      exit 1
      ;;
    *[!A-Za-z0-9/_-]*)
      echo "ERROR: PINCHTAB_NOVNC_PUBLIC_PATH contains unsupported characters: ${NOVNC_PUBLIC_PATH}" >&2
      exit 1
      ;;
  esac
fi

if [ "$PINCHTAB_ENABLED_JSON" = "true" ] && [ -n "$PINCHTAB_API_PUBLIC_PATH" ]; then
  PINCHTAB_API_PUBLIC_PATH_NORM="$PINCHTAB_API_PUBLIC_PATH"
  if [ "${PINCHTAB_API_PUBLIC_PATH_NORM#/}" = "$PINCHTAB_API_PUBLIC_PATH_NORM" ]; then
    PINCHTAB_API_PUBLIC_PATH_NORM="/${PINCHTAB_API_PUBLIC_PATH_NORM}"
  fi
  if [ "$PINCHTAB_API_PUBLIC_PATH_NORM" != "/" ]; then
    PINCHTAB_API_PUBLIC_PATH_NORM="${PINCHTAB_API_PUBLIC_PATH_NORM%/}"
  fi
  case "$PINCHTAB_API_PUBLIC_PATH_NORM" in
    ''|'/')
      echo "ERROR: PINCHTAB_API_PUBLIC_PATH must not be empty or '/'." >&2
      exit 1
      ;;
    *[!A-Za-z0-9/_-]*)
      echo "ERROR: PINCHTAB_API_PUBLIC_PATH contains unsupported characters: ${PINCHTAB_API_PUBLIC_PATH_NORM}" >&2
      exit 1
      ;;
  esac
fi

if [ -n "$NOVNC_PUBLIC_PATH" ] || [ -n "$PINCHTAB_API_PUBLIC_PATH_NORM" ]; then
  PUBLIC_GATEWAY_PROXY_ENABLED=true
  NULLCLAW_GATEWAY_PORT="$NULLCLAW_GATEWAY_INTERNAL_PORT"
fi

NOVNC_PUBLIC_URL=""
PINCHTAB_API_PUBLIC_URL=""
if [ -n "$RAILWAY_PUBLIC_DOMAIN" ] && [ "$PUBLIC_GATEWAY_PROXY_ENABLED" = "true" ]; then
  if [ -n "$NOVNC_PUBLIC_PATH" ]; then
  NOVNC_PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}${NOVNC_PUBLIC_PATH}/vnc.html?autoconnect=1&resize=scale"
  fi
  if [ -n "$PINCHTAB_API_PUBLIC_PATH_NORM" ]; then
    PINCHTAB_API_PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}${PINCHTAB_API_PUBLIC_PATH_NORM}"
  fi
fi

if is_placeholder_value "$NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT"; then
  echo "WARN: Ignoring placeholder NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT value; using local browser mode." >&2
  NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT=""
fi
if is_placeholder_value "$NULLCLAW_WEB_RELAY_URL"; then
  NULLCLAW_WEB_RELAY_URL=""
fi
if is_placeholder_value "$NULLCLAW_WEB_RELAY_TOKEN"; then
  NULLCLAW_WEB_RELAY_TOKEN=""
fi
if is_placeholder_value "$PINCHTAB_TOKEN"; then
  echo "WARN: Ignoring placeholder PINCHTAB_TOKEN value; PinchTab auth token disabled." >&2
  PINCHTAB_TOKEN=""
fi

if [ -z "$PINCHTAB_CHROME_BINARY" ]; then
  for _chrome_bin in /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/google-chrome-stable; do
    if [ -x "$_chrome_bin" ]; then
      PINCHTAB_CHROME_BINARY="$_chrome_bin"
      break
    fi
  done
fi

MCP_BROWSER_LC="$(printf '%s' "$NULLCLAW_MCP_PLAYWRIGHT_BROWSER" | tr '[:upper:]' '[:lower:]')"
case "$MCP_BROWSER_LC" in
  ''|chrome|firefox|webkit|msedge) ;;
  chromium)
    # @playwright/mcp expects chrome channel name; pair with explicit Chromium path.
    NULLCLAW_MCP_PLAYWRIGHT_BROWSER="chrome"
    ;;
  *)
    echo "WARN: Unsupported NULLCLAW_MCP_PLAYWRIGHT_BROWSER='$NULLCLAW_MCP_PLAYWRIGHT_BROWSER'; letting Playwright choose default browser." >&2
    NULLCLAW_MCP_PLAYWRIGHT_BROWSER=""
    ;;
esac

if [ -z "$NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH" ]; then
  for _pw_bin in /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/google-chrome-stable; do
    if [ -x "$_pw_bin" ]; then
      NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH="$_pw_bin"
      break
    fi
  done
fi

if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR" ] && [ "$NULLCLAW_MCP_PLAYWRIGHT_ISOLATED_JSON" = "true" ]; then
  echo "WARN: NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR is set; forcing NULLCLAW_MCP_PLAYWRIGHT_ISOLATED=false for persistent sessions." >&2
  NULLCLAW_MCP_PLAYWRIGHT_ISOLATED_JSON="false"
fi
if [ "$(id -u)" = "0" ] && [ "$NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX_JSON" != "true" ]; then
  echo "WARN: Container is running as root; forcing Playwright --no-sandbox." >&2
  NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX_JSON="true"
fi

WEB_TRANSPORT_LC="$(printf '%s' "$NULLCLAW_WEB_TRANSPORT" | tr '[:upper:]' '[:lower:]')"
if [ "$NULLCLAW_WEB_ENABLED_JSON" = "true" ] && [ "$WEB_TRANSPORT_LC" = "relay" ]; then
  if [ -z "$NULLCLAW_WEB_RELAY_URL" ] || [ -z "$NULLCLAW_WEB_RELAY_TOKEN" ]; then
    echo "WARN: NULLCLAW_WEB_ENABLED=true with relay transport but relay URL/token is missing or placeholder; disabling web channel." >&2
    NULLCLAW_WEB_ENABLED_JSON="false"
  fi
fi

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

if [ "$NULLCLAW_MCP_PLAYWRIGHT_ENABLED_JSON" = "true" ]; then
  if ! command -v "$NULLCLAW_MCP_PLAYWRIGHT_COMMAND" >/dev/null 2>&1; then
    echo "ERROR: NULLCLAW_MCP_PLAYWRIGHT_ENABLED=true but command '$NULLCLAW_MCP_PLAYWRIGHT_COMMAND' is not available in PATH." >&2
    exit 1
  fi
fi

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

WORKSPACE_NOVNC_URL="$NOVNC_PUBLIC_URL"
if [ -z "$WORKSPACE_NOVNC_URL" ]; then
  WORKSPACE_NOVNC_URL="http://127.0.0.1:${PINCHTAB_NOVNC_PORT}/vnc.html?autoconnect=1&resize=scale"
fi
WORKSPACE_NOVNC_PASSWORD="${PINCHTAB_VNC_PASSWORD:-not-set}"
WORKSPACE_PINCHTAB_API="http://127.0.0.1:${PINCHTAB_PORT}"
WORKSPACE_PINCHTAB_API_PUBLIC="${PINCHTAB_API_PUBLIC_URL:-not-configured}"
WORKSPACE_PINCHTAB_TOKEN="${PINCHTAB_TOKEN:-not-set}"
write_workspace_browser_docs "$WORKSPACE_DIR" "$WORKSPACE_NOVNC_URL" "$WORKSPACE_NOVNC_PASSWORD" "$WORKSPACE_PINCHTAB_API" "$WORKSPACE_PINCHTAB_API_PUBLIC" "$WORKSPACE_PINCHTAB_TOKEN" "$PINCHTAB_NOVNC_PORT"

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

  RELIABILITY_FALLBACKS_JSON="$(csv_to_json_array "$NULLCLAW_RELIABILITY_FALLBACK_PROVIDERS_CSV")"
  RELIABILITY_API_KEYS_JSON="$(csv_to_json_array "$NULLCLAW_RELIABILITY_API_KEYS_CSV")"
  RELIABILITY_MODEL_FALLBACKS_FIELD=""
  if [ -n "$NULLCLAW_RELIABILITY_MODEL_FALLBACKS_CSV" ]; then
    RELIABILITY_MODEL_SOURCE="$NULLCLAW_RELIABILITY_MODEL_FALLBACK_SOURCE"
    if [ -z "$RELIABILITY_MODEL_SOURCE" ]; then
      RELIABILITY_MODEL_SOURCE="$MODEL"
    fi
    RELIABILITY_MODEL_SOURCE_ESC="$(json_escape "$RELIABILITY_MODEL_SOURCE")"
    RELIABILITY_MODEL_FALLBACKS_JSON="$(csv_to_json_array "$NULLCLAW_RELIABILITY_MODEL_FALLBACKS_CSV")"
    RELIABILITY_MODEL_FALLBACKS_FIELD=$(cat <<EOF_REL_MODEL
,
    "model_fallbacks": [
      {
        "model": "$RELIABILITY_MODEL_SOURCE_ESC",
        "fallbacks": $RELIABILITY_MODEL_FALLBACKS_JSON
      }
    ]
EOF_REL_MODEL
)
  fi

  RELIABILITY_BLOCK=$(cat <<EOF_RELIABILITY
,
  "reliability": {
    "provider_retries": $NULLCLAW_RELIABILITY_PROVIDER_RETRIES,
    "provider_backoff_ms": $NULLCLAW_RELIABILITY_PROVIDER_BACKOFF_MS,
    "fallback_providers": $RELIABILITY_FALLBACKS_JSON,
    "api_keys": $RELIABILITY_API_KEYS_JSON$RELIABILITY_MODEL_FALLBACKS_FIELD
  }
EOF_RELIABILITY
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

  MCP_SERVERS_BLOCK=""
  if [ "$NULLCLAW_MCP_PLAYWRIGHT_ENABLED_JSON" = "true" ]; then
    MCP_PLAYWRIGHT_NAME_ESC="$(json_escape "$NULLCLAW_MCP_PLAYWRIGHT_NAME")"
    MCP_PLAYWRIGHT_COMMAND_ESC="$(json_escape "$NULLCLAW_MCP_PLAYWRIGHT_COMMAND")"
    MCP_PLAYWRIGHT_PACKAGE_ESC="$(json_escape "$NULLCLAW_MCP_PLAYWRIGHT_PACKAGE")"

    MCP_ARGS_ITEMS=""
    append_mcp_arg() {
      arg_esc="$(json_escape "$1")"
      if [ -n "$MCP_ARGS_ITEMS" ]; then
        MCP_ARGS_ITEMS="$MCP_ARGS_ITEMS, \"$arg_esc\""
      else
        MCP_ARGS_ITEMS="\"$arg_esc\""
      fi
    }

    append_mcp_arg "-y"
    append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_PACKAGE"
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_HEADLESS_JSON" = "true" ]; then
      append_mcp_arg "--headless"
    fi
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_ISOLATED_JSON" = "true" ]; then
      append_mcp_arg "--isolated"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_BROWSER" ]; then
      append_mcp_arg "--browser"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_BROWSER"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT" ]; then
      append_mcp_arg "--cdp-endpoint"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_CDP_ENDPOINT"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_CDP_HEADER" ]; then
      append_mcp_arg "--cdp-header"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_CDP_HEADER"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_HOSTS" ]; then
      append_mcp_arg "--allowed-hosts"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_HOSTS"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_ORIGINS" ]; then
      append_mcp_arg "--allowed-origins"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_ALLOWED_ORIGINS"
    fi
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_IGNORE_HTTPS_ERRORS_JSON" = "true" ]; then
      append_mcp_arg "--ignore-https-errors"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH" ]; then
      append_mcp_arg "--executable-path"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_EXECUTABLE_PATH"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR" ]; then
      append_mcp_arg "--user-data-dir"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_USER_DATA_DIR"
    fi
    if [ -n "$NULLCLAW_MCP_PLAYWRIGHT_OUTPUT_DIR" ]; then
      append_mcp_arg "--output-dir"
      append_mcp_arg "$NULLCLAW_MCP_PLAYWRIGHT_OUTPUT_DIR"
    fi
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_SAVE_SESSION_JSON" = "true" ]; then
      append_mcp_arg "--save-session"
    fi
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_SHARED_BROWSER_CONTEXT_JSON" = "true" ]; then
      append_mcp_arg "--shared-browser-context"
    fi
    if [ "$NULLCLAW_MCP_PLAYWRIGHT_NO_SANDBOX_JSON" = "true" ]; then
      append_mcp_arg "--no-sandbox"
    fi

    MCP_ARGS_JSON="[$MCP_ARGS_ITEMS]"
    MCP_SERVERS_BLOCK=$(cat <<EOF_MCP
,
  "mcp_servers": {
    "$MCP_PLAYWRIGHT_NAME_ESC": {
      "command": "$MCP_PLAYWRIGHT_COMMAND_ESC",
      "args": $MCP_ARGS_JSON
    }
  }
EOF_MCP
)
  fi

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

  AGENT_RUNBOOK_CONTENT=""
  if [ -f "$NULLCLAW_AGENT_RUNBOOK_PATH" ]; then
    AGENT_RUNBOOK_CONTENT="$(cat "$NULLCLAW_AGENT_RUNBOOK_PATH")"
  fi

  AGENT_NOVNC_PUBLIC_URL="${NOVNC_PUBLIC_URL:-not-configured}"
  AGENT_NOVNC_PASSWORD="${PINCHTAB_VNC_PASSWORD:-not-set}"
  AGENT_PINCHTAB_TOKEN="${PINCHTAB_TOKEN:-not-set}"
  AGENT_NOVNC_PUBLIC_PATH="${NOVNC_PUBLIC_PATH:-not-configured}"
  AGENT_PINCHTAB_API_INTERNAL_URL="http://127.0.0.1:${PINCHTAB_PORT}"
  AGENT_PINCHTAB_API_PUBLIC_URL="${PINCHTAB_API_PUBLIC_URL:-not-configured}"
  AGENT_PINCHTAB_API_URL="$AGENT_PINCHTAB_API_INTERNAL_URL"
  if [ -n "$PINCHTAB_API_PUBLIC_URL" ]; then
    AGENT_PINCHTAB_API_URL="$PINCHTAB_API_PUBLIC_URL"
  fi

  AGENT_RUNTIME_CONTEXT_MD=$(cat <<EOF_AGENT_RUNTIME
## Runtime Endpoints (Auto-Injected)
- noVNC URL (for user): \`${AGENT_NOVNC_PUBLIC_URL}\`
- noVNC password: \`${AGENT_NOVNC_PASSWORD}\`
- noVNC public path: \`${AGENT_NOVNC_PUBLIC_PATH}\`
- PinchTab API endpoint (use this first): \`${AGENT_PINCHTAB_API_URL}\`
- PinchTab API (public): \`${AGENT_PINCHTAB_API_PUBLIC_URL}\`
- PinchTab API (internal): \`${AGENT_PINCHTAB_API_INTERNAL_URL}\`
- PinchTab bearer token (internal): \`${AGENT_PINCHTAB_TOKEN}\`

If browser task requires account login, direct the user to noVNC first, ask them to confirm when login is done, then continue and provide the requested report.
Never ask the user for PinchTab token. Use the injected token above; if token is \`not-set\`, call PinchTab without Authorization header.
If PinchTab returns unauthorized, retry once using the other endpoint (public vs internal) before reporting failure.
EOF_AGENT_RUNTIME
)

  if [ -n "$AGENT_RUNBOOK_CONTENT" ]; then
    AGENT_SYSTEM_PROMPT_RAW="${AGENT_RUNBOOK_CONTENT}

${AGENT_RUNTIME_CONTEXT_MD}"
  else
    AGENT_SYSTEM_PROMPT_RAW="$AGENT_RUNTIME_CONTEXT_MD"
  fi
  AGENT_SYSTEM_PROMPT_ESC="$(json_escape_multiline "$AGENT_SYSTEM_PROMPT_RAW")"

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
      "model": { "primary": "$PRIMARY_MODEL_ESC" },
      "system_prompt": "$AGENT_SYSTEM_PROMPT_ESC"
    }
  }$TOOLS_BLOCK$MEMORY_BLOCK$HTTP_REQUEST_BLOCK$AUTONOMY_BLOCK$RELIABILITY_BLOCK$BROWSER_BLOCK,
  "gateway": {
    "port": $NULLCLAW_GATEWAY_PORT,
    "host": "$HOST_ESC",
    "allow_public_bind": $ALLOW_PUBLIC_BIND_JSON,
    "require_pairing": $REQUIRE_PAIRING_JSON
  }$CHANNELS_BLOCK$MCP_SERVERS_BLOCK
}
EOF_CONFIG
fi

export HOME="$NULLCLAW_HOME"
export NULLCLAW_WORKSPACE="$WORKSPACE_DIR"

BACKGROUND_PIDS=""
track_pid() {
  pid="$1"
  if [ -n "$BACKGROUND_PIDS" ]; then
    BACKGROUND_PIDS="${BACKGROUND_PIDS} ${pid}"
  else
    BACKGROUND_PIDS="${pid}"
  fi
}

start_bg() {
  label="$1"
  shift
  "$@" &
  pid=$!
  track_pid "$pid"
  echo "Started ${label} (pid=${pid})"
}

cleanup_background() {
  trap - EXIT INT TERM
  for pid in $BACKGROUND_PIDS; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
  for pid in $BACKGROUND_PIDS; do
    wait "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup_background EXIT INT TERM

if [ "$PUBLIC_GATEWAY_PROXY_ENABLED" = "true" ]; then
  if ! command -v caddy >/dev/null 2>&1; then
    echo "ERROR: noVNC public path proxy requires 'caddy' binary." >&2
    exit 1
  fi
  if [ "$PUBLIC_PORT" = "$NULLCLAW_GATEWAY_PORT" ]; then
    echo "ERROR: NULLCLAW_GATEWAY_INTERNAL_PORT must differ from PORT when noVNC public path proxy is enabled." >&2
    exit 1
  fi
fi

if [ "$PINCHTAB_ENABLED_JSON" = "true" ]; then
  if ! command -v pinchtab >/dev/null 2>&1; then
    echo "ERROR: PINCHTAB_ENABLED=true but 'pinchtab' binary is not available in PATH." >&2
    exit 1
  fi

  mkdir -p "$PINCHTAB_STATE_DIR"

  export BRIDGE_BIND="$PINCHTAB_BIND"
  export BRIDGE_PORT="$PINCHTAB_PORT"
  export BRIDGE_HEADLESS="$PINCHTAB_HEADLESS_DEFAULT_JSON"
  export BRIDGE_STATE_DIR="$PINCHTAB_STATE_DIR"
  export BRIDGE_PROFILE="$PINCHTAB_PROFILE"
  export BRIDGE_STEALTH="$PINCHTAB_STEALTH"
  export BRIDGE_BLOCK_ADS="$PINCHTAB_BLOCK_ADS_JSON"
  export BRIDGE_BLOCK_IMAGES="$PINCHTAB_BLOCK_IMAGES_JSON"
  export BRIDGE_BLOCK_MEDIA="$PINCHTAB_BLOCK_MEDIA_JSON"
  export BRIDGE_DEBUG="$PINCHTAB_DEBUG_JSON"
  export BRIDGE_LOG_LEVEL="$PINCHTAB_LOG_LEVEL"
  export BRIDGE_NO_DASHBOARD="$PINCHTAB_NO_DASHBOARD_JSON"
  if [ -n "$PINCHTAB_TOKEN" ]; then
    export BRIDGE_TOKEN="$PINCHTAB_TOKEN"
  else
    unset BRIDGE_TOKEN || true
    if [ "$PINCHTAB_BIND" = "0.0.0.0" ]; then
      echo "WARN: PinchTab is exposed on 0.0.0.0 without PINCHTAB_TOKEN." >&2
    fi
  fi
  if [ -n "$PINCHTAB_CHROME_BINARY" ]; then
    export CHROME_BINARY="$PINCHTAB_CHROME_BINARY"
  fi
  export CHROME_FLAGS="$PINCHTAB_CHROME_FLAGS"

  if [ "$PINCHTAB_NOVNC_ENABLED_JSON" = "true" ]; then
    for _display_cmd in Xvfb x11vnc websockify; do
      if ! command -v "$_display_cmd" >/dev/null 2>&1; then
        echo "ERROR: PINCHTAB_NOVNC_ENABLED=true but '${_display_cmd}' is missing." >&2
        exit 1
      fi
    done
    if [ ! -d "$PINCHTAB_NOVNC_WEB_DIR" ]; then
      echo "ERROR: noVNC web dir '${PINCHTAB_NOVNC_WEB_DIR}' does not exist." >&2
      exit 1
    fi

    export DISPLAY="$PINCHTAB_DISPLAY"
    echo "Starting noVNC on http://0.0.0.0:${PINCHTAB_NOVNC_PORT}/vnc.html (display=${PINCHTAB_DISPLAY}, vnc=${PINCHTAB_VNC_PORT})"
    start_bg "Xvfb" Xvfb "$PINCHTAB_DISPLAY" -screen 0 "$PINCHTAB_SCREEN" -ac +extension RANDR
    sleep 1

    PINCHTAB_VNC_PASS_FILE=""
    if [ -n "$PINCHTAB_VNC_PASSWORD" ]; then
      PINCHTAB_VNC_PASS_FILE="${PINCHTAB_STATE_DIR}/.vnc-passwd"
      x11vnc -storepasswd "$PINCHTAB_VNC_PASSWORD" "$PINCHTAB_VNC_PASS_FILE" >/dev/null
      chmod 600 "$PINCHTAB_VNC_PASS_FILE" || true
    else
      echo "WARN: noVNC is enabled without PINCHTAB_VNC_PASSWORD; VNC access is unauthenticated." >&2
    fi

    if [ "$PINCHTAB_VNC_VIEW_ONLY_JSON" = "true" ]; then
      if [ -n "$PINCHTAB_VNC_PASS_FILE" ]; then
        start_bg "x11vnc" x11vnc -display "$PINCHTAB_DISPLAY" -rfbport "$PINCHTAB_VNC_PORT" -forever -shared -viewonly -rfbauth "$PINCHTAB_VNC_PASS_FILE"
      else
        start_bg "x11vnc" x11vnc -display "$PINCHTAB_DISPLAY" -rfbport "$PINCHTAB_VNC_PORT" -forever -shared -viewonly -nopw
      fi
    else
      if [ -n "$PINCHTAB_VNC_PASS_FILE" ]; then
        start_bg "x11vnc" x11vnc -display "$PINCHTAB_DISPLAY" -rfbport "$PINCHTAB_VNC_PORT" -forever -shared -rfbauth "$PINCHTAB_VNC_PASS_FILE"
      else
        start_bg "x11vnc" x11vnc -display "$PINCHTAB_DISPLAY" -rfbport "$PINCHTAB_VNC_PORT" -forever -shared -nopw
      fi
    fi

    start_bg "websockify" websockify --web "$PINCHTAB_NOVNC_WEB_DIR" "$PINCHTAB_NOVNC_PORT" "127.0.0.1:${PINCHTAB_VNC_PORT}"
    wait_for_http_health "http://127.0.0.1:${PINCHTAB_NOVNC_PORT}/vnc.html" "$PINCHTAB_STARTUP_TIMEOUT_SECS" "noVNC"
  fi

  echo "Starting PinchTab bridge on ${PINCHTAB_BIND}:${PINCHTAB_PORT} (headless_default=${PINCHTAB_HEADLESS_DEFAULT_JSON}, state_dir=${PINCHTAB_STATE_DIR})"
  start_bg "PinchTab" pinchtab
  wait_for_http_health "http://127.0.0.1:${PINCHTAB_PORT}/health" "$PINCHTAB_STARTUP_TIMEOUT_SECS" "PinchTab" "$PINCHTAB_TOKEN"
  cleanup_stale_chromium_locks "${PINCHTAB_STATE_DIR}/profiles"

  if [ "$PINCHTAB_NOVNC_ENABLED_JSON" = "true" ] && [ "$PINCHTAB_NOVNC_AUTOSTART_HEADED_JSON" = "true" ]; then
    if [ -x /usr/local/bin/pinchtab-client.sh ]; then
      export PINCHTAB_BASE_URL="http://127.0.0.1:${PINCHTAB_PORT}"
      export PINCHTAB_TOKEN
      AUTOSTART_PROFILE="$PINCHTAB_NOVNC_AUTOSTART_PROFILE"

      if ! /usr/local/bin/pinchtab-client.sh profiles all 2>/dev/null | grep -F "\"name\":\"${AUTOSTART_PROFILE}\"" >/dev/null 2>&1; then
        /usr/local/bin/pinchtab-client.sh profile-create "$AUTOSTART_PROFILE" "Auto-created for noVNC headed startup" "manual browser login in noVNC" >/dev/null 2>&1 || true
      fi

      STARTED_INSTANCE_JSON="$(/usr/local/bin/pinchtab-client.sh start "$AUTOSTART_PROFILE" headed 2>/dev/null || true)"
      AUTOSTART_INSTANCE_ID="$(printf '%s' "$STARTED_INSTANCE_JSON" | jq -r '.id // empty' 2>/dev/null || true)"
      if [ -n "$AUTOSTART_INSTANCE_ID" ] && [ -n "$PINCHTAB_NOVNC_AUTOSTART_URL" ]; then
        /usr/local/bin/pinchtab-client.sh navigate "$AUTOSTART_INSTANCE_ID" "$PINCHTAB_NOVNC_AUTOSTART_URL" >/dev/null 2>&1 || true
      fi
      if [ -n "$AUTOSTART_INSTANCE_ID" ]; then
        echo "PinchTab headed instance started for noVNC (profile=${AUTOSTART_PROFILE}, instance=${AUTOSTART_INSTANCE_ID})"
      else
        echo "WARN: Failed to auto-start headed PinchTab instance for noVNC (profile=${AUTOSTART_PROFILE})." >&2
      fi
    else
      echo "WARN: /usr/local/bin/pinchtab-client.sh is missing; skipping noVNC headed auto-start." >&2
    fi
  fi
else
  if [ "$PINCHTAB_NOVNC_ENABLED_JSON" = "true" ]; then
    echo "WARN: PINCHTAB_NOVNC_ENABLED=true ignored because PINCHTAB_ENABLED=false." >&2
  fi
fi

echo "Starting nullclaw gateway on ${HOST}:${NULLCLAW_GATEWAY_PORT} with provider=${PROVIDER} model=${PRIMARY_MODEL}"
nullclaw gateway --host "$HOST" --port "$NULLCLAW_GATEWAY_PORT" &
NULLCLAW_PID=$!
track_pid "$NULLCLAW_PID"
echo "Started nullclaw gateway (pid=${NULLCLAW_PID})"

if [ "$PUBLIC_GATEWAY_PROXY_ENABLED" = "true" ]; then
  CADDYFILE_PATH="${CONFIG_DIR}/Caddyfile"
  CADDY_HANDLE_BLOCKS=""
  if [ -n "$NOVNC_PUBLIC_PATH" ]; then
    CADDY_HANDLE_BLOCKS="${CADDY_HANDLE_BLOCKS}
  handle_path ${NOVNC_PUBLIC_PATH}* {
    reverse_proxy 127.0.0.1:${PINCHTAB_NOVNC_PORT}
  }"
  fi
  if [ -n "$PINCHTAB_API_PUBLIC_PATH_NORM" ]; then
    CADDY_HANDLE_BLOCKS="${CADDY_HANDLE_BLOCKS}
  handle_path ${PINCHTAB_API_PUBLIC_PATH_NORM}* {
    reverse_proxy 127.0.0.1:${PINCHTAB_PORT}
  }"
  fi
  cat > "$CADDYFILE_PATH" <<EOF_CADDY
:${PUBLIC_PORT} {
${CADDY_HANDLE_BLOCKS}
  reverse_proxy 127.0.0.1:${NULLCLAW_GATEWAY_PORT}
}
EOF_CADDY
  echo "Starting caddy public proxy on 0.0.0.0:${PUBLIC_PORT} (noVNC path=${NOVNC_PUBLIC_PATH:-disabled}, pinchtab path=${PINCHTAB_API_PUBLIC_PATH_NORM:-disabled})"
  start_bg "Caddy" caddy run --config "$CADDYFILE_PATH" --adapter caddyfile
  wait_for_http_health "http://127.0.0.1:${PUBLIC_PORT}/health" "$PINCHTAB_STARTUP_TIMEOUT_SECS" "Gateway proxy"
fi

set +e
wait "$NULLCLAW_PID"
NULLCLAW_STATUS=$?
set -e
exit "$NULLCLAW_STATUS"
