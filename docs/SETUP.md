# CGE-AZ Lab Setup Guide

Do this once, before Lab 1. Total time: ~20 minutes of work, plus a few waits.
Every step here exists because skipping it broke a real lab run on a real fresh
account — see [VALIDATION-LOG.md](VALIDATION-LOG.md) for the receipts.

## 0. What you need

- **An Azure free account** — [azure.microsoft.com/free](https://azure.microsoft.com/free).
  You get **USD 200 of credit for your first 30 days**, free monthly amounts of 20+
  services for 12 months, 65+ always-free services, and **spending protection**: your
  card is never charged unless you deliberately upgrade to pay-as-you-go.
- **Azure CLI** (`brew install azure-cli` / [install docs](https://learn.microsoft.com/cli/azure/install-azure-cli)) — validated on 2.90.
- **Terraform >= 1.9** (`brew install terraform`) — validated on 1.14.
- **Python 3.11+** with `pip`.
- **A GitHub account** and `git`.
- Domain 6 also uses **conftest** (`brew install conftest`).

## 1. Timing strategy — read this before creating anything

Two 30-day clocks matter, and you start both:

1. **The $200 credit clock** starts when you create the free account.
2. **The Defender trial clock** starts in Lab 2 when you enable your first paid plan.

Create the account when you're ready to actually take the course, do Lab 2 within the
first few days, and both windows comfortably cover Labs 2–6 and the capstone. If life
interrupts you mid-course, that's fine — everything except the one Defender plan is
free-tier, and the teardown script kills the plan in one command.

**One more clock:** Defender's *first assessment cycle* on a brand-new subscription can
take several hours to ~24h. Lab 2 sets this expectation; don't panic at an empty
assessments API on day one.

## 2. Sign in and register resource providers

```bash
az login
az account show   # confirm the right subscription
```

Fresh subscriptions have almost every resource provider **unregistered**, which produces
confusing errors deep into the labs. Register the eight the course uses now:

```bash
for ns in Microsoft.Management Microsoft.OperationalInsights Microsoft.Security \
          Microsoft.DocumentDB Microsoft.Web Microsoft.Storage Microsoft.Insights \
          Microsoft.PolicyInsights; do
  az provider register --namespace $ns
done
```

Registration takes ~2–3 minutes; check with
`az provider list --query "[?registrationState=='Registering'].namespace"` — empty means done.

## 3. Fork and clone the repo

Fork `github.com/GRCEngClub/cgeaz` to your own account, then:

```bash
git clone https://github.com/<you>/cgeaz.git
cd cgeaz
```

Every lab lives in `labs/`, every pipeline stage in `stages/`.

## 4. Know the regional quirks (validated 2026-09)

- **Consumption-plan (Y1) quota is regional and ZERO in most US regions on free
  accounts.** In validation, `centralus` and `westus3` worked; eastus, eastus2, westus2,
  southcentralus, northcentralus did not. Before Lab 4, run:

  ```bash
  ./labs/00-setup/probe-quota.sh
  ```

  and set `functions_location` (stages 03/04) to a region marked OK.
- **East US frequently lacks Cosmos DB capacity** for new subscriptions. The evidence
  store defaults to `eastus2` for this reason. Leave it unless it fails, then pick
  another region.

## 5. Known CLI potholes (already routed around in the labs)

| Symptom | Cause | The lab's fix |
|---|---|---|
| `az consumption budget create` → 400 | CLI uses a retired API | Lab 1 uses `az rest` (script provided) |
| `az monitor diagnostic-settings create` → `KeyError: resource_group` at subscription scope | CLI parsing bug | Lab 2 uses `az rest` (script provided) |
| `terraform init` → 403 `AuthorizationPermissionMismatch` on brand-new state storage | Blob **data-plane** role just granted; RBAC propagation | Wait 1–3 minutes and retry — bootstrap.sh warns you |
| First management group creation hangs a couple of minutes | Tenant root group being provisioned | Wait; do not re-run |
| Assessments API returns `[]` on a new subscription | Defender's first cycle hasn't run | Expected — see timing strategy above |

## 6. Cost guardrails (defense in depth for your wallet)

Three layers, in order of who saves you:

1. **Spending protection** — free accounts don't charge your card unless you upgrade.
2. **The $200 credit** — absorbs anything the free tiers don't.
3. **Your Lab 1 budget alert** — $10/month with actual + forecast alerts, so you hear
   about a runaway before it matters.

Validated lab-run costs: everything except the Defender for Storage trial is free tier or
pennies (Cosmos serverless, consumption Functions, one Log Analytics workspace at PerGB2018
with lab-scale ingestion). Teardown scripts exist in every lab folder; the course-end
teardown is `terraform destroy` per stage, in reverse order (06 → 04 → 03 → 01).

You're ready. Start with `labs/01-sandbox`.

## Appendix: CI identity (course-team setup, not learner setup)

The gate and drift workflows authenticate via OIDC federation — app registration
`github-cgeaz-pipeline`, federated for `repo:GRCEngClub/cgeaz:pull_request` and
`:ref:refs/heads/main`. It holds Contributor at `mg-grc` (plan/refresh needs list-keys
and config-read actions that Reader lacks; Contributor cannot write RBAC) plus
Storage Blob Data Contributor on the state RG. Hardening this to a plan-only custom
role is a worthwhile production exercise — and a good community PR.
