#!/usr/bin/env bash
# Route the subscription Activity Log to the GRC workspace.
# az monitor diagnostic-settings create throws KeyError: 'resource_group' at
# subscription scope (validated on CLI 2.90), so this uses the API directly.
set -euo pipefail

SUB_ID=$(az account show --query id -o tsv)
WSID=$(az monitor log-analytics workspace show -g rg-grc-sandbox-dev -n law-grc-sandbox --query id -o tsv)

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Insights/diagnosticSettings/ds-activity-to-law?api-version=2021-05-01-preview" \
  --body "{
    \"properties\": {
      \"workspaceId\": \"$WSID\",
      \"logs\": [
        {\"category\": \"Administrative\", \"enabled\": true},
        {\"category\": \"Security\", \"enabled\": true},
        {\"category\": \"Policy\", \"enabled\": true},
        {\"category\": \"Alert\", \"enabled\": true}
      ]
    }
  }" --query name -o tsv
echo "Activity Log now routes to law-grc-sandbox. Ingestion lag: ~5-10 minutes."
