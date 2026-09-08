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

echo ">> State resource group: $RG_STATE"
az group create --name "$RG_STATE" --location "$LOCATION" \
  --tags env=shared purpose=terraform-state --output none

echo ">> State storage account: $SA_NAME (versioned, no public blob access)"
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --tags env=shared purpose=terraform-state \
  --output none

echo ">> Enabling blob versioning (every state change becomes a recoverable version)"
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --enable-versioning true \
  --output none

echo ">> State container: $CONTAINER"
az storage container create \
  --name "$CONTAINER" \
  --account-name "$SA_NAME" \
  --auth-mode login \
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
