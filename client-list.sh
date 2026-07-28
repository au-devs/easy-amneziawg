#!/usr/bin/env bash
# List existing clients.
set -euo pipefail
docker exec amneziawg awg_manage --listclients
