#!/bin/sh
set -eu

BASE_URL="${PINCHTAB_BASE_URL:-http://127.0.0.1:9867}"
TOKEN="${PINCHTAB_TOKEN:-}"
SESSION_MAP_DIR="${PINCHTAB_SESSION_MAP_DIR:-${HOME:-/tmp}/.nullclaw/pinchtab-sessions}"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for this command." >&2
    exit 1
  fi
}

curl_api() {
  method="$1"
  path="$2"
  body="${3:-}"
  url="${BASE_URL}${path}"
  if [ -n "$body" ]; then
    if [ -n "$TOKEN" ]; then
      curl -sS -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "$body"
    else
      curl -sS -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -d "$body"
    fi
  else
    if [ -n "$TOKEN" ]; then
      curl -sS -X "$method" "$url" \
        -H "Authorization: Bearer $TOKEN"
    else
      curl -sS -X "$method" "$url"
    fi
  fi
}

sanitize_profile_key() {
  printf '%s' "$1" | tr '/ ' '__' | tr -cd '[:alnum:]_.-'
}

profile_map_file() {
  profile_key="$(sanitize_profile_key "$1")"
  printf '%s/%s.instance' "$SESSION_MAP_DIR" "$profile_key"
}

tab_map_file() {
  instance_key="$(sanitize_profile_key "$1")"
  printf '%s/%s.tab' "$SESSION_MAP_DIR" "$instance_key"
}

store_profile_instance() {
  profile="$1"
  instance_id="$2"
  mkdir -p "$SESSION_MAP_DIR"
  printf '%s\n' "$instance_id" > "$(profile_map_file "$profile")"
}

load_profile_instance() {
  profile="$1"
  map_file="$(profile_map_file "$profile")"
  if [ -f "$map_file" ]; then
    sed -n '1p' "$map_file"
  fi
}

clear_profile_instance() {
  profile="$1"
  map_file="$(profile_map_file "$profile")"
  rm -f "$map_file"
}

store_instance_tab() {
  instance_id="$1"
  tab_id="$2"
  mkdir -p "$SESSION_MAP_DIR"
  printf '%s\n' "$tab_id" > "$(tab_map_file "$instance_id")"
}

load_instance_tab() {
  instance_id="$1"
  map_file="$(tab_map_file "$instance_id")"
  if [ -f "$map_file" ]; then
    sed -n '1p' "$map_file"
  fi
}

clear_instance_tab() {
  instance_id="$1"
  map_file="$(tab_map_file "$instance_id")"
  rm -f "$map_file"
}

instance_exists() {
  require_jq
  instance_id="$1"
  instances="$(curl_api GET "/instances")"
  if printf '%s' "$instances" | jq -e --arg id "$instance_id" '.[] | select(.id == $id)' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

find_running_instance_for_profile() {
  require_jq
  profile="$1"
  instances="$(curl_api GET "/instances")"
  printf '%s' "$instances" | jq -r --arg profile "$profile" '
    .[] | select(.profileId == $profile or .profileName == $profile) | .id
  ' | head -n 1
}

resolve_instance_target() {
  target="$1"
  case "$target" in
    inst_*)
      printf '%s' "$target"
      return 0
      ;;
    @*)
      profile="${target#@}"
      mapped="$(load_profile_instance "$profile")"
      if [ -n "${mapped:-}" ] && instance_exists "$mapped"; then
        printf '%s' "$mapped"
        return 0
      fi
      found="$(find_running_instance_for_profile "$profile")"
      if [ -n "$found" ]; then
        store_profile_instance "$profile" "$found"
        printf '%s' "$found"
        return 0
      fi
      echo "ERROR: no running instance found for profile '$profile'." >&2
      exit 1
      ;;
    *)
      found="$(find_running_instance_for_profile "$target")"
      if [ -n "$found" ]; then
        store_profile_instance "$target" "$found"
        printf '%s' "$found"
      else
        printf '%s' "$target"
      fi
      ;;
  esac
}

resolve_tab_for_instance() {
  instance_id="$1"
  mapped_tab="$(load_instance_tab "$instance_id")"
  if [ -n "${mapped_tab:-}" ]; then
    printf '%s' "$mapped_tab"
    return 0
  fi
  echo "ERROR: no tracked tab for instance '${instance_id}'. Run 'navigate' first." >&2
  exit 1
}

