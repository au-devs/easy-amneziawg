#!/usr/bin/env bash
# Fetch AmneziaWG client configs from a remote server by name mask.
#
# Usage:
#   ./fetch-clients.sh <ssh-host> [mask] [dest-dir]
#
# Examples:
#   ./fetch-clients.sh lit-vps 'utsg-*'          # only utsg-1..N
#   ./fetch-clients.sh lit-vps 'mila-*' ./mila   # mila-* into ./mila
#   ./fetch-clients.sh pol-vps                   # all clients (mask defaults to *)
#
# Env overrides:
#   CONTAINER   docker container name on the server (default: amneziawg)
set -euo pipefail

HOST="${1:-}"
MASK="${2:-*}"
DEST="${3:-./amneziawg-clients/${HOST}}"
CONTAINER="${CONTAINER:-amneziawg}"

if [ -z "${HOST}" ]; then
  echo "Usage: $(basename "$0") <ssh-host> [mask] [dest-dir]"
  exit 1
fi

names="$(ssh "${HOST}" "docker exec ${CONTAINER} awg_manage --listclients" 2>/dev/null | tr -d '\r')"
if [ -z "${names}" ]; then
  echo "No clients found on ${HOST} (container '${CONTAINER}')."
  exit 1
fi

mkdir -p "${DEST}"
count=0
matched=0
while IFS= read -r name; do
  [ -z "${name}" ] && continue
  # shellcheck disable=SC2254
  case "${name}" in
    ${MASK}) ;;
    *) continue ;;
  esac
  matched=$((matched+1))
  if ssh "${HOST}" "docker exec ${CONTAINER} awg_manage --showclientcfg ${name}" \
       > "${DEST}/${name}.conf" 2>/dev/null && [ -s "${DEST}/${name}.conf" ]; then
    chmod 600 "${DEST}/${name}.conf"
    echo "OK   ${name}"
    count=$((count+1))
  else
    rm -f "${DEST}/${name}.conf"
    echo "FAIL ${name}"
  fi
done <<< "${names}"

echo "---"
echo "Matched ${matched} client(s) for mask '${MASK}', fetched ${count} into ${DEST}"
