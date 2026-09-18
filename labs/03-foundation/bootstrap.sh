#!/usr/bin/env bash
# Bootstrap the Terraform remote-state storage for the CGE-AZ pipeline.
# Run once, before your first `terraform init` in stages/01-foundation.
# Chicken-and-egg: state storage can't manage itself, so this one piece is a script.
set -euo pipefail

LOCATION="${LOCATION:-eastus}"
RG_STATE="rg-grc-tfstate"
# Storage account names are globally unique, lowercase, <=24 chars.
# We derive a stable suffix from your subscription ID so re-runs are idempotent.
SUB_ID=$(az account show --query id -o tsv)
SUFFIX=$(echo "$SUB_ID" | tr -d '-' | cut -c1-8)
SA_NAME="stgrctfstate${SUFFIX}"
CONTAINER="tfstate"
# The POA&M resolves finding owners from the resource group's owner tag, so the state
# resource group needs one too. Defaults to whoever is signed in; override with OWNER_EMAIL.
OWNER="${OWNER_EMAIL:-$(az account show --query user.name -o tsv)}"

echo ">> State resource group: $RG_STATE (owner: $OWNER)"
az group create --name "$RG_STATE" --location "$LOCATION" \
  --tags env=shared purpose=terraform-state owner="$OWNER" --output none

echo ">> State storage account: $SA_NAME (versioned, no public blob access)"
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --tags env=shared purpose=terraform-state owner="$OWNER" \
  --output none

echo ">> Enabling blob versioning (every state change becomes a recoverable version)"
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 7 \
  --output none

# Terraform reads/writes state over the blob DATA plane (use_azuread_auth = true).
# Owner on the subscription is a CONTROL-plane role and does NOT include data actions,
# so grant yourself Storage Blob Data Contributor explicitly. (This is the control-plane
# vs data-plane split from lesson 01_02, biting in real life.)
echo ">> Granting you Storage Blob Data Contributor on the state resource group"
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --assignee-object-id "$ME" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG_STATE" \
  --output none 2>/dev/null || echo "   (already granted)"
echo "   Note: a fresh role grant can take 1-2 minutes to propagate before terraform init works."

# Shared keys are off, so even creating the container needs the data-plane role granted above.
echo ">> State container: $CONTAINER (retries while the role grant propagates)"
for attempt in 1 2 3 4 5 6; do
  az storage container create --name "$CONTAINER" --account-name "$SA_NAME" --auth-mode login --output none 2>/dev/null && break
  [ "$attempt" -eq 6 ] && { echo "container create still failing: wait a minute and re-run this script" >&2; exit 1; }
  sleep 20
done

echo ">> Locking the state account against deletion"
az lock create --name lock-tfstate-no-delete --lock-type CanNotDelete \
  --resource-group "$RG_STATE" --resource-name "$SA_NAME" --resource-type Microsoft.Storage/storageAccounts \
  --notes "Terraform state must not be deleted by accident" --output none

BACKEND_FILE="$(dirname "$0")/backend.hcl"
cat > "$BACKEND_FILE" <<EOF
resource_group_name  = "$RG_STATE"
storage_account_name = "$SA_NAME"
container_name       = "$CONTAINER"
EOF

cat <<EOF

Bootstrap complete. Backend config written to: $BACKEND_FILE

Next, from any stage directory (e.g. stages/01-foundation):

  export ARM_SUBSCRIPTION_ID=$SUB_ID
  terraform init -backend-config=../../labs/03-foundation/backend.hcl
EOF
