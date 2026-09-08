#!/usr/bin/env bash
# Free-account consumption-plan quota is REGIONAL and zero in most US regions.
# Discovery before action applies to quotas too: this probe finds the regions where
# your subscription can actually host the pipeline's Function tier, before Lab 4.
set -uo pipefail

SUB_ID=$(az account show --query id -o tsv)
RG="rg-grc-quota-probe"
REGIONS=("${@:-centralus westus3 eastus2 eastus westus2 southcentralus northcentralus}")
[ $# -eq 0 ] && REGIONS=(centralus westus3 eastus2 eastus westus2 southcentralus northcentralus)

az group create --name "$RG" --location eastus2 --output none

echo "Probing consumption (Y1) quota per region:"
for region in "${REGIONS[@]}"; do
  body="{\"location\":\"$region\",\"kind\":\"functionapp\",\"sku\":{\"name\":\"Y1\",\"tier\":\"Dynamic\"},\"properties\":{\"reserved\":true}}"
  url="https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG/providers/Microsoft.Web/serverfarms/probe-$region?api-version=2023-12-01"
  out=$(az rest --method PUT --url "$url" --body "$body" 2>&1)
  if echo "$out" | grep -q '"provisioningState": "Succeeded"'; then
    echo "  $region: OK  <-- usable for functions_location"
    az rest --method DELETE --url "$url" --output none 2>/dev/null
  else
    limit=$(echo "$out" | grep -oE 'Current Limit \([^)]*\): [0-9]+' | head -1)
    echo "  $region: no quota (${limit:-unknown error})"
  fi
done

az group delete --name "$RG" --yes --no-wait --output none
echo
echo "Set functions_location in stages/03 and stages/04 to a region marked OK."
