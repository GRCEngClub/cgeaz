# Lab 1 — Stand Up Your Azure GRC Sandbox

**Video:** 01_04 · **Time:** ~30 min · **Cost:** $0
**Prereq:** [docs/SETUP.md](../../docs/SETUP.md) completed (providers registered!).

Everything you build for the rest of the course deploys into what you create here.

## Deliverables

1. Management group hierarchy: `mg-grc` → `mg-grc-sandbox` → your subscription
2. Tagged resource group `rg-grc-sandbox-dev`
3. `grc-auditors` Entra group with Reader, scoped to the resource group only
4. $10/month budget with actual + forecast alerts

## Steps

### 1. The hierarchy

```bash
az account management-group create --name mg-grc --display-name "GRC Engineering"
az account management-group create --name mg-grc-sandbox --display-name "GRC Sandbox" --parent mg-grc
az account management-group subscription add --name mg-grc-sandbox \
  --subscription $(az account show --query id -o tsv)
```

> The **first** management group in a tenant can take a couple of minutes while Azure
> creates the tenant root group. Normal. Don't re-run.

Verify: portal → Management groups → your tree.

### 2. The resource group (tagged from birth)

```bash
az group create --name rg-grc-sandbox-dev --location eastus \
  --tags env=dev owner=<your-email> purpose=cge-az-labs
```

The `owner` tag isn't decoration — Domain 5's POA&M generator resolves finding owners
from it. Boring, predictable names are a control: they make anomalies visible.

### 3. The scoped role assignment

```bash
az ad group create --display-name grc-auditors --mail-nickname grc-auditors
GROUP_ID=$(az ad group show --group grc-auditors --query id -o tsv)
RG_ID=$(az group show --name rg-grc-sandbox-dev --query id -o tsv)
az role assignment create --assignee-object-id $GROUP_ID \
  --assignee-principal-type Group --role Reader --scope $RG_ID
```

Read it back — and save it, because this is your first evidence artifact of the course:

```bash
az role assignment list --resource-group rg-grc-sandbox-dev --output json > lab1-evidence.json
```

Role + principal + scope, timestamped, no screenshots.

### 4. The budget

`az consumption budget create` is broken against the current API (validated — you get a
400). Use the provided script, which calls the budgets API directly:

```bash
./create-budget.sh <your-email>
```

Or do it in the portal: Cost Management → Budgets → $10/month, alert at 80% **actual**
and 100% **forecast**. Yes, your free account already has spending protection and $200
credit. Defense in depth applies to your wallet too.

## Verify

- [ ] `az account management-group show --name mg-grc --expand` shows the tree
- [ ] Resource group exists with all three tags
- [ ] `az role assignment list --resource-group rg-grc-sandbox-dev` shows Reader / grc-auditors / RG scope
- [ ] Budget shows in Cost Management with two alert conditions

## Teardown

None — nothing here costs money at rest, and every later lab builds inside it.
