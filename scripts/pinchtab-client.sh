#!/bin/sh
set -eu

BASE_URL="${PINCHTAB_BASE_URL:-http://127.0.0.1:9867}"
TOKEN="${PINCHTAB_TOKEN:-}"

auth_header() {
  if [ -n "$TOKEN" ]; then
    printf '%s' "Authorization: Bearer $TOKEN"
  fi
}

curl_json() {
  path="$1"
  body="${2:-}"
  if [ -n "$body" ]; then
    if [ -n "$TOKEN" ]; then
      curl -sS -X POST "${BASE_URL}${path}" \
        -H "Content-Type: application/json" \
        -H "$(auth_header)" \
        -d "$body"
    else
      curl -sS -X POST "${BASE_URL}${path}" \
        -H "Content-Type: application/json" \
        -d "$body"
    fi
  else
    if [ -n "$TOKEN" ]; then
      curl -sS "${BASE_URL}${path}" -H "$(auth_header)"
    else
      curl -sS "${BASE_URL}${path}"
    fi
  fi
}

usage() {
  cat <<'EOF'
Usage:
  pinchtab-client.sh health
  pinchtab-client.sh nav <url>
  pinchtab-client.sh snapshot [query]
  pinchtab-client.sh text
  pinchtab-client.sh click <ref>
  pinchtab-client.sh fill <ref> <text>
  pinchtab-client.sh press <ref> <key>
  pinchtab-client.sh cookies

Environment:
  PINCHTAB_BASE_URL  default: http://127.0.0.1:9867
  PINCHTAB_TOKEN     optional Bearer token
EOF
}

cmd="${1:-}"
case "$cmd" in
  health)
    curl_json "/health"
    ;;
  nav)
    url="${2:-}"
    [ -n "$url" ] || { usage >&2; exit 1; }
    curl_json "/navigate" "{\"url\":\"$url\"}"
    ;;
  snapshot|snap)
    query="${2:-format=compact&filter=interactive}"
    curl_json "/snapshot?$query"
    ;;
  text)
    curl_json "/text"
    ;;
  click)
    ref="${2:-}"
    [ -n "$ref" ] || { usage >&2; exit 1; }
    curl_json "/action" "{\"kind\":\"click\",\"ref\":\"$ref\"}"
    ;;
  fill)
    ref="${2:-}"
    text="${3:-}"
    [ -n "$ref" ] && [ -n "$text" ] || { usage >&2; exit 1; }
    curl_json "/action" "{\"kind\":\"fill\",\"ref\":\"$ref\",\"text\":\"$text\"}"
    ;;
  press)
    ref="${2:-}"
    key="${3:-}"
    [ -n "$ref" ] && [ -n "$key" ] || { usage >&2; exit 1; }
    curl_json "/action" "{\"kind\":\"press\",\"ref\":\"$ref\",\"key\":\"$key\"}"
    ;;
  cookies)
    curl_json "/cookies"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
