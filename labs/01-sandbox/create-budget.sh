#!/usr/bin/env bash
# az consumption budget create is broken against the current API (400: "use filter
# interface with 2019-05-01-preview"). This calls the budgets API directly instead.
set -euo pipefail

EMAIL="${1:?usage: ./create-budget.sh you@example.com}"
SUB_ID=$(az account show --query id -o tsv)
START=$(date +%Y-%m-01)T00:00:00Z
END=$(date -v+2y +%Y-%m-01 2>/dev/null || date -d "+2 years" +%Y-%m-01)T00:00:00Z

az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Consumption/budgets/budget-cge-az-labs?api-version=2023-11-01" \
  --body "{
    \"properties\": {
      \"category\": \"Cost\",
      \"amount\": 10,
      \"timeGrain\": \"Monthly\",
      \"timePeriod\": {\"startDate\": \"$START\", \"endDate\": \"$END\"},
      \"notifications\": {
        \"actual80\": {\"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": 80, \"thresholdType\": \"Actual\", \"contactEmails\": [\"$EMAIL\"]},
        \"forecast100\": {\"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": 100, \"thresholdType\": \"Forecasted\", \"contactEmails\": [\"$EMAIL\"]}
      }
    }
  }" --query name -o tsv
echo "budget-cge-az-labs created: \$10/month, alerts at 80% actual and 100% forecast."
