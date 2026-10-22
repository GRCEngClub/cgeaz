#!/usr/bin/env bash
# register-providers.sh — register every resource provider the course touches.
#
# A brand-new subscription has almost nothing registered. Terraform then fails with
# a provider-not-registered error that looks like a permissions problem and isn't
# (VALIDATION-LOG F1). Run this once, right after `az login`, before Lab 1.
#
#   ./labs/00-setup/register-providers.sh
#
# Idempotent: already-registered namespaces are skipped. Waits until every
# registration has finished (usually 2–3 minutes) so you don't hit the error later.
set -uo pipefail

command -v az >/dev/null 2>&1 || { echo "error: Azure CLI not found (docs/SETUP.md step 0)" >&2; exit 1; }
az account show --query id -o tsv >/dev/null 2>&1 || { echo "error: not signed in — run: az login" >&2; exit 1; }

# The eight the pipeline uses (Labs 1–6), then the three the capstone estate uses.
NAMESPACES=(
  Microsoft.Management
  Microsoft.OperationalInsights
  Microsoft.Security
  Microsoft.DocumentDB
  Microsoft.Web
  Microsoft.Storage
  Microsoft.Insights
  Microsoft.PolicyInsights
  Microsoft.KeyVault
  Microsoft.Network
  Microsoft.ManagedIdentity
)

echo ">> Subscription: $(az account show --query name -o tsv)"
for ns in "${NAMESPACES[@]}"; do
  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)"
  if [ "$state" = "Registered" ]; then
    echo "   already registered  $ns"
  else
    az provider register --namespace "$ns" --output none
    echo "   registering         $ns"
  fi
done

echo ">> Waiting for registration to finish"
for _ in $(seq 1 40); do
  pending=""
  for ns in "${NAMESPACES[@]}"; do
    state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)"
    [ "$state" = "Registered" ] || pending="$pending $ns"
  done
  if [ -z "$pending" ]; then
    echo ">> All ${#NAMESPACES[@]} providers registered."
    exit 0
  fi
  sleep 10
done

echo "!! Still registering after ~7 minutes:$pending" >&2
echo "   Check with: az provider list --query \"[?registrationState=='Registering'].namespace\"" >&2
exit 1