wait_for_instance_running() {
  require_jq
  instance_id="$1"
  timeout_secs="${PINCHTAB_INSTANCE_READY_TIMEOUT_SECS:-30}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout_secs" ]; do
    status="$(curl_api GET "/instances" | jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .status')"
    case "$status" in
      running) return 0 ;;
      error)
        echo "ERROR: instance '${instance_id}' failed to start." >&2
        exit 1
        ;;
      *)
        ;;
    esac
    elapsed=$((elapsed + 1))
    sleep 1
  done
  echo "ERROR: instance '${instance_id}' did not reach running state within ${timeout_secs}s." >&2
  exit 1
}

build_start_payload() {
  require_jq
  profile="${1:-}"
  mode="${2:-headless}"
  port="${3:-}"
  printf '%s' "$mode" | grep -Eq '^(headless|headed)$' || {
    echo "ERROR: mode must be 'headless' or 'headed'." >&2
    exit 1
  }
  jq -nc \
    --arg profile "$profile" \
    --arg mode "$mode" \
    --arg port "$port" '
      {
        profileId: ($profile | if . == "" then null else . end),
        mode: ($mode | if . == "" then null else . end),
        port: ($port | if . == "" then null else . end)
      }
      | with_entries(select(.value != null))
    '
}

usage() {
  cat <<'EOF'
Usage:
  pinchtab-client.sh health
  pinchtab-client.sh list-instances
  pinchtab-client.sh profiles [all]
  pinchtab-client.sh profile-create <name> [description] [use_when]
  pinchtab-client.sh start <profile-id-or-name> [headed|headless] [port]
  pinchtab-client.sh stop <instance-id|@profile>
  pinchtab-client.sh stop-profile <profile-id-or-name>
  pinchtab-client.sh switch-mode <profile-id-or-name> <headed|headless>
  pinchtab-client.sh tabs <instance-id|@profile>
  pinchtab-client.sh navigate <instance-id|@profile> <url>
  pinchtab-client.sh snapshot <instance-id|@profile> [query]
  pinchtab-client.sh text <instance-id|@profile>
  pinchtab-client.sh click <instance-id|@profile> <ref>
  pinchtab-client.sh fill <instance-id|@profile> <ref> <text>
  pinchtab-client.sh press <instance-id|@profile> <ref> <key>
  pinchtab-client.sh cookies <instance-id|@profile>
  pinchtab-client.sh novnc-url [host]

Notes:
  - Use '@profile' to target the last known running instance for that profile.
  - 'start' stores profile->instance mapping in PINCHTAB_SESSION_MAP_DIR.
  - 'navigate' stores instance->tab mapping used by snapshot/text/action/cookies.

Environment:
  PINCHTAB_BASE_URL         default: http://127.0.0.1:9867
  PINCHTAB_TOKEN            optional Bearer token
  PINCHTAB_SESSION_MAP_DIR  default: ~/.nullclaw/pinchtab-sessions
  PINCHTAB_NOVNC_PORT       default: 6080
  PINCHTAB_INSTANCE_READY_TIMEOUT_SECS default: 30
EOF
}

