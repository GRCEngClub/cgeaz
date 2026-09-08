# Lab 2 — Turn It All On

**Video:** 02_05 · **Time:** ~30 min · **Cost:** starts the Defender for Storage 30-day trial
**Prereq:** Lab 1.

## Deliverables

1. Defender for Storage enabled (inside its 30-day trial)
2. NIST CSF v2.0 standard assigned to the subscription
3. Log Analytics workspace receiving the subscription Activity Log
4. A seed storage account for Defender to assess
5. Your first pull from the assessments API — the pipeline's raw material

## Steps

### 1. The Defender plan (starts the trial clock)

Foundational CSPM is already on and free. Enable exactly one paid plan:

```bash
az security pricing create --name StorageAccounts --tier Standard
```

Verify in portal → Defender for Cloud → Environment settings: trial active, days
remaining shown. Enabling plans across an estate is stage two's job — this is rep one,
done by hand so you know what the pipeline automates.

### 2. The compliance standard

The regulatory compliance dashboard is powered by a built-in policy initiative.
Assign **NIST CSF v2.0** (built-in initiative `184a0e05-7b06-4a68-bbbe-13b8353bc613`):

```bash
az policy assignment create --name nist-csf-20 --display-name "NIST CSF v2.0" \
  --policy-set-definition 184a0e05-7b06-4a68-bbbe-13b8353bc613 \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

It appears under Defender → Regulatory compliance as it populates (give it time).

### 3. The workspace and Activity Log routing

```bash
az monitor log-analytics workspace create --workspace-name law-grc-sandbox \
  --resource-group rg-grc-sandbox-dev --location eastus
./route-activity-log.sh
```

(The script uses `az rest` — the plain CLI command has a parsing bug at subscription
scope; see SETUP.md potholes.)

**Timing fact:** routing only captures events **after** it exists, and ingestion lags
~5–10 minutes. So make a fresh change (re-run the budget script, add a tag), wait a few
minutes, then prove your audit trail in the workspace's query editor:

```kusto
AzureActivity
| summarize n=count() by OperationNameValue
| order by n desc
```

Your own actions, logged, routed, queryable. That loop — act, record, route, query,
prove — is the fundamental motion of the whole pipeline.

### 4. Seed resource + first API pull

Defender needs something to assess:

```bash
az storage account create --name stgrcseed$RANDOM --resource-group rg-grc-sandbox-dev \
  --location eastus --sku Standard_LRS --tags env=dev purpose=cge-az-labs
```

Then pull assessments the way the collector Function will:

```bash
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Security/assessments?api-version=2021-06-01"
```

> **On a brand-new subscription this returns `[]` for the first several hours (up to
> ~24h)** — Defender's first assessment cycle hasn't run yet. That's expected, it's
> validated behavior, and it's why this pull is repeated at the start of Lab 4. When it
> populates, each object is a control test: rule, resource, verdict, timestamp.

## Verify

- [ ] Defender for Storage: Standard, trial clock visible
- [ ] CSF v2.0 in the regulatory compliance blade (populating)
- [ ] `AzureActivity` query returns your own operations
- [ ] Assessments API call succeeds (data now or within a day)

## Teardown

Leave everything running — Labs 3–6 build on it. The only paid meter is the Storage
plan trial; `az security pricing create --name StorageAccounts --tier Free` turns it
off any time.
