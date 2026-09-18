#!/usr/bin/env bash
# Proves the gate rules fire: the compliant example must pass, and every rule must reject the insecure one.
#   Usage: policy/test-examples.sh [conftest-binary]      (default: conftest on PATH)
# The expected-failure count is the number of deny rules exercised by fail/insecure-plan.json.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFTEST="${1:-conftest}"
EXPECTED_FAILURES=8

"$CONFTEST" test policy/examples/pass/compliant-plan.json -p policy >/dev/null
echo "PASS  compliant example produces no violations"

out="$("$CONFTEST" test policy/examples/fail/insecure-plan.json -p policy -o json || true)"
got="$(python3 -c 'import json,sys; print(sum(len(r.get("failures") or []) for r in json.load(sys.stdin)))' <<<"$out")"
if [ "$got" -ne "$EXPECTED_FAILURES" ]; then
  echo "FAIL  insecure example produced $got violations, expected $EXPECTED_FAILURES"; echo "$out"; exit 1
fi
echo "PASS  insecure example is rejected ($got violations, one per rule exercised)"
