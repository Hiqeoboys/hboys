#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
( cd "$ROOT/packages/mesh_protocol" && dart analyze && dart test )
( cd "$ROOT/packages/geo_utils" && dart analyze && dart test )
( cd "$ROOT/app" && flutter analyze && flutter test )
PYTHON_BIN="$(command -v python3 || command -v python)"
"$PYTHON_BIN" "$ROOT/data_pipeline/scripts/validate_trails.py" \
  "$ROOT/data_pipeline/packs/contoh_gunung/trails.geojson" \
  "$ROOT/data_pipeline/packs/contoh_gunung/poi.geojson"
