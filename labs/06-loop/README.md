# Lab 6 — Close the Loop

| | |
|---|---|
| **Video** | 06_02 |
| **Hands-on time** | ~60 min at the keyboard, plus policy-evaluation waits you do NOT sit through (the compliance scan alone ran ~15 minutes in validation) |
| **Cost** | $0. Policies, remediation tasks, and GitHub Actions on a public fork are free; the sabotage target is the free-tier seed account from Lab 2. Guardrail: the Lab 1 budget, still watching. |
| **Prerequisites** | Lab 5. A GitHub account; your fork of this repo. |
| **Where you'll work** | `cgeaz/stages/06-enforcement`, `cgeaz/labs/06-loop`, `cgeaz/stages/01-foundation`, plus your fork's GitHub UI. Each step says which. |

You break your sandbox on purpose, and the system detects it, proposes the fix, waits
for your approval, executes as the remediation identity, and documents itself.

> **This lab is mostly waiting, by design.** Policy compliance scans and remediation
> are asynchronous platform machinery. Every wait below has its validated duration
> printed next to it. When a step says ~15 minutes, start the step, go do something
> else, come back. Re-running commands does not speed Azure up.

## A design note you should understand first

Your foundation's **deny** policy makes the obvious sabotage impossible — you literally
cannot flip a storage account public while deny is active (we tried; validated: deny
fires on updates too, not just creates). That's the guardrail doing its job. So this
lab also teaches the escalation ladder in reverse: you'll **de-escalate deny → audit
through a parameter change** (in production, that's a reviewed one-line PR —
automation acts, humans authorize), sabotage, remediate, then re-escalate.

## Steps

### 1. Deploy enforcement (dry-run mode)

**where:** `cgeaz/labs/06-loop`, then the `cd` takes you to `cgeaz/stages/06-enforcement`

```bash
cd ../../stages/06-enforcement
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=stgrctfstateXXXXXXXX   # your value from backend.hcl
terraform apply    # remediation_mode defaults to "dry-run"
```

**Success signal:** `Apply complete!`; `terraform output remediation_mode` says
`dry-run`. Read what dry-run means in `main.tf`: the modify policy deploys, but the
assignment is `DoNotEnforce` — compliance data accumulates, and **you** create the
remediation task. That task is the human approval gate.

### 2. Arm the CI gate — on YOUR fork, never upstream

**where:** `cgeaz/labs/06-loop`

Read the script's header before running it: it explains why the upstream repo is
deliberately unarmed (on a public repo, `pull_request` OIDC subjects match PRs from
any fork, and the PR can modify the workflow it runs — a trust boundary you should be
able to explain by the end of this course, because it's the same reasoning you'll
apply to every CI system you ever assess).

```bash
./arm-your-fork.sh your-github-username
```

**Expected output** (tail; your IDs differ):

```
Done. Add these five VARIABLES (not secrets — see header comment) in YOUR fork:
Settings -> Secrets and variables -> Actions -> Variables -> New repository variable

  AZURE_CLIENT_ID        <guid>
  AZURE_TENANT_ID        <guid>
  AZURE_SUBSCRIPTION_ID  <guid>
  STATE_STORAGE_ACCOUNT  stgrctfstateXXXXXXXX
  OWNER_EMAIL            <your email>
```

They're variables, not secrets, because OIDC stores no credential — the IDs grant
nothing without the federation match, and the federation names your fork alone.

> **On a corporate tenant?** This step assumes you can create app registrations and
> federated credentials (`az ad app create`), which employer tenants commonly block.
> Fallback: skip the arming, keep the workflows disabled, and run the gate locally
> with conftest (below). The trust-boundary lesson is in the script header either way.

Then, in your fork's GitHub UI:

1. Actions tab → enable the two workflows (`compliance-gate`, `drift-detection`).
2. Settings → Branches → protect `main`, requiring the `gate` check.
3. Test the gate: open a PR adding a public storage account to any stage — conftest
   fails, naming the rule and the resource. Close it unmerged.

**Local test (no fork arming needed):** from the repo root, with a plan JSON produced
the way Lab 3 taught (`terraform show -json tf.plan > plan.json`):

```bash
conftest test plan.json -p policy/
```

**Success signal:** on a clean foundation plan, all checks pass (validated with
conftest 0.6x: 4 of 4 passed). On a deliberately bad plan (public blob + shared
keys), the run fails and each failure names the rule and the resource address.

### 3. De-escalate, then sabotage

