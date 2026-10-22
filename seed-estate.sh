#!/usr/bin/env bash
# seed-estate.sh — the FAFO capstone estate.
#
# The capstone brief describes FAFO: three subscriptions, four hundred resources.
# You have one free sandbox. This script closes that gap just enough to be honest:
# it deploys about a dozen cheap, free-tier-friendly resources into your sandbox,
# several of them deliberately misconfigured, so discovery finds something,
# assessments have something to assess, and your reports carry real findings with
# real resource IDs. You are graded on the pipeline, not the size of the estate.
#
#   ./seed-estate.sh              deploy (idempotent — re-run any time)
#   ./seed-estate.sh --teardown   delete everything this script created
#
# Cost: pennies at most. Free (F1) App Service plan, LRS storage, a standard Key
# Vault with no secrets in it, a VNet and NSG (free), a user-assigned identity (free).
# No VMs, no public IPs, no Cosmos. The Lab 1 budget alert is still watching.
#
# Run it after Lab 6, before you start the capstone build. Free accounts often have
# zero F1 App Service quota in eastus (same pattern as Y1 in Lab 4): set
# SEED_APP_LOCATION=centralus (or another region) if the plan create fails on quota.
# If your foundation's
# deny-public-blob policy is still at Deny, the one public-blob misconfiguration is
# refused by policy — that is the control working, and the script says so.
#
# Everything lands in two resource groups, rg-fafo-prod and rg-fafo-legacy, so the
# estate is separate from your pipeline and teardown is two deletes.
set -uo pipefail

export MSYS_NO_PATHCONV=1 # Git Bash: stop rewriting /subscriptions/... scopes into Windows paths

LOCATION="${SEED_LOCATION:-eastus}"
APP_LOCATION="${SEED_APP_LOCATION:-$LOCATION}"  # App Service F1 quota is regional; free accounts can have 0 in eastus
OWNER="${SEED_OWNER:-you@example.com}"

RG_PROD="rg-fafo-prod"
RG_LEGACY="rg-fafo-legacy"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
say()  { printf '\n==> %s\n' "$1"; }
ok()   { printf '  ✓ %s\n' "$1"; }
note() { printf '  · %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1" >&2; }
die()  { printf 'error: %s\n' "$1" >&2; exit 1; }

command -v az >/dev/null 2>&1 || die "Azure CLI not found (docs/SETUP.md step 0)"

SUB_ID="$(az account show --query id -o tsv 2>/dev/null)" || die "not signed in — run: az login"
SUB_NAME="$(az account show --query name -o tsv)"
# A stable per-subscription suffix keeps the globally unique names (storage, Key
# Vault, Web App) deterministic, so re-running finds the same resources.
SFX="$(printf '%s' "$SUB_ID" | tr -d '-' | cut -c1-6)"

ST_PUBLIC="stfafopub${SFX}"
ST_LOGS="stfafologs${SFX}"
ST_ARCHIVE="stfafoarch${SFX}"
KV="kv-fafo-${SFX}"
VNET="vnet-fafo"
SUBNET="snet-fafo-app"
NSG="nsg-fafo-open"
PLAN="plan-fafo-free-${APP_LOCATION}"
APP="app-fafo-${SFX}"
UAMI="id-fafo-batch"

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--teardown" ]; then
  say "Tearing down the FAFO estate in $SUB_NAME ($SUB_ID)"
  for rg in "$RG_PROD" "$RG_LEGACY"; do
    if az group exists --name "$rg" | grep -qi true; then
      az group delete --name "$rg" --yes >/dev/null && ok "deleted $rg"
    else
      note "$rg not present"
    fi
  done
  # Key Vault soft-delete keeps the name reserved for 90 days; purge so a
  # re-seed can reuse it. Purge protection is deliberately OFF on this vault.
  if az keyvault list-deleted --query "[?name=='$KV']" -o tsv | grep -q "$KV"; then
    if az keyvault purge --name "$KV" --location "$LOCATION" >/dev/null 2>&1; then
      ok "purged soft-deleted Key Vault $KV"
    else
      warn "could not purge $KV — run: az keyvault purge --name $KV --location $LOCATION"
    fi
  fi
  say "Done. Your pipeline's own resource groups were not touched."
  exit 0
fi

[ -n "${1:-}" ] && die "unknown argument: $1 (use --teardown, or no arguments)"

# ---------------------------------------------------------------------------
# deploy
# ---------------------------------------------------------------------------
say "Seeding the FAFO estate into $SUB_NAME ($SUB_ID), region $LOCATION"
note "owner tag: $OWNER  (override with SEED_OWNER=you@domain)"

# SETUP.md registers the eight providers the pipeline uses. The estate uses three more.
say "Resource providers"
for ns in Microsoft.KeyVault Microsoft.Network Microsoft.ManagedIdentity; do
  state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)"
  if [ "$state" != "Registered" ]; then
    az provider register --namespace "$ns" >/dev/null
    note "registering $ns"
  fi
