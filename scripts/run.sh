#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
open "$PWD/build/PDF Compressor.app"
