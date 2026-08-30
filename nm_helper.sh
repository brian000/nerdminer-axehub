#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nm_helper.sh <ip> [options]

Configure display brightness and the nightly backlight sleep window on a
single NerdMiner AxeHub device, or query live info from the AxeHub API.

Arguments:
  <ip>                  Device IP address (required)

Options:
  --on <HH:MM>          Time backlight turns back on (sleep_window end). Default: 09:00
  --off <HH:MM>         Time backlight turns off (sleep_window start). Default: 23:30
  --brightness <0-255>  Backlight brightness level. Default: 150
  --user                Query /info and print the user field from the response
  --hashrate            Query /info and print current_khs from the response
  -h, --help            Show this help and exit

Examples:
  nm_helper.sh 192.168.2.11 --on 08:00 --off 22:00 --brightness 200
  nm_helper.sh 192.168.2.11 --user
  nm_helper.sh 192.168.2.11 --hashrate
EOF
}

ip=""
brightness=150
start="23:30"
end="09:00"
query=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --on)
      end="$2"
      shift 2
      ;;
    --off)
      start="$2"
      shift 2
      ;;
    --brightness)
      brightness="$2"
      shift 2
      ;;
    --user)
      query="user"
      shift
      ;;
    --hashrate)
      query="hashrate"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$ip" ]]; then
        ip="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$ip" ]]; then
  echo "Error: <ip> is required" >&2
  usage
  exit 1
fi

if [[ -n "$query" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for query mode" >&2
    exit 1
  fi

  info_json="$(curl -fsS -H 'X-AxeHub-Compat: 1' "http://$ip/api/axehub/v1/info")"

  case "$query" in
    user)
      echo "$info_json" | jq -r '.pool.primary.user // .pool.fallback.user // empty'
      ;;
    hashrate)
      echo "$info_json" | jq -r '.hashing.current_khs // empty'
      ;;
  esac
  exit 0
fi

printf '== %s ==\n' "$ip"

if ! curl -fsS -H 'X-AxeHub-Compat: 1' -H 'Content-Type: application/json' \
    -X POST "http://$ip/api/axehub/v1/display/brightness" \
    --data "{\"value\":${brightness},\"persist\":true}" >/dev/null; then
  echo "brightness update failed"
else
  echo "brightness -> ${brightness}"
fi

if ! curl -fsS -H 'X-AxeHub-Compat: 1' -H 'Content-Type: application/json' \
    -X POST "http://$ip/api/axehub/v1/display/sleep_window" \
    --data "{\"start\":\"${start}\",\"end\":\"${end}\"}" >/dev/null; then
  echo "sleep_window update failed"
else
  echo "sleep_window -> ${start} to ${end}"
fi