done
for _ in $(seq 1 30); do
  pending="$(az provider list --query "[?registrationState=='Registering' && (namespace=='Microsoft.KeyVault' || namespace=='Microsoft.Network' || namespace=='Microsoft.ManagedIdentity')].namespace" -o tsv)"
  [ -z "$pending" ] && break
  sleep 10
done
ok "KeyVault, Network, ManagedIdentity registered"

# --- 1-2. Two resource groups: one governed, one that predates governance ------
say "Resource groups"
az group create --name "$RG_PROD" --location "$LOCATION" \
  --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
  && ok "$RG_PROD (tagged env=prod)"
# MISCONFIG: no env tag. The foundation's require-env-tag policy audits this one.
az group create --name "$RG_LEGACY" --location "$LOCATION" \
  --tags purpose=cge-az-capstone-seed >/dev/null \
  && ok "$RG_LEGACY (no env tag — deliberate)"

# --- 3. Public, plaintext, shared-key storage: the headline finding ----------
say "Storage accounts"
# MISCONFIG x2: public blob access, HTTP allowed. Shared keys stay on. (No TLS floor
# finding here: Azure retired TLS 1.0/1.1 for storage in Feb 2026 and silently
# upgrades the flag to 1.2 — found on the first live run, see VALIDATION-LOG F22.)
if ! out="$(az storage account create --name "$ST_PUBLIC" --resource-group "$RG_PROD" \
      --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
      --allow-blob-public-access true --https-only false \
      --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed 2>&1)"; then
  if printf '%s' "$out" | grep -q RequestDisallowedByPolicy; then
    warn "$ST_PUBLIC: public blob access was REFUSED by your deny-public-blob policy."
    note "That is the control working. Creating it without public access; the TLS and HTTPS findings remain."
    az storage account create --name "$ST_PUBLIC" --resource-group "$RG_PROD" \
      --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
      --https-only false \
      --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
      && ok "$ST_PUBLIC (HTTP allowed — deliberate; public blob blocked by policy)"
  else
    warn "$ST_PUBLIC failed: $(printf '%s' "$out" | head -3)"
  fi
else
  ok "$ST_PUBLIC (public blob + HTTP allowed — deliberate)"
fi

# MISCONFIG: defaults only, no tags, no diagnostic settings. The foundation's
# deployIfNotExists policy should route its diagnostics to the GRC workspace —
# watch the remediation task do it.
az storage account create --name "$ST_LOGS" --resource-group "$RG_LEGACY" \
  --location "$LOCATION" --sku Standard_LRS --kind StorageV2 >/dev/null \
  && ok "$ST_LOGS (untagged, no diagnostics — deliberate)"

# CONTROL: one account built to the pipeline's own standard, so your reports show
# a pass next to the fails and a reader can tell the difference.
az storage account create --name "$ST_ARCHIVE" --resource-group "$RG_PROD" \
  --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --min-tls-version TLS1_2 --https-only true \
  --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
  && ok "$ST_ARCHIVE (hardened — the control sample)"

# --- 6. Key Vault with the guardrails off ------------------------------------
say "Key Vault"
# A soft-deleted vault with this name blocks create; recover it instead.
if az keyvault list-deleted --query "[?name=='$KV']" -o tsv | grep -q "$KV"; then
  az keyvault recover --name "$KV" >/dev/null && note "recovered soft-deleted $KV"
fi
# MISCONFIG x3: purge protection off, public network access, legacy access policies
# instead of RBAC. Nothing is stored in it.
if az keyvault show --name "$KV" >/dev/null 2>&1; then
  ok "$KV already exists"
else
  az keyvault create --name "$KV" --resource-group "$RG_PROD" --location "$LOCATION" \
    --retention-days 7 \
    --public-network-access Enabled --enable-rbac-authorization false \
    --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
    && ok "$KV (no purge protection, public network, access policies — deliberate)"
fi

