#!/usr/bin/env bash
set -euo pipefail

# --- Load env from .env if present (exporting vars) ---
# Resolve script directory so we can load a sibling .env regardless of CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try script-local .env first, then current working directory as fallback
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
  echo "Loaded env from $SCRIPT_DIR/.env" >&2
elif [[ -f ./.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
  echo "Loaded env from ./.env" >&2
fi

# --- Config / Defaults ---
DISCORD_API=${DISCORD_API:-"https://discord.com/api/v10"}
DISCORD_TOKEN=${DISCORD_TOKEN:-${BOT_TOKEN:-}}            # allow old var name BOT_TOKEN
APPLICATION_ID=${APPLICATION_ID:-}
GUILD_ID_ENV=${GUILD_ID:-}
SCOPE=""
DRY_RUN=0

usage() {
  cat <<USAGE
Register (bulk overwrite) Discord application commands.

Usage:
  $(basename "$0") [--global] [--guild <GUILD_ID>] [--dry-run]

Flags:
  --global            Register globally (visible in all guilds; can take up to 1 hr to propagate)
  --guild <ID>        Register for a specific guild (instant)
  --dry-run           Print the payload and endpoint without performing the request
  -h, --help          Show this help

Env vars (read from environment or a local .env file):
  DISCORD_TOKEN   (required) your bot token
  APPLICATION_ID  (required) your application (client) id
  GUILD_ID        (optional) default guild id if --guild omitted
  DISCORD_API     (optional) defaults to https://discord.com/api/v10
USAGE
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global) SCOPE="global"; shift ;;
    --guild|-g) SCOPE="guild"; GUILD_ID_ENV=${2:-""}; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# Decide scope if not provided
if [[ -z "$SCOPE" ]]; then
  if [[ -n "$GUILD_ID_ENV" ]]; then SCOPE="guild"; else SCOPE="global"; fi
fi

# --- Validate deps & inputs ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need curl

# Quick diagnostics for missing envs
missing=()
[[ -z ${DISCORD_TOKEN:-} ]] && missing+=(DISCORD_TOKEN)
[[ -z ${APPLICATION_ID:-} ]] && missing+=(APPLICATION_ID)
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required envs: ${missing[*]}" >&2
fi

if [[ -z "$DISCORD_TOKEN" || -z "$APPLICATION_ID" ]]; then
  echo "ERROR: Set DISCORD_TOKEN and APPLICATION_ID (env or .env)." >&2
  exit 1
fi

if [[ "$SCOPE" == "guild" && -z "$GUILD_ID_ENV" ]]; then
  echo "ERROR: --guild requires a guild id (pass via --guild <ID> or GUILD_ID env)." >&2
  exit 1
fi

# --- Define commands (bulk) ---
COMMANDS_JSON=$(cat <<'JSON'
[
  {
    "name": "generate-ideas",
    "description": "Initiates the idea generation workflow.",
    "type": 1
  },
  {
    "name": "new-idea",
    "description": "Create a new idea from a description.",
    "type": 1,
    "options": [
      {
        "name": "description",
        "description": "A brief description of the idea",
        "type": 3,
        "required": true
      }
    ]
  }
]
JSON
)

# --- Choose endpoint ---
if [[ "$SCOPE" == "guild" ]]; then
  ENDPOINT="$DISCORD_API/applications/$APPLICATION_ID/guilds/$GUILD_ID_ENV/commands"
  echo "Target: Guild commands (guild_id=$GUILD_ID_ENV)"
else
  ENDPOINT="$DISCORD_API/applications/$APPLICATION_ID/commands"
  echo "Target: Global commands"
fi

echo "Using endpoint: $ENDPOINT"

# --- Dry-run? ---
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf "\nDRY RUN — would PUT the following JSON:\n"
  echo "$COMMANDS_JSON" | sed 's/^/  /'
  exit 0
fi

# --- Register (bulk overwrite) ---
echo "Registering commands via bulk overwrite..."
HTTP_STATUS=$(curl -sS -o /tmp/discord_resp.json -w "%{http_code}" \
  -X PUT "$ENDPOINT" \
  -H "Authorization: Bot $DISCORD_TOKEN" \
  -H "Content-Type: application/json" \
  --data "$COMMANDS_JSON")

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then
  echo "Discord API returned HTTP $HTTP_STATUS" >&2
  echo "Response:" >&2
  cat /tmp/discord_resp.json >&2 || true
  exit 1
fi

echo "Success! Response:"
# Pretty-print if jq exists; otherwise cat
if command -v jq >/dev/null 2>&1; then
  jq . </tmp/discord_resp.json
else
  cat /tmp/discord_resp.json
fi

echo "Done."
