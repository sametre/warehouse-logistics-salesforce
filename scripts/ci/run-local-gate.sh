#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

./scripts/ci/verify-architecture.sh
python3 ./scripts/ci/verify-metadata.py
python3 ./scripts/ci/verify-permissions.py
python3 ./scripts/ci/verify-integration.py
./scripts/ci/verify-secrets.sh
git diff --check

echo "Local quality gate passed."
