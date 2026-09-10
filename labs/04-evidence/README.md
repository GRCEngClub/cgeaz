# Lab 4 — Evidence Flowing End to End

| | |
|---|---|
| **Video** | 04_04 |
| **Hands-on time** | ~60 min (Cosmos provisioning and the zip deploy add unattended waits of a few minutes each) |
| **Cost** | Pennies. Cosmos DB serverless and consumption (Y1) Functions bill per use; at lab volume both round to cents. The 90-day WORM container holds kilobytes. Guardrails: the Lab 1 budget alerts, and serverless/consumption SKUs have no idle charge. |
| **Prerequisites** | Lab 3. Python 3.11+ with `pip`. **Also:** run the quota probe first — see below. |
| **Where you'll work** | Four directories, in order: `cgeaz/labs/00-setup`, `cgeaz/stages/03-evidence-store`, `cgeaz/functions/collect_assessments`, `cgeaz/labs/04-evidence`. Each step says which. |

## Before you start: two validated gotchas

1. **Consumption quota is regional, and free accounts have ZERO Y1 quota in most US
   regions.** Probe your subscription before deploying anything:

   **where:** `cgeaz/labs/00-setup`

   ```bash
   ./probe-quota.sh
   ```

   **Expected output** (your regions may differ; this is the validated free-account result):

   ```
   Probing consumption (Y1) quota per region:
     centralus: OK  <-- usable for functions_location
     westus3: OK  <-- usable for functions_location
     eastus2: no quota (Current Limit (Y1 VMs): 0)
     eastus: no quota (Current Limit (Y1 VMs): 0)
   ```

   Stage 03 defaults `functions_location` to `centralus`. If your probe marks
   `centralus` as no-quota, set `TF_VAR_functions_location` to a region marked OK
   before the apply in step 1 (and again for stage 04 in Lab 5).

2. **Assessments must exist for the collection run to be interesting.** Re-run the
   Lab 2 API pull now. If it's still empty, Defender's first cycle hasn't finished —
   do the infrastructure half of this lab (steps 1–3), then come back for the
   collection run later. The collector handles an empty API gracefully (validated:
   "0 documents" is a clean run, not an error).

## Steps

### 1. Deploy the evidence store

**where:** `cgeaz/labs/04-evidence`, then the `cd` takes you to `cgeaz/stages/03-evidence-store`

```bash
cd ../../stages/03-evidence-store
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=stgrctfstateXXXXXXXX   # your value from backend.hcl
terraform plan   # count the custody chain: Cosmos + 3 containers, WORM container,
                 # keyless storage, collector app, two scoped role grants
terraform apply  # Cosmos takes a few minutes — read the collector code while you wait
```

**Success signal:** `Apply complete!` and `terraform output` lists `cosmos_endpoint`,
`evidence_storage_account`, and `collector_function_app`. Cosmos alone taking several
minutes is normal; that's the longest single wait in the lab.

> **If Cosmos fails in your region, it's capacity, not you.** On validation day
> `eastus` could not host the evidence plane at all. Cosmos returned:
>
> ```
> ServiceUnavailable ... high demand in East US region ... cannot fulfill your request
> ```
>
> That's why the store defaults to `eastus2`. If your region fails the same way, set
> `TF_VAR_location` to another region and re-apply. One more trap from that failure:
> the account showed `Succeeded` in `az resource list` while actually `Failed` —
> check `provisioningState` **on the resource itself**, not the deployment list.

### 2. Deploy the collector code

**where:** `cgeaz/functions/collect_assessments`

```bash
cd ../../functions/collect_assessments
zip -r /tmp/collector.zip .
az functionapp deployment source config-zip \
  --name $(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app) \
  --resource-group rg-grc-evidence-dev --src /tmp/collector.zip --build-remote true --timeout 600
```

Remote build installs the Python dependencies, so the deploy command holding the
terminal for a while is the build working, not hanging. **Success signal:** the
command returns with deployment status successful, and within ~1–2 minutes

