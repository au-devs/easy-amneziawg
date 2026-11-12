#!/usr/bin/env bash
# List existing clients.
set -euo pipefail
CONTAINER="${CONTAINER:-amneziawg}"
docker exec "${CONTAINER}" awg_manage --listclients
