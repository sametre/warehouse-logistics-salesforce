#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSES="$ROOT/force-app/main/default/classes"
failed=0

while IFS= read -r file; do
  name="$(basename "$file")"
  case "$name" in
    *Selector.cls|*Test.cls) continue ;;
  esac
  if grep -nE '\bFROM[[:space:]]+[A-Za-z0-9_]+(__c)?\b' "$file" >/tmp/warehouse-soql.$$ 2>/dev/null; then
    echo "Direct SOQL found outside selector layer: $name"
    cat /tmp/warehouse-soql.$$
    failed=1
  fi
done < <(find "$CLASSES" -maxdepth 1 -type f -name '*.cls' | sort)
rm -f /tmp/warehouse-soql.$$ 2>/dev/null || true

for file in "$CLASSES"/*Controller.cls; do
  [[ -e "$file" ]] || continue
  if grep -nE '\b(Database\.(insert|update|delete|upsert)|insert[[:space:]]+|update[[:space:]]+|delete[[:space:]]+|upsert[[:space:]]+)' "$file" >/tmp/warehouse-dml.$$ 2>/dev/null; then
    echo "DML found in controller: $(basename "$file")"
    cat /tmp/warehouse-dml.$$
    failed=1
  fi
done
rm -f /tmp/warehouse-dml.$$ 2>/dev/null || true

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Architecture check passed: runtime SOQL is isolated in selectors and controllers contain no DML."
