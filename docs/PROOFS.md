# Proofs

Commands anyone with read access can run to check a claim. Nothing here changes Azure or the repository.
Resource names below are this build's; substitute yours.

```bash
export SUB=$(az account show --query id -o tsv)
export RG=rg-grc-evidence-dev
export EVIDENCE_ACCOUNT=stgrcevidqst3u6
export COSMOS=https://cosmos-grc-evidence-qst3u6.documents.azure.com:443/
```

## 1. The timers have run on schedule
Azure Monitor counts every execution of a Function App per hour. Expect one collector execution in every hour.

```bash
az monitor metrics list \
  --resource "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/func-grc-collectors-qst3u6" \
  --metric FunctionExecutionCount --interval PT1H --aggregation Total --offset 24h \
  --query "value[0].timeseries[0].data[].{hourUTC:timeStamp, executions:total}" -o table
```

The run ledger says the same thing from inside the store, and records whether each run was a timer or a manual call:

```bash
python3 - <<'PY'
import os
from azure.cosmos import CosmosClient
from azure.identity import AzureCliCredential
db = CosmosClient(os.environ["COSMOS"], AzureCliCredential()).get_database_client("grc")
for r in db.get_container_client("runs").query_items(
        "SELECT c.collectedAt, c.trigger, c.documents, c.unhealthy FROM c ORDER BY c.collectedAt DESC OFFSET 0 LIMIT 24",
        enable_cross_partition_query=True):
    print(r)
PY
```

Scheduled GitHub Actions runs:

```bash
gh run list --event schedule --limit 30 --json workflowName,createdAt,conclusion \
  --jq '.[] | "\(.workflowName)  \(.createdAt)  \(.conclusion)"'
```

## 2. Every report number traces to stored documents
A report names the run it was cut from. The store still holds that run, so the counts reproduce:

```bash
az storage blob list --account-name "$EVIDENCE_ACCOUNT" --container-name reports --auth-mode login \
  --query "[?ends_with(name,'.json')].name" -o tsv | tail -3
```

Download one, then compare its counts with a query for the same `runId`:

```bash
REPORT=poam/2026/09/poam-2026-09-18T2300Z.json
az storage blob download --account-name "$EVIDENCE_ACCOUNT" --container-name reports \
  --name "$REPORT" --auth-mode login --file report.json --no-progress -o none
RUN=$(python3 -c "import json;print(json.load(open('report.json'))['runId'])")
python3 -c "import json;print('items in report:', len(json.load(open('report.json'))['items']))"
RUN=$RUN python3 - <<'PY'
import os
from azure.cosmos import CosmosClient
from azure.identity import AzureCliCredential
c = CosmosClient(os.environ["COSMOS"], AzureCliCredential()).get_database_client("grc").get_container_client("assessments")
q = "SELECT VALUE COUNT(1) FROM c WHERE c.runId = @r AND c.status = 'Unhealthy'"
print("unhealthy documents for that run:", list(c.query_items(q, parameters=[{"name": "@r", "value": os.environ["RUN"]}], enable_cross_partition_query=True))[0])
PY
```

The two numbers must be equal. Report generators never reach a live API; a unit test enforces it:

```bash
grep -nE "management.azure.com|Microsoft.Security" functions/reports/function_app.py || echo "no live API in the report generators"
```

## 3. Reports cannot be edited or deleted
A delete against the WORM container fails for every identity:

```bash
az storage blob delete --account-name "$EVIDENCE_ACCOUNT" --container-name reports \
  --name "$REPORT" --auth-mode login 2>&1 | grep -o "BlobImmutableDueToPolicy" | head -1
```

## 4. The gate rules fire
```bash
policy/test-examples.sh
```

## 5. Static checks
```bash
.venv/bin/checkov --config-file .checkov.yaml
.venv/bin/pytest tests -q
```

## 6. Terraform state is keyless and protected
```bash
az storage account show --name stgrctfstatec0a353d0 --resource-group rg-grc-tfstate \
  --query "{sharedKey:allowSharedKeyAccess, publicBlob:allowBlobPublicAccess, tls:minimumTlsVersion}" -o json
az lock list --resource-group rg-grc-tfstate --query "[].{name:name, level:level}" -o table
```
