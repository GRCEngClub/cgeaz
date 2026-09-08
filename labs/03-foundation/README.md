# Lab 3 — Deploy Your Foundation

**Video:** 03_03 · **Time:** ~60 min · **Cost:** $0
**Prereq:** Labs 1–2; Terraform >= 1.9; this repo forked and cloned.

Your sandbox stops being hand-built and starts being governed by code. Destination:
a denied deployment.

## Steps

### 1. Bootstrap remote state

```bash
./bootstrap.sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

Creates the state resource group, a **versioned** storage account, the `tfstate`
container, and grants you `Storage Blob Data Contributor` — because Terraform state
access is **data plane** and Owner alone gets a 403 (the 01_02 lesson, live).
It also writes `backend.hcl` for every stage to share.

> **The fresh role grant takes 1–3 minutes to propagate.** If `terraform init` 403s,
> wait and retry — validated propagation time was ~2.5 minutes.

### 2. Init and adopt (never recreate what exists)

```bash
cd ../../stages/01-foundation
terraform init -backend-config=../../labs/03-foundation/backend.hcl
export TF_VAR_owner_email=<your-email>

SUB=/subscriptions/$ARM_SUBSCRIPTION_ID
terraform import azurerm_management_group.grc /providers/Microsoft.Management/managementGroups/mg-grc
terraform import azurerm_management_group.sandbox /providers/Microsoft.Management/managementGroups/mg-grc-sandbox
terraform import azurerm_resource_group.sandbox $SUB/resourceGroups/rg-grc-sandbox-dev
terraform import azurerm_log_analytics_workspace.grc $SUB/resourceGroups/rg-grc-sandbox-dev/providers/Microsoft.OperationalInsights/workspaces/law-grc-sandbox
```

Run `terraform plan` and read it. The goal for the imported resources is **no changes**
(tag diffs are fine to let TF settle). "No changes" means code and reality agree — your
first governance milestone.

### 3. Read, then apply

Read `main.tf`, `policies.tf`, `identity.tf` — never apply code you haven't read, even
ours. Note the `identity` block on the assignment: remediation effects silently no-op
without it. Then:

```bash
terraform apply
```

~8 new resources: workspace under management, evidence RG, three policies, the
initiative, its management-group assignment, the remediation identity + role.

### 4. The proof: a denied deployment

```bash
az storage account create --name stgrcdenytest$RANDOM --resource-group rg-grc-sandbox-dev \
  --location eastus --sku Standard_LRS --allow-blob-public-access true
```

**`RequestDisallowedByPolicy`** — read the error: it names the policy, the initiative,
and the assignment, and the resource was never created. (Validated: enforcement was
live within ~2 minutes of assignment.) Save the error JSON — it's a preventive-control
evidence artifact. Then retry without the flag and watch it succeed. The pair is the
complete story: safe path permitted, unsafe path blocked.

## Verify

- [ ] Portal: initiative assigned at mg-grc-sandbox, inheriting to the subscription
- [ ] `terraform plan` → No changes
- [ ] The deny fired; the compliant retry succeeded
- [ ] Committed and pushed — from here on: **changes go through the repo, never the portal**

## Teardown

None during the course — this foundation carries everything. Course-end:
`terraform destroy` (after destroying stages 06/04/03 first).
