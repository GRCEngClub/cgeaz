# Lab 3 — Deploy Your Foundation

| | |
|---|---|
| **Video** | 03_03 |
| **Hands-on time** | ~60 min (includes one validated ~2.5 min RBAC-propagation wait) |
| **Cost** | $0. State storage is one LRS account holding kilobytes; policies and assignments are free. Guardrail: the Lab 1 budget. |
| **Prerequisites** | Labs 1–2; Terraform >= 1.9; this repo forked and cloned; `az login` active. |
| **Where you'll work** | Two directories: `cgeaz/labs/03-foundation` (bootstrap), then `cgeaz/stages/01-foundation` (Terraform). Each step says which. |

Your sandbox stops being hand-built and starts being governed by code. Destination:
a denied deployment.

> **On a corporate tenant?** Stage 01 defines policy at management-group scope, which
> assumes the `mg-grc` hierarchy from Lab 1 is yours. If an admin gave you a sandbox
> management group instead, import that group in step 2 rather than creating a new
> one. If you have no management-group rights at all, this course's designed path is
> a personal free account.

## Steps

### 1. Bootstrap remote state

**where:** `cgeaz/labs/03-foundation`

```bash
./bootstrap.sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID   # every stage takes the subscription explicitly
```

Creates the state resource group, a **versioned** storage account, the `tfstate`
container, and grants you `Storage Blob Data Contributor` — because Terraform state
access is **data plane** and Owner alone gets a 403 (the 01_02 lesson, live).
It also writes `backend.hcl` for every stage to share.

**Expected output** (abridged; the storage-account suffix is derived from your
subscription ID, so yours differs):

```
>> State resource group: rg-grc-tfstate
>> State storage account: stgrctfstateXXXXXXXX (versioned, no public blob access)
>> Enabling blob versioning (every state change becomes a recoverable version)
>> State container: tfstate
>> Granting you Storage Blob Data Contributor on the state resource group
   Note: a fresh role grant can take 1-2 minutes to propagate before terraform init works.

Bootstrap complete. Backend config written to: ./backend.hcl
```

### 2. Init and adopt (never recreate what exists)

**where:** `cgeaz/stages/01-foundation`

```bash
cd ../../stages/01-foundation
terraform init -backend-config=../../labs/03-foundation/backend.hcl
```

> **If init fails with a 403, that's the RBAC wait, not a mistake.** The validated
> run hit exactly this:
>
> ```
> Error: ... status 403 ... AuthorizationPermissionMismatch
> ```
>
> The blob **data-plane** role bootstrap just granted takes 1–3 minutes to propagate
> (validated: ~2.5 minutes on a fresh account). Wait, then re-run `terraform init`
> until it completes. Do not add yourself more roles, and do not recreate the storage
> account; time is the only fix.

> **If a command hangs on `Acquiring state lock…` and never returns**, a previous
> `terraform` run was interrupted and left a lock on the state blob. Take the lock ID
> from the error and run `terraform force-unlock <ID>`, or break the blob lease on the
> state file (`az storage blob lease break`). Only do this when no other run is active.

**Success signal:** `Terraform has been successfully initialized!`

Now adopt what Labs 1 and 2 built by hand:

```bash
export TF_VAR_owner_email=you@example.com   # must match the tag from Lab 1

SUB=/subscriptions/$ARM_SUBSCRIPTION_ID
terraform import azurerm_management_group.grc /providers/Microsoft.Management/managementGroups/mg-grc
terraform import azurerm_management_group.sandbox /providers/Microsoft.Management/managementGroups/mg-grc-sandbox
terraform import azurerm_resource_group.sandbox $SUB/resourceGroups/rg-grc-sandbox-dev
terraform import azurerm_log_analytics_workspace.grc $SUB/resourceGroups/rg-grc-sandbox-dev/providers/Microsoft.OperationalInsights/workspaces/law-grc-sandbox
```

> **Windows / Git Bash:** every import ID starts with `/` and Git Bash will mangle it.
> `export MSYS_NO_PATHCONV=1` first (see Lab 1).

> **All four imports must land before you apply.** If a later `terraform apply` fails
> with `... already exists - to be managed via Terraform this resource needs to be
> imported into the State`, one or more imports didn't take (an interrupted run, a
> skipped line). These errors surface in **dependency order** — Terraform reports the
> independent resources first, and the dependents (`mg-grc-sandbox` needs `mg-grc`; the
> workspace needs the resource group) only after those are fixed — so reacting to them
> one at a time feels like whack-a-mole. Instead, list what is actually in state and
> re-import everything still missing in a single pass:
>
> ```bash
> terraform state list   # compare against the four resources imported above
> ```

**Success signal:** each import ends with Terraform reporting the import succeeded.
Then run `terraform plan` and read it. The goal for the imported resources is **no
changes** (tag diffs are fine to let TF settle). In the validated run the plan
converged to `No changes.` for all four imports. "No changes" means code and reality
agree — your first governance milestone.

### 3. Read, then apply

**where:** `cgeaz/stages/01-foundation`

Read `main.tf`, `policies.tf`, `identity.tf` — never apply code you haven't read, even
ours. Note the `identity` block on the assignment: remediation effects silently no-op
without it. Then:

```bash
terraform apply
```

**Success signal:** the plan shows roughly 8 resources to add (workspace under
management, evidence RG, three policies, the initiative, its management-group
assignment, the remediation identity + role), you approve, and it ends with
`Apply complete!`. This applied cleanly in validation; if it errors on the policy set
definition, confirm you're on azurerm ~> 4.0 (`terraform version`), where the
management-group policy set resource replaced the deprecated one.

### 4. The proof: a denied deployment

**where:** `cgeaz/stages/01-foundation` (any directory with az works)

```bash
az storage account create --name stgrcdenytest$RANDOM --resource-group rg-grc-sandbox-dev \
  --location eastus --sku Standard_LRS --allow-blob-public-access true \
  2>&1 | tee lab3-deny-evidence.txt
```

**Expected output:** the command FAILS, and the failure is the deliverable:

```
RequestDisallowedByPolicy
```

Read the full error: it names the policy, the initiative, and the assignment (the
`Policy identifiers` block), and the resource was never created. The `tee` above saved
the full text to `lab3-deny-evidence.txt` — that file is your preventive-control
evidence artifact. (The CLI prints a text error, not clean JSON; the raw text with the
policy identifiers is the artifact.)

> **If the create unexpectedly SUCCEEDS:** you likely ran it within moments of the
> apply. Validated: enforcement was live within ~2 minutes of assignment. Delete the
> account, wait two minutes, try again.

Then retry without the `--allow-blob-public-access true` flag and watch it succeed
(then `az storage account delete` the test account, it's served its purpose). The
pair is the complete story: safe path permitted, unsafe path blocked.

## Verify

- [ ] Portal: initiative assigned at mg-grc-sandbox, inheriting to the subscription
- [ ] `terraform plan` → No changes
- [ ] The deny fired; the compliant retry succeeded; test account cleaned up
- [ ] Understand the workflow shift: from here on, all infrastructure changes go through the repo, never the portal. You start committing and pushing your own code in Lab 4 — Labs 1–3 only import and apply the provided starter, so there is nothing new to commit yet.

## Teardown

None during the course — this foundation carries everything. Course-end:
`terraform destroy` (after destroying stages 06/04/03 first).
