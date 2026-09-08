# Lab 5 — Generate Your First ATO Deliverables

**Video:** 05_02 · **Time:** ~45 min · **Cost:** pennies
**Prereq:** Lab 4 (with at least one collection run that wrote documents — the reports
are only interesting once Defender has cycled and the collector has swept).

## Steps

### 1. Deploy the reporting stage

```bash
cd ../../stages/04-reporting
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=<from backend.hcl>
terraform plan   # read the reporter identity's whitelist: Cosmos READ + Blob WRITE.
                 # No Security Reader, no Cosmos write — SoD enforced by scopes.
terraform apply
```

### 2. Deploy the report generators

```bash
cd ../../functions/reports
zip -r /tmp/reports.zip .
az functionapp deployment source config-zip \
  --name $(cd ../../stages/04-reporting && terraform output -raw reporting_function_app) \
  --resource-group rg-grc-evidence-dev --src /tmp/reports.zip --build-remote true --timeout 600
```

### 3. Generate the POA&M and the SAR

```bash
APP=$(cd ../../stages/04-reporting && terraform output -raw reporting_function_app)
K1=$(az functionapp function keys list --name $APP -g rg-grc-evidence-dev --function-name poam_now --query default -o tsv)
K2=$(az functionapp function keys list --name $APP -g rg-grc-evidence-dev --function-name sar_now --query default -o tsv)
curl "https://$APP.azurewebsites.net/api/poam?code=$K1"
curl "https://$APP.azurewebsites.net/api/sar?code=$K2"
```

Both land in the WORM `reports` container on dated paths — xlsx + json for the POA&M
(humans + machines, always both), markdown for the SAR.

### 4. The trace — the test an assessor would run

Pick a number in your SAR (say, total findings). Reproduce it from the store:

- Data Explorer → `SELECT VALUE COUNT(1) FROM c WHERE c.runId = "<runId from the SAR header>" AND c.status = "Unhealthy"`
- Same number. Pick one finding's assessment ID from the SAR → query the document →
  timestamps, resource path, run lineage.

Number → query → immutable document, in under a minute. Every number is a fact with a receipt.

## Verify

- [ ] Both artifacts on dated paths in the WORM container (try the delete again if you
      want to enjoy the error)
- [ ] The trace reproduces a SAR number from Cosmos
- [ ] Timers live: POA&M daily 06:00 UTC, SAR weekly Monday 07:00 UTC

**Stage 5 (AI narrative) is walkthrough-only** — video 05_03 demos it; the capstone
does not require it and never penalizes its absence.
