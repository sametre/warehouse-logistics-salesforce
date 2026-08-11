#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TARGET_ORG="${1:-${SF_TARGET_ORG:-}}"

if [[ -z "$TARGET_ORG" ]]; then
  echo "Usage: scripts/ci/run-salesforce-gate.sh <target-org-alias>"
  exit 2
fi
if ! command -v sf >/dev/null 2>&1; then
  echo "Salesforce CLI (sf) is required."
  exit 2
fi

mkdir -p reports/apex
sf code-analyzer run \
  --workspace force-app \
  --rule-selector Recommended \
  --severity-threshold 3 \
  --output-file reports/code-analyzer.json

sf project deploy validate \
  --source-dir force-app \
  --target-org "$TARGET_ORG" \
  --test-level RunLocalTests \
  --wait 30

sf apex run test \
  --target-org "$TARGET_ORG" \
  --suite-names Warehouse_Week10 \
  --code-coverage \
  --detailed-coverage \
  --result-format junit \
  --output-dir reports/apex \
  --wait 30
