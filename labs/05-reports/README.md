# Lab 5 — Generate Your First ATO Deliverables

| | |
|---|---|
| **Video** | 05_02 |
| **Hands-on time** | ~45 min |
| **Cost** | Pennies. One more consumption Function App and its LRS runtime storage account; reports are kilobytes in the existing WORM container. Guardrail: the Lab 1 budget. |
| **Prerequisites** | Lab 4, ideally with at least one collection run that wrote documents. The reports are only *interesting* once Defender has cycled and the collector has swept, but empty-store runs are validated clean, so you can deploy this lab's infrastructure any time. |
| **Where you'll work** | `cgeaz/stages/04-reporting`, then `cgeaz/functions/reports`. |

## Steps

### 1. Deploy the reporting stage

**where:** `cgeaz/labs/05-reports`, then the `cd` takes you to `cgeaz/stages/04-reporting`

```bash
cd ../../stages/04-reporting
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=stgrctfstateXXXXXXXX   # your value from backend.hcl
terraform plan   # read the reporter identity's whitelist: Cosmos READ + Blob WRITE.
                 # No Security Reader, no Cosmos write — SoD enforced by scopes.
terraform apply
```

**Success signal:** `Apply complete!` and `terraform output -raw reporting_function_app`
returns the app name.

> **Same regional quota rule as Lab 4:** this stage also defaults
> `functions_location = "centralus"`. If your Lab 4 probe forced a different region,
> set `TF_VAR_functions_location` to the same one here.

### 2. Deploy the report generators

**where:** `cgeaz/functions/reports`

```bash
cd ../../functions/reports
zip -r /tmp/reports.zip .
az functionapp deployment source config-zip \
  --name $(cd ../../stages/04-reporting && terraform output -raw reporting_function_app) \
  --resource-group rg-grc-evidence-dev --src /tmp/reports.zip --build-remote true --timeout 600
```

Remote build again, so expect the command to hold the terminal while dependencies
install. **Success signal:** deployment reports success, and after the same ~1–2 minute
lag as Lab 4, `az functionapp function list` on this app shows `poam_now`, `sar_now`,
and the two timer functions.

> **Windows / Git Bash:** no `zip` in Git Bash; use 7-Zip (`7z a /tmp/reports.zip .`)
> or WSL, and keep `host.json` at the archive root (see Lab 4 step 2).

### 3. Generate the POA&M and the SAR

**where:** `cgeaz/functions/reports` (any directory works; the `cd` subshells fetch outputs)

```bash
APP=$(cd ../../stages/04-reporting && terraform output -raw reporting_function_app)
K1=$(az functionapp function keys list --name $APP -g rg-grc-evidence-dev --function-name poam_now --query default -o tsv)
K2=$(az functionapp function keys list --name $APP -g rg-grc-evidence-dev --function-name sar_now --query default -o tsv)
curl "https://$APP.azurewebsites.net/api/poam?code=$K1"
curl "https://$APP.azurewebsites.net/api/sar?code=$K2"
```

**Expected output:** one JSON line each, shaped like (your counts, run ID, and dates differ):

```
{"items": <N>, "runId": "<uuid>", "xlsx": "poam/<YYYY>/<MM>/poam-<YYYY-MM-DD>.xlsx", "json": "poam/<YYYY>/<MM>/poam-<YYYY-MM-DD>.json"}
{"findings": <N>, "runId": "<uuid>", "path": "sar/<YYYY>/<MM>/sar-<YYYY-MM-DD>.md"}
```

Both land in the WORM `reports` container on dated paths — xlsx + json for the POA&M
(humans + machines, always both), markdown for the SAR.

> **If the counts are 0 and `runId` is null:** the store is empty because Defender
> hasn't cycled or the collector hasn't run. Validated: empty-store runs are clean,
> not errors. Generate real reports after Lab 4 step 4 produces a non-zero run.

> **If a second run the same day errors on upload:** the generators write with
> `overwrite=False` and the blob path is dated per day, so a same-day re-run finds
> the first artifact already there (and WORM would forbid replacing it anyway).
> That's the store doing its job; tomorrow's path is new.

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

## Teardown

None mid-course; Lab 6 regenerates the POA&M to prove the loop closed. Course-end:
`terraform destroy` here happens second in the reverse order (06 → **04** → 03 → 01).

**Stage 5 (AI narrative) is walkthrough-only** — video 05_03 demos it; the capstone
does not require it and never penalizes its absence.
