#!/usr/bin/env bash
# Remove a client (both from the server and the local copy). Pass -y to skip the prompt.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="amneziawg"
NAME="${1:-}"

if [ -z "${NAME}" ]; then
  echo "Usage: $(basename "$0") <client-name> [-y]"
  exit 1
fi

if [ "${2:-}" = "-y" ]; then
  docker exec "${CONTAINER}" awg_manage --removeclient "${NAME}" -y
else
  docker exec -it "${CONTAINER}" awg_manage --removeclient "${NAME}"
fi
rm -f "${DIR}/clients/${NAME}.conf"
