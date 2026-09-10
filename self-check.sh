#!/usr/bin/env bash
# Run your own capstone rubric before the grader does (docs/RUBRIC.md).
# This covers the mechanical half: if any check is red here, it will be red there.
# It cannot judge run history or writing quality — those need time and a human eye.
set -uo pipefail

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "== Docs =="
[ -f README.md ] && ok "README.md exists" || bad "README.md missing (auto-fail trigger)"
[ -f docs/CONTROLS.md ] && ok "docs/CONTROLS.md exists" || bad "docs/CONTROLS.md missing"
grep -qi "blast radius" stages/06-enforcement/*.tf 2>/dev/null \
  && ok "blast-radius notes present in enforcement stage" \
  || bad "no blast-radius documentation in stages/06-enforcement"

echo "== IaC quality (Tier 0 mirrors) =="
if terraform fmt -check -recursive stages/ >/dev/null 2>&1; then
  ok "terraform fmt clean across stages/"
else
  bad "terraform fmt -check has diffs (run: terraform fmt -recursive stages/)"
fi
for d in stages/*/; do
  name=$(basename "$d")
  if (cd "$d" && terraform init -backend=false -input=false >/dev/null 2>&1 \
      && terraform validate >/dev/null 2>&1); then
    ok "terraform validate: $name"
  else
    bad "terraform validate fails: $name"
  fi
done

echo "== Evidence integrity config =="
grep -rq "azurerm_storage_container_immutability_policy" stages/ \
  && ok "WORM immutability policy present" \
  || bad "no immutability policy resource found"
grep -rq "shared_access_key_enabled *= *false" stages/ \
  && ok "shared keys disabled on evidence storage" \
  || bad "shared_access_key_enabled=false not found"
grep -rq "runId" functions/collect_assessments/*.py \
  && ok "collector stamps run lineage" \
  || bad "collector has no runId stamping"

echo "== Identity design =="
if grep -rqE 'role_definition_name *= *"(Owner|Contributor)"' stages/; then
  bad 'a pipeline identity holds Owner/Contributor (whitelist roles only)'
else
  ok "no broad roles granted in Terraform"
fi
grep -rq "identity {" stages/01-foundation/policies.tf stages/06-enforcement/*.tf 2>/dev/null \
  && ok "policy assignments carry identity blocks" \
  || bad "a remediation-effect assignment may be missing its identity block"

echo "== Operations =="
[ -f .github/workflows/gate.yml ] && ok "CI gate workflow present" || bad "gate workflow missing"
[ -f .github/workflows/drift.yml ] && ok "drift workflow present" || bad "drift workflow missing"
ls policy/*.rego >/dev/null 2>&1 && ok "OPA gate rules present" || bad "no policy/*.rego rules"
if command -v conftest >/dev/null 2>&1; then
  echo "  (tip: prove the gate blocks — plan a public storage account and conftest it)"
else
  echo "  (conftest not installed locally — CI still runs it)"
fi

echo "== Secrets (auto-fail trigger) =="
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --exit-code 1 >/dev/null 2>&1; then
    ok "gitleaks: no secrets detected"
  else
    bad "gitleaks found potential secrets — fix and rotate BEFORE submitting"
  fi
else
  echo "  (gitleaks not installed — the grader WILL run it; brew install gitleaks)"
fi

echo
echo "self-check: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Fix the ✗ items before submitting. The grader checks all of this and more."
  exit 1
fi
echo "Mechanical checks green. Now verify the two things this script can't:"
echo "  1. Your timers have real run history (not a burst from last night)."
echo "  2. Every number in your reports traces to a stored document."