**where:** `cgeaz/stages/01-foundation`

```bash
cd ../../stages/01-foundation
terraform apply -var public_blob_policy_effect=Audit   # in prod: a reviewed PR
az storage account update --name stgrcseedNNNNN --resource-group rg-grc-sandbox-dev \
  --allow-blob-public-access true                       # the out-of-band change
```

Use your seed account's real name from Lab 2 (`az storage account list -g
rg-grc-sandbox-dev -o table` if you lost it). **Success signal:** the update
*succeeds*, which should feel wrong — that's the point. With deny standing (skip the
de-escalation and try, if you like) the same command dies with
`RequestDisallowedByPolicy`.

Two tripwires are now armed against you: the KQL drift query (your caller ID, in the
portal, making an administrative write) and the policy compliance scan.

### 4. Detect and remediate — with your approval

**where:** `cgeaz/stages/01-foundation` (any directory with az works)

```bash
az policy state trigger-scan --resource-group rg-grc-sandbox-dev
```

> **This is the long wait: ~10–20 minutes (validated run: ~15).** The command can
> hold the terminal for the duration; if you interrupt it, the scan keeps running
> server-side. Do not re-trigger. Poll instead:

```bash
az policy state list --resource-group rg-grc-sandbox-dev \
  --filter "policyDefinitionName eq 'cge-fix-public-blob'" \
  --query "[].{resource:resourceId, state:complianceState}" -o table
```

**Expected output** (when the scan lands; empty output means the scan hasn't finished,
keep polling):

```
Resource                                    State
------------------------------------------  ------------
.../storageAccounts/stgrcseedNNNNN          NonCompliant
```

When it shows NonCompliant, create the remediation task — this is you, the human at
the gate, approving the fix:

```bash
az policy remediation create --name fix-public-blob-$(date +%s) \
  --resource-group rg-grc-sandbox-dev \
  --policy-assignment $(az policy assignment list --disable-scope-strict-match \
      --query "[?name=='cge-fix-public-blob'].id" -o tsv)
```

> **Why the `$(az policy assignment list ...)` dance?** Validated caveat:
> `az policy remediation create` needs the assignment's **full resource ID** —
> management-group-scoped assignments aren't found by name from a subscription
> context. Passing just `cge-fix-public-blob` fails with a not-found; the subshell
> resolves the full ID for you.

Verify the fix and its author (validated: the task reported `Succeeded` with 1
resource remediated, 0 failed):

```bash
az policy remediation list --resource-group rg-grc-sandbox-dev \
  --query "[].{name:name, state:provisioningState}" -o table
az storage account show --name stgrcseedNNNNN -g rg-grc-sandbox-dev --query allowBlobPublicAccess
```

**Expected:** `false` — and in the Activity Log, the caller on that write is
`id-grc-remediation-dev`, not you. Fixed by the remediation identity, not a human
command. That caller field is the audit story of this whole domain.

> **Windows / Git Bash:** if you exported `MSYS_NO_PATHCONV=1` back in Lab 1, the
> resource-ID arguments here pass through untouched. If remediation-create complains
> about a malformed assignment ID, that's the variable missing from this shell.

### 5. Close the loop

Trigger the collector (Lab 4 step 4). The assessment flips healthy in Cosmos;
regenerate the POA&M (Lab 5 step 3) and the line item is gone. Nobody edited a
document — the documents noticed. Then re-escalate:

**where:** `cgeaz/stages/01-foundation`

```bash
cd ../../stages/01-foundation && terraform apply   # public_blob_policy_effect back to Deny
```

**Success signal:** the plan shows exactly one change (the assignment parameter back
to Deny), you approve, `Apply complete!`. The escalation ladder went down and back up,
and every rung is in your history: state, Activity Log, and Git.

## Verify

- [ ] Gate blocked the bad PR (or the local conftest run failed the bad plan), drift workflow enabled
- [ ] Compliance scan flagged the seed account NonCompliant
- [ ] Remediation task Succeeded and ran as the remediation identity (Activity Log caller check)
- [ ] Next collection + POA&M reflect the fix
- [ ] Deny re-escalated

## Teardown

This is the last lab, so course-end teardown applies: `terraform destroy` per stage
in reverse order (**06 → 04 → 03 → 01**), then
`az security pricing create --name StorageAccounts --tier Free` to end the Defender
trial meter, and delete the OIDC app registration if you armed your fork
(`az ad app delete --id <AZURE_CLIENT_ID>`). Keep the fork; it's your capstone.