cmd="${1:-}"
case "$cmd" in
  health)
    curl_api GET "/health"
    ;;
  list-instances|instances)
    curl_api GET "/instances"
    ;;
  profiles)
    if [ "${2:-}" = "all" ]; then
      curl_api GET "/profiles?all=true"
    else
      curl_api GET "/profiles"
    fi
    ;;
  profile-create)
    name="${2:-}"
    description="${3:-}"
    use_when="${4:-}"
    [ -n "$name" ] || { usage >&2; exit 1; }
    require_jq
    payload="$(jq -nc \
      --arg name "$name" \
      --arg description "$description" \
      --arg useWhen "$use_when" '
        {
          name: $name,
          description: ($description | if . == "" then null else . end),
          useWhen: ($useWhen | if . == "" then null else . end)
        } | with_entries(select(.value != null))
      ')"
    curl_api POST "/profiles" "$payload"
    ;;
  start)
    profile="${2:-}"
    mode="${3:-headless}"
    port="${4:-}"
    [ -n "$profile" ] || { usage >&2; exit 1; }
    payload="$(build_start_payload "$profile" "$mode" "$port")"
    response="$(curl_api POST "/instances/start" "$payload")"
    printf '%s\n' "$response"
    require_jq
    instance_id="$(printf '%s' "$response" | jq -r '.id // empty')"
    if [ -n "$instance_id" ]; then
      store_profile_instance "$profile" "$instance_id"
    fi
    ;;
  stop)
    target="${2:-}"
    [ -n "$target" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "$target")"
    curl_api POST "/instances/${instance_id}/stop"
    clear_instance_tab "$instance_id"
    case "$target" in
      @*) clear_profile_instance "${target#@}" ;;
    esac
    ;;
  stop-profile)
    profile="${2:-}"
    [ -n "$profile" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "@$profile")"
    curl_api POST "/instances/${instance_id}/stop"
    clear_instance_tab "$instance_id"
    clear_profile_instance "$profile"
    ;;
  switch-mode)
    profile="${2:-}"
    mode="${3:-}"
    [ -n "$profile" ] && [ -n "$mode" ] || { usage >&2; exit 1; }
    existing="$(find_running_instance_for_profile "$profile" || true)"
    if [ -n "${existing:-}" ]; then
      curl_api POST "/instances/${existing}/stop" >/dev/null
      clear_instance_tab "$existing"
    fi
    payload="$(build_start_payload "$profile" "$mode" "")"
    response="$(curl_api POST "/instances/start" "$payload")"
    printf '%s\n' "$response"
    require_jq
    instance_id="$(printf '%s' "$response" | jq -r '.id // empty')"
    if [ -n "$instance_id" ]; then
      store_profile_instance "$profile" "$instance_id"
    fi
    ;;
  tabs)
    target="${2:-}"
    [ -n "$target" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    curl_api GET "/instances/${instance_id}/tabs"
    ;;
  nav|navigate)
    target="${2:-}"
    url="${3:-}"
    [ -n "$target" ] && [ -n "$url" ] || { usage >&2; exit 1; }
    require_jq
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    payload="$(jq -nc --arg url "$url" '{url: $url}')"
    response="$(curl_api POST "/instances/${instance_id}/tabs/open" "$payload")"
    printf '%s\n' "$response"
    tab_id="$(printf '%s' "$response" | jq -r '.tabId // .id // empty')"
    if [ -n "$tab_id" ]; then
      store_instance_tab "$instance_id" "$tab_id"
    fi
    ;;
  snapshot|snap)
    target="${2:-}"
    query="${3:-format=compact&filter=interactive}"
    [ -n "$target" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    curl_api GET "/tabs/${tab_id}/snapshot?${query}"
    ;;
  text)
    target="${2:-}"
    [ -n "$target" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    curl_api GET "/tabs/${tab_id}/text"
    ;;
  click)
    target="${2:-}"
    ref="${3:-}"
    [ -n "$target" ] && [ -n "$ref" ] || { usage >&2; exit 1; }
    require_jq
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    payload="$(jq -nc --arg ref "$ref" '{kind:"click", ref:$ref}')"
    curl_api POST "/tabs/${tab_id}/action" "$payload"
    ;;
  fill)
    target="${2:-}"
    ref="${3:-}"
    text="${4:-}"
    [ -n "$target" ] && [ -n "$ref" ] && [ -n "$text" ] || { usage >&2; exit 1; }
    require_jq
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    payload="$(jq -nc --arg ref "$ref" --arg text "$text" '{kind:"fill", ref:$ref, text:$text}')"
    curl_api POST "/tabs/${tab_id}/action" "$payload"
    ;;
  press)
    target="${2:-}"
    ref="${3:-}"
    key="${4:-}"
    [ -n "$target" ] && [ -n "$ref" ] && [ -n "$key" ] || { usage >&2; exit 1; }
    require_jq
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    payload="$(jq -nc --arg ref "$ref" --arg key "$key" '{kind:"press", ref:$ref, key:$key}')"
    curl_api POST "/tabs/${tab_id}/action" "$payload"
    ;;
  cookies)
    target="${2:-}"
    [ -n "$target" ] || { usage >&2; exit 1; }
    instance_id="$(resolve_instance_target "$target")"
    wait_for_instance_running "$instance_id"
    tab_id="$(resolve_tab_for_instance "$instance_id")"
    curl_api GET "/tabs/${tab_id}/cookies"
    ;;
  novnc-url)
    host="${2:-localhost}"
    port="${PINCHTAB_NOVNC_PORT:-6080}"
    printf 'http://%s:%s/vnc.html?autoconnect=1&resize=scale\n' "$host" "$port"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
