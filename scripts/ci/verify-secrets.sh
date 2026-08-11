#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|Bearer [A-Za-z0-9._-]{24,}|sk-[A-Za-z0-9_-]{20,}'
if git grep -nEI "$pattern" -- ':!scripts/ci/verify-secrets.sh' >/tmp/warehouse-secrets.$$ 2>/dev/null; then
  echo "Potential credential material found in tracked files:"
  cat /tmp/warehouse-secrets.$$
  rm -f /tmp/warehouse-secrets.$$
  exit 1
fi
rm -f /tmp/warehouse-secrets.$$ 2>/dev/null || true

echo "Secret check passed: no common private-key, bearer-token, or API-key patterns found in tracked files."