# --- 7-9. Network with management ports open to the internet -----------------
say "Network"
az network nsg create --name "$NSG" --resource-group "$RG_LEGACY" --location "$LOCATION" \
  --tags purpose=cge-az-capstone-seed >/dev/null && ok "$NSG"
# MISCONFIG: SSH and RDP from anywhere. No VM sits behind it (cost), so this is
# material for the policy YOU write — the rubric wants at least one of your own.
az network nsg rule create --nsg-name "$NSG" --resource-group "$RG_LEGACY" \
  --name allow-mgmt-from-internet --priority 100 --direction Inbound --access Allow \
  --protocol Tcp --source-address-prefixes Internet --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 22 3389 >/dev/null \
  && ok "$NSG rule: 22 + 3389 inbound from Internet — deliberate"
az network vnet create --name "$VNET" --resource-group "$RG_LEGACY" --location "$LOCATION" \
  --address-prefix 10.42.0.0/16 --subnet-name "$SUBNET" --subnet-prefix 10.42.1.0/24 \
  --network-security-group "$NSG" --tags purpose=cge-az-capstone-seed >/dev/null \
  && ok "$VNET / $SUBNET (bound to $NSG)"

# --- 10-11. A free web app with transport security turned off ----------------
say "App Service"
az appservice plan create --name "$PLAN" --resource-group "$RG_PROD" --location "$APP_LOCATION" \
  --sku F1 --is-linux --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
  && ok "$PLAN (F1, free)"
az webapp create --name "$APP" --resource-group "$RG_PROD" --plan "$PLAN" \
  --runtime "PYTHON|3.12" --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null \
  && ok "$APP"
# MISCONFIG x3: HTTP allowed, plain FTP allowed, TLS 1.0 floor.
az webapp update --name "$APP" --resource-group "$RG_PROD" --https-only false >/dev/null \
  && az webapp config set --name "$APP" --resource-group "$RG_PROD" \
       --ftps-state AllAllowed --min-tls-version 1.0 >/dev/null \
  && ok "$APP: HTTPS-only off, FTP allowed, TLS 1.0 — deliberate"

# --- 12. An over-privileged workload identity --------------------------------
say "Workload identity"
az identity create --name "$UAMI" --resource-group "$RG_PROD" --location "$LOCATION" \
  --tags env=prod owner="$OWNER" purpose=cge-az-capstone-seed >/dev/null && ok "$UAMI"
PID="$(az identity show --name "$UAMI" --resource-group "$RG_PROD" --query principalId -o tsv)"
RG_PROD_ID="$(az group show --name "$RG_PROD" --query id -o tsv)"
# MISCONFIG: Contributor on the whole resource group for a batch job that needs one
# container. Your own gate rule (policy/broad_roles.rego) refuses this in Terraform;
# here it was done in the portal, as these things are. New identities can take a
# minute to be assignable, hence the retry.
if az role assignment list --assignee "$PID" --scope "$RG_PROD_ID" --role Contributor \
     --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
  ok "$UAMI already Contributor on $RG_PROD — deliberate"
else
  for attempt in 1 2 3 4 5 6; do
    if az role assignment create --assignee-object-id "$PID" \
         --assignee-principal-type ServicePrincipal --role Contributor \
         --scope "$RG_PROD_ID" >/dev/null 2>&1; then
      ok "$UAMI granted Contributor on $RG_PROD — deliberate"
      break
    fi
    if [ "$attempt" -eq 6 ]; then
      warn "role assignment did not land; re-run the script in a minute"
    else
      sleep 10
    fi
  done
fi

# ---------------------------------------------------------------------------
say "Estate seeded. What to expect"
cat <<EOF
  Defender for Cloud needs an assessment cycle to see new resources (hours on a fresh
  subscription, see VALIDATION-LOG F6). Policy compliance evaluates within ~15 min,
  or on demand:

    az policy state trigger-scan --no-wait

  Deliberate findings you should be able to point at by resource ID:
    $RG_LEGACY      missing env tag
    $ST_PUBLIC   public blob (unless policy refused it), HTTP allowed, shared keys
    $ST_LOGS   untagged, no diagnostics (deployIfNotExists should fix this one)
    $KV     purge protection off, public network, no RBAC
    $NSG    22 + 3389 inbound from Internet
    $APP   HTTPS-only off, FTP allowed, TLS 1.0
    $UAMI      Contributor at resource-group scope

  Discover it the way your pipeline should — by tag, not by name:

    az resource list --tag purpose=cge-az-capstone-seed -o table

  Tear it all down when the score is back:  ./seed-estate.sh --teardown
EOF
