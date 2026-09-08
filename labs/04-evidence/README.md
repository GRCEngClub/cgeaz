# Lab 4 — Evidence Flowing End to End

**Video:** 04_04 · **Time:** ~60 min · **Cost:** pennies (Cosmos serverless + consumption Functions)
**Prereq:** Lab 3. **Also:** run `../00-setup/probe-quota.sh` first — see below.

## Before you start: two validated gotchas

1. **Consumption quota is regional.** Free accounts have ZERO Y1 quota in most US
   regions (`centralus` and `westus3` worked in validation). Run the probe, then set
   `functions_location` if your region differs from the `centralus` default.
2. **Assessments must exist.** Re-run the Lab 2 API pull now. If it's still `[]`,
   Defender's first cycle hasn't finished — do the infrastructure half of this lab,
   then come back for the collection run later. The collector handles an empty API
   gracefully (validated: "0 documents" is a clean run, not an error).

## Steps

### 1. Deploy the evidence store

```bash
cd ../../stages/03-evidence-store
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=<from backend.hcl>
terraform plan   # count the custody chain: Cosmos + 3 containers, WORM container,
                 # keyless storage, collector app, two scoped role grants
terraform apply  # Cosmos takes a few minutes — read the collector code while you wait
```

### 2. Deploy the collector code

```bash
cd ../../functions/collect_assessments
zip -r /tmp/collector.zip .
az functionapp deployment source config-zip \
  --name $(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app) \
  --resource-group rg-grc-evidence-dev --src /tmp/collector.zip --build-remote true --timeout 600
```

Remote build installs the Python dependencies. Wait until
`az functionapp function list` shows `collect_nightly` and `collect_now` (~1–2 min after deploy).

### 3. Seed the frameworks container

```bash
cd ../../labs/04-evidence
pip install azure-cosmos azure-identity
COSMOS_ENDPOINT=$(cd ../../stages/03-evidence-store && terraform output -raw cosmos_endpoint) \
  python3 seed_frameworks.py
```

This also proves the Cosmos data-plane write path with YOUR identity (the stage granted it).

### 4. Trigger a collection run

```bash
APP=$(cd ../../stages/03-evidence-store && terraform output -raw collector_function_app)
KEY=$(az functionapp function keys list --name $APP --resource-group rg-grc-evidence-dev \
      --function-name collect_now --query default -o tsv)
curl "https://$APP.azurewebsites.net/api/collect?code=$KEY"
```

### 5. The trace (the point of everything)

Pick one unhealthy assessment in the Defender portal, note its assessment ID, then find
the same finding in Cosmos Data Explorer — same ID, same status, plus `collectedAt`,
`runId`, and the full resource path. Portal: a live view. Your store: owned history.

### 6. Prove WORM

```bash
STG=$(cd ../../stages/03-evidence-store && terraform output -raw evidence_storage_account)
echo test > /tmp/worm.txt
az storage blob upload --account-name $STG --container-name reports \
  --name worm-test.txt --file /tmp/worm.txt --auth-mode login
az storage blob delete --account-name $STG --container-name reports \
  --name worm-test.txt --auth-mode login
```

The delete fails with **`BlobImmutableDueToPolicy`** — that error IS the test passing.
Not permissions: policy, applying to every identity including Owner.

## Verify

- [ ] Collector ran (check the run summary output; 0 documents is valid if Defender hasn't cycled)
- [ ] `frameworks` container holds 7 CSF 2.0 documents
- [ ] WORM delete blocked
- [ ] Nightly timer live (05:00 UTC) — evidence now accumulates without you
