# CGE-AZ Lab Validation Log

Every lab in this repo was executed end-to-end against a **brand-new Azure free account**
(created 2026-09-08, tenant `hellogrcengclub.onmicrosoft.com`) before the course shipped.
This log records what actually happened — including everything that broke — and the fix
that is now baked into the labs. If a lab step surprises you, check here first.

## Environment

| Item | Value |
|---|---|
| Account type | Azure free account ($200 / 30-day credit, spending protection on) |
| Azure CLI | 2.90.0 |
| Terraform | 1.14.9 |
| azurerm provider | ~> 4.0 |
| Validation date | 2026-09-08 |

## Findings and fixes

### F1 — Fresh subscriptions have almost no resource providers registered
`Microsoft.Management`, `Microsoft.Security`, `Microsoft.OperationalInsights`,
`Microsoft.DocumentDB`, `Microsoft.Web`, `Microsoft.Storage`, `Microsoft.Insights`,
`Microsoft.PolicyInsights` were all `NotRegistered` out of the box. Symptoms range from
clear errors to confusing 404s.
**Fix:** SETUP.md step 2 registers all eight up front. Registration took ~2–3 minutes.

### F2 — `az consumption budget create` is broken against the current API
Returns `(400) Invalid budget configuration, please use filter interface with
2019-05-01-preview version`.
**Fix:** Lab 1 creates the budget with `az rest` against
`Microsoft.Consumption/budgets` API `2023-11-01` (script provided), or the portal.

### F3 — Subscription-scope diagnostic settings fail in `az monitor diagnostic-settings create`
CLI 2.90 throws `KeyError: 'resource_group'` when the target is a bare subscription.
**Fix:** Lab 2 routes the Activity Log with `az rest` against
`Microsoft.Insights/diagnosticSettings` API `2021-05-01-preview` (script provided).

### F4 — Owner ≠ blob data access (Terraform state 403)
`terraform init` against the state account returned 403 `AuthorizationPermissionMismatch`
even as subscription Owner: state access is **data plane**, Owner is **control plane**.
This is lesson 01_02's control-vs-data-plane split biting in real life.
**Fix:** `bootstrap.sh` always grants the runner `Storage Blob Data Contributor` on the
state resource group. **Propagation took ~2.5 minutes** — init retries until clean.

### F5 — First management group can be slow
The first management group in a tenant triggers creation of the tenant root group.
Ours was fast, but delays of minutes are documented and normal. Don't re-run the command.

### F6 — Defender assessments are EMPTY for the first hours of a new subscription
`GET /providers/Microsoft.Security/assessments` legitimately returns `[]` until Defender's
first assessment cycle runs (can take up to ~24h on a brand-new subscription, and there must
be resources to assess).
**Fix:** Lab 2 creates a seed storage account, sets the expectation in the README, and the
Lab 2 "first API pull" is repeated at the start of Lab 4, by which point data exists.

### F7 — Activity Log routing only captures events AFTER routing exists
The Lab 1 role assignment did not appear in Log Analytics because it predates the Lab 2
diagnostic setting.
**Fix:** Lab 2's KQL verification queries an action taken after routing (the budget write /
policy assignment writes), and tells you to make a fresh change if the table is quiet.
Ingestion lag observed: ~5–10 minutes.

### F8 — East US could not host the evidence plane at all
Two independent failures in `eastus` on validation day:
- Cosmos DB: `ServiceUnavailable — high demand in East US region … cannot fulfill your request`.
  (The account even showed `Succeeded` in `az resource list` while actually `Failed` — check
  `provisioningState` on the resource itself, not the deployment list.)
- App Service consumption plan: `Current Limit (Y1 VMs): 0`.
**Fix:** stage 03 defaults: evidence store in `eastus2`, function tier in `centralus`.

### F9 — Free accounts have ZERO consumption-plan quota in most US regions
Probing serverfarm creation (SKU Y1) region by region on this free subscription:

| Region | Y1 quota |
|---|---|
| eastus | 0 |
| eastus2 | 0 |
| westus2 | 0 |
| southcentralus | 0 |
| northcentralus | 0 |
| **centralus** | **OK** |
| **westus3** | **OK** |

**Fix:** `labs/00-setup/probe-quota.sh` runs this probe against your subscription before
Lab 4; stage 03's `functions_location` variable defaults to `centralus`.
(Discovery before action applies to quotas too.)

### F10 — Keyless storage needs `storage_use_azuread = true`
With `shared_access_key_enabled = false` on the evidence account, the azurerm provider's
data-plane calls fail unless the provider block sets `storage_use_azuread = true` and the
runner holds a blob data role.
**Fix:** stage 03 sets the provider flag and grants the deployer
`Storage Blob Data Contributor` on the evidence account as part of the stage.

### F11 — `azurerm_policy_set_definition` at management-group scope is deprecated in azurerm 4.x
**Fix:** stage 01 uses `azurerm_management_group_policy_set_definition`.

## What worked exactly as designed (first try)

- Management group hierarchy + subscription move (Lab 1)
- Tagged RG, Entra group, scoped Reader assignment, `az role assignment list` evidence (Lab 1)
- Defender for Storage `az security pricing create` — trial clock confirmed at 30 days (Lab 2)
- Built-in **NIST CSF v2.0** initiative (`184a0e05-7b06-4a68-bbbe-13b8353bc613`) assignment (Lab 2)
- Log Analytics workspace + KQL over AzureActivity (Lab 2)
- `terraform import` adoption of all Lab 1/2 resources → plan converged to **No changes** (Lab 3)
- The deny test: `RequestDisallowedByPolicy` fired **within ~2 minutes** of assignment,
  naming the policy, initiative, and assignment; compliant retry succeeded (Lab 3)
- Cosmos serverless + 3 containers + WORM immutability policy + all identity wiring (Lab 4)
- Zip deploy with remote build to the consumption Function App (Lab 4)

## Lab 5 / Lab 6 validation (same session, continued)

- Reporting stage deployed; POA&M (xlsx+json) and SAR (md) generated via HTTP triggers
  and landed on dated paths in the WORM container. Empty-store runs are clean, not errors.
- OPA gate validated both directions with conftest 0.6x: clean foundation plan passed
  4/4; a deliberately bad plan (public blob + shared keys) failed with named rules.
- **Lab 6 design finding:** the foundation deny policy blocks the sabotage itself —
  you cannot flip a storage account public while deny stands (deny fires on updates).
  The lab now teaches deliberate de-escalation (Deny → Audit via parameter = a reviewed
  one-line PR), sabotage, remediation, re-escalation.
- Full loop executed on-account: de-escalated, flipped the seed account public,
  `az policy state trigger-scan` (~15 min), compliance flagged **NonCompliant**,
  remediation task created manually (the dry-run approval), task **Succeeded (1/0)**,
  `allowBlobPublicAccess` back to `false` — fixed by the remediation identity, not a
  human command — then deny re-escalated.
- Remediation caveat: `az policy remediation create` needs the assignment's **full
  resource ID** (management-group-scoped assignments aren't found by name from a
  subscription context).
