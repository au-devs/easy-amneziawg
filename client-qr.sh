#!/usr/bin/env bash
# Show the QR code for an existing client.
set -euo pipefail

CONTAINER="amneziawg"
NAME="${1:-}"

if [ -z "${NAME}" ]; then
  echo "Usage: $(basename "$0") <client-name>"
  exit 1
fi

docker exec "${CONTAINER}" awg_manage --showclientqr "${NAME}"