```bash
az functionapp function list \
  --name $(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app) \
  --resource-group rg-grc-evidence-dev --query "[].name" -o tsv
```

shows both `collect_nightly` and `collect_now`. If the list is empty right after the
deploy, that's the ~1–2 minute indexing lag; re-run the list command before touching
anything else.

> **Windows / Git Bash:** Git Bash does not ship a `zip` command. Options: install
> 7-Zip and use `7z a /tmp/collector.zip .`, or run this step from WSL. Whatever you
> use, zip the *contents* of the function directory (host.json at the archive root),
> not the directory itself.

### 3. Seed the frameworks container

**where:** `cgeaz/labs/04-evidence`

```bash
cd ../../labs/04-evidence
pip install azure-cosmos azure-identity
COSMOS_ENDPOINT=$(cd ../../stages/03-evidence-store && terraform output -raw cosmos_endpoint) \
  python3 seed_frameworks.py
```

**Expected output:**

```
seeded 7 framework documents into https://cosmos-grc-evidence-XXXXXX.documents.azure.com:443/
```

This also proves the Cosmos data-plane write path with YOUR identity (the stage
granted it). If it fails with an auth error, the stage's Cosmos role grant may still
be propagating; like the Lab 3 state-storage 403, waiting a couple of minutes and
retrying beats changing anything.

### 4. Trigger a collection run

**where:** `cgeaz/labs/04-evidence`

```bash
APP=$(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app)
KEY=$(az functionapp function keys list --name $APP --resource-group rg-grc-evidence-dev \
      --function-name collect_now --query default -o tsv)
curl "https://$APP.azurewebsites.net/api/collect?code=$KEY"
```

**Expected output** (one line; your run ID, count, and timestamp differ):

```
run <uuid>: <N> documents at <ISO timestamp>
```

> **`0 documents` is a valid, clean run** if Defender still hasn't finished its first
> assessment cycle (up to ~24h on a brand-new subscription; see Lab 2). Nothing is
> broken. Come back tomorrow, hit the same URL, and the count goes positive. The
> nightly timer (05:00 UTC) will also do it for you.

### 5. The trace (the point of everything)

Pick one unhealthy assessment in the Defender portal, note its assessment ID, then find
the same finding in Cosmos Data Explorer (portal → your Cosmos account → Data Explorer
→ `grc` → `assessments`) — same ID, same status, plus `collectedAt`, `runId`, and the
full resource path. Portal: a live view. Your store: owned history.

### 6. Prove WORM

**where:** `cgeaz/labs/04-evidence`

```bash
STG=$(cd ../../stages/03-evidence-store && terraform output -raw evidence_storage_account)
echo test > /tmp/worm.txt
az storage blob upload --account-name $STG --container-name reports \
  --name worm-test.txt --file /tmp/worm.txt --auth-mode login
az storage blob delete --account-name $STG --container-name reports \
  --name worm-test.txt --auth-mode login
```

**Expected output:** the upload succeeds; the delete FAILS with

```
BlobImmutableDueToPolicy
```

**That error IS the test passing.** Not permissions: policy, applying to every
identity including Owner. If the delete succeeds, the immutability policy didn't
deploy; check `terraform plan` for drift before anything else.

## Verify

- [ ] Collector ran (run summary line returned; 0 documents is valid if Defender hasn't cycled)
- [ ] `frameworks` container holds 7 CSF 2.0 documents
- [ ] WORM delete blocked with `BlobImmutableDueToPolicy`
- [ ] Nightly timer live (05:00 UTC) — evidence now accumulates without you

## Teardown

Nothing to tear down mid-course; Labs 5–6 read this store. Course-end teardown is
`terraform destroy` per stage in reverse order (06 → 04 → 03 → 01). The WORM
immutability policy ships **unlocked** precisely so that destroy works.
