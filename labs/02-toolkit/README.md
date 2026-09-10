# Lab 2 — Turn It All On

| | |
|---|---|
| **Video** | 02_05 |
| **Hands-on time** | ~30 min (Defender's first assessment cycle then runs on its own, up to ~24h) |
| **Cost** | Starts the Defender for Storage **30-day trial** ($0 during the trial). The Log Analytics workspace is PerGB2018: pennies at lab ingestion volume. Guardrails: your Lab 1 budget alerts, and `az security pricing create --name StorageAccounts --tier Free` turns the plan off any time. |
| **Prerequisites** | Lab 1. |
| **Where you'll work** | `cgeaz/labs/02-toolkit` (the routing script lives here). |

## Deliverables

1. Defender for Storage enabled (inside its 30-day trial)
2. NIST CSF v2.0 standard assigned to the subscription
3. Log Analytics workspace receiving the subscription Activity Log
4. A seed storage account for Defender to assess
5. Your first pull from the assessments API — the pipeline's raw material

> **On a corporate tenant?** This lab assumes your own free tenant. On an employer
> subscription, Defender plans are often already enabled at Standard (enabling "your"
> trial does nothing, and disabling plans is a production change you must not make),
> and policy assignment rights may be restricted. Everything in this lab targets
> subscription scope, so a personal sandbox subscription an admin gives you works;
> otherwise use your own free account.

## Steps

### 1. The Defender plan (starts the trial clock)

Foundational CSPM is already on and free. Enable exactly one paid plan:

**where:** `cgeaz/labs/02-toolkit`

```bash
az security pricing create --name StorageAccounts --tier Standard
```

**Success signal:** the returned JSON shows `"pricingTier": "Standard"`. In the
validated run, portal → Defender for Cloud → Environment settings showed the trial
active with 30 days remaining. That number is your clock; note the date.

Enabling plans across an estate is stage two's job — this is rep one, done by hand so
you know what the pipeline automates.

### 2. The compliance standard

The regulatory compliance dashboard is powered by a built-in policy initiative.
Assign **NIST CSF v2.0** (built-in initiative `184a0e05-7b06-4a68-bbbe-13b8353bc613`):

**where:** `cgeaz/labs/02-toolkit`

```bash
az policy assignment create --name nist-csf-20 --display-name "NIST CSF v2.0" \
  --policy-set-definition 184a0e05-7b06-4a68-bbbe-13b8353bc613 \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

**Success signal:** JSON comes back with `"name": "nist-csf-20"`. This worked first
try in validation. It appears under Defender → Regulatory compliance **as it
populates**: the blade can take hours to show data on a new subscription. Assignment
succeeding now is the deliverable; the dashboard filling in is a background process,
not a step you wait on.

> **Windows / Git Bash:** the `--scope` argument starts with `/` and Git Bash will
> rewrite it into a Windows path. Run `export MSYS_NO_PATHCONV=1` first (see Lab 1).

### 3. The workspace and Activity Log routing

**where:** `cgeaz/labs/02-toolkit`

```bash
az monitor log-analytics workspace create --workspace-name law-grc-sandbox \
  --resource-group rg-grc-sandbox-dev --location eastus
./route-activity-log.sh
```

**Expected output** (from the script):

```
ds-activity-to-law
Activity Log now routes to law-grc-sandbox. Ingestion lag: ~5-10 minutes.
```

Why a script? The plain CLI command is broken at subscription scope. Validated on
CLI 2.90, `az monitor diagnostic-settings create` against a bare subscription throws:

```
KeyError: 'resource_group'
```

If you see that error, you ran the raw CLI command instead of the script. The script
uses `az rest` against the diagnostic-settings API (`2021-05-01-preview`) directly.

**Timing fact (this bit us in validation):** routing only captures events **after**
it exists. Our Lab 1 role assignment never appeared in the workspace, because it
predates the diagnostic setting. And ingestion lags ~5–10 minutes even for new events.
So: make a fresh change (re-run the budget script, add a tag to the resource group),
wait a few minutes, then prove your audit trail in the workspace's query editor
(portal → Log Analytics workspace → Logs):

```kusto
AzureActivity
| summarize n=count() by OperationNameValue
| order by n desc
```

**Success signal:** rows appear, and the operations are the ones you just performed
(budget write, tag write). If the table is empty, it is almost certainly the two
delays above, not a broken setup. Make another change, wait 10 minutes, re-run the
query. Don't rebuild anything.

Your own actions, logged, routed, queryable. That loop — act, record, route, query,
prove — is the fundamental motion of the whole pipeline.

### 4. Seed resource + first API pull

Defender needs something to assess:

**where:** `cgeaz/labs/02-toolkit`

```bash
az storage account create --name stgrcseed$RANDOM --resource-group rg-grc-sandbox-dev \
  --location eastus --sku Standard_LRS --tags env=dev purpose=cge-az-labs
```

**Success signal:** JSON with `"provisioningState": "Succeeded"`. Note the generated
account name (`stgrcseed` plus a number). Labs 4 and 6 use this account; save the name.

Then pull assessments the way the collector Function will:

```bash
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Security/assessments?api-version=2021-06-01"
```

> **An empty result here is not an error.** On the validated brand-new subscription
> this returned an empty list for the first several hours (Defender documents up to
> ~24h for the first assessment cycle, and there must be resources to assess). The
> HTTP call succeeding with `[]`-worth of data IS the passing state for day one.
> That's exactly why this pull is repeated at the start of Lab 4, by which point the
> validated account had data. When it populates, each object is a control test:
> rule, resource, verdict, timestamp.

## Verify

- [ ] Defender for Storage: Standard, trial clock visible in Environment settings
- [ ] CSF v2.0 assignment exists (`az policy assignment show --name nist-csf-20 --scope "/subscriptions/$(az account show --query id -o tsv)"`); the compliance blade populates over hours
- [ ] `AzureActivity` query returns your own post-routing operations
- [ ] Seed storage account created and its name saved
- [ ] Assessments API call returns HTTP 200 (data now, or within a day)

## Teardown

Leave everything running — Labs 3–6 build on it. The only paid meter is the Storage
plan trial; `az security pricing create --name StorageAccounts --tier Free` turns it
off any time.
