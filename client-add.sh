#!/usr/bin/env bash
# Add an AmneziaWG client, save its config next to this script, and show the QR.
#
# --split (default): tunnel everything except the private networks. For Android/iOS.
# --full: plain 0.0.0.0/0. Use for Linux and macOS, where wg-quick needs a /0 prefix
# to keep the route to the server's Endpoint out of the tunnel.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="amneziawg"
NAME="${1:-}"
MODE="${2:-}"

if [ -z "${NAME}" ]; then
  echo "Usage: $(basename "$0") <client-name> [--full|--split]"
  exit 1
fi

case "${MODE}" in
  ""|--full|--split) ;;
  *) echo "Usage: $(basename "$0") <client-name> [--full|--split]"; exit 1 ;;
esac

docker exec "${CONTAINER}" awg_manage --addclient "${NAME}" ${MODE}

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
