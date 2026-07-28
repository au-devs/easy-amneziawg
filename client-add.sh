#!/usr/bin/env bash
# Add an AmneziaWG client, save its config next to this script, and show the QR.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="amneziawg"
NAME="${1:-}"

if [ -z "${NAME}" ]; then
  echo "Usage: $(basename "$0") <client-name>"
  exit 1
fi

docker exec "${CONTAINER}" awg_manage --addclient "${NAME}"

mkdir -p "${DIR}/clients"
# Write via stdout redirect so the file is owned by the current user (readable),
# unlike 'docker cp' which would copy it root-owned with mode 600.
docker exec "${CONTAINER}" awg_manage --showclientcfg "${NAME}" > "${DIR}/clients/${NAME}.conf"
chmod 600 "${DIR}/clients/${NAME}.conf"

echo
echo "Saved: ${DIR}/clients/${NAME}.conf"
echo
echo "Scan with the AmneziaWG app (NOT the plain WireGuard app):"
echo
docker exec "${CONTAINER}" awg_manage --showclientqr "${NAME}"
