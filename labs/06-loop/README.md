# Lab 6 — Close the Loop

**Video:** 06_02 · **Time:** ~60 min (plus policy-evaluation waits) · **Cost:** $0
**Prereq:** Lab 5.

You break your sandbox on purpose, and the system detects it, proposes the fix, waits
for your approval, executes as the remediation identity, and documents itself.

## A design note you should understand first

Your foundation's **deny** policy makes the obvious sabotage impossible — you literally
cannot flip a storage account public while deny is active (we tried; validated). That's
the guardrail doing its job. So this lab also teaches the escalation ladder in reverse:
you'll **de-escalate deny → audit through a parameter change** (in production, that's a
reviewed one-line PR — automation acts, humans authorize), sabotage, remediate, then
re-escalate.

## Steps

### 1. Deploy enforcement (dry-run mode)

```bash
cd ../../stages/06-enforcement
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_state_storage_account=<from backend.hcl>
terraform apply    # remediation_mode defaults to "dry-run"
```

Read what dry-run means in `main.tf`: the modify policy deploys, but the assignment is
`DoNotEnforce` — compliance data accumulates, and **you** create the remediation task.
That task is the human approval gate.

### 2. Arm the CI gate — on YOUR fork, never upstream

```bash
./arm-your-fork.sh <your-github-username>
```

The script creates an OIDC app federated to **your fork**, grants it the plan roles,
and prints five repository **Variables** to add in your fork's UI (Settings → Secrets
and variables → Actions → Variables). They're variables, not secrets, because OIDC
stores no credential — the IDs grant nothing without the federation match.

Read the script's header before running it: it explains why the upstream repo is
deliberately unarmed (on a public repo, `pull_request` OIDC subjects match PRs from
any fork, and the PR can modify the workflow it runs — a trust boundary you should be
able to explain by the end of this course, because it's the same reasoning you'll
apply to every CI system you ever assess).

Then enable both workflows in your fork's Actions tab, add branch protection on `main`
requiring the gate, and test it: open a PR adding a public storage account to any
stage — conftest fails, naming the rule and the resource. Close it unmerged.
(Local test: `conftest test <plan.json> -p policy/`.)

### 3. De-escalate, then sabotage

```bash
cd ../../stages/01-foundation
terraform apply -var public_blob_policy_effect=Audit   # in prod: a reviewed PR
az storage account update --name <your seed account> --resource-group rg-grc-sandbox-dev \
  --allow-blob-public-access true                       # the out-of-band change
```

Two tripwires are now armed against you: the KQL drift query (your caller ID, in the
portal, making an administrative write) and the policy compliance scan.

### 4. Detect and remediate — with your approval

```bash
az policy state trigger-scan --resource-group rg-grc-sandbox-dev   # takes ~10-20 min
az policy state list --resource-group rg-grc-sandbox-dev \
  --filter "policyDefinitionName eq 'cge-fix-public-blob'" \
  --query "[].{resource:resourceId, state:complianceState}" -o table
```

When it shows NonCompliant, create the remediation task — this is you, the human at
the gate, approving the fix:

```bash
az policy remediation create --name fix-public-blob-$(date +%s) \
  --resource-group rg-grc-sandbox-dev \
  --policy-assignment $(az policy assignment list --disable-scope-strict-match \
      --query "[?name=='cge-fix-public-blob'].id" -o tsv)
```

Verify the fix and its author:

```bash
az storage account show --name <seed> -g rg-grc-sandbox-dev --query allowBlobPublicAccess
# false — and in the Activity Log, the caller is id-grc-remediation-dev, not you.
```

### 5. Close the loop

Trigger the collector (Lab 4 step 4). The assessment flips healthy in Cosmos;
regenerate the POA&M and the line item is gone. Nobody edited a document — the
documents noticed. Then re-escalate:

```bash
cd ../../stages/01-foundation && terraform apply   # public_blob_policy_effect back to Deny
```

## Verify

- [ ] Gate blocked the bad PR, drift workflow enabled
- [ ] Remediation task ran as the remediation identity (Activity Log caller check)
- [ ] Next collection + POA&M reflect the fix
- [ ] Deny re-escalated
