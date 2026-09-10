# Lab 1 — Stand Up Your Azure GRC Sandbox

| | |
|---|---|
| **Video** | 01_04 |
| **Hands-on time** | ~30 min (plus a possible one-time wait on the first management group) |
| **Cost** | $0. Nothing in this lab has a running meter. The $10/month budget you create here is itself the guardrail for every later lab, sitting in front of free-account spending protection and the $200 credit. |
| **Prerequisites** | [docs/SETUP.md](../../docs/SETUP.md) completed. Providers registered (`Microsoft.Management` especially, or step 1 fails). |
| **Where you'll work** | Your fork of `cgeaz`, cloned locally. Run every command in this lab from `cgeaz/labs/01-sandbox`. |

Everything you build for the rest of the course deploys into what you create here.

> **On a corporate tenant?** This lab assumes your own free tenant, where your account
> can create management groups and Entra groups. On an employer tenant you usually
> can't (and shouldn't). Fallback: ask an admin for a sandbox management group you own,
> or do the course on a personal free account. That's the designed path.

## Deliverables

1. Management group hierarchy: `mg-grc` → `mg-grc-sandbox` → your subscription
2. Tagged resource group `rg-grc-sandbox-dev`
3. `grc-auditors` Entra group with Reader, scoped to the resource group only
4. $10/month budget with actual + forecast alerts

## Steps

### 1. The hierarchy

**where:** `cgeaz/labs/01-sandbox`

```bash
az account management-group create --name mg-grc --display-name "GRC Engineering"
az account management-group create --name mg-grc-sandbox --display-name "GRC Sandbox" --parent mg-grc
az account management-group subscription add --name mg-grc-sandbox \
  --subscription $(az account show --query id -o tsv)
```

**Success signal:** each command returns JSON describing the group (the first two) or
returns silently (the subscription add). Portal → Management groups shows
`mg-grc` → `mg-grc-sandbox` → your subscription. The validated run created all three
levels without error.

> **Wait, not error:** the **first** management group in a tenant also creates the
> tenant root group behind the scenes. Ours was fast, but delays of several minutes
> are documented and normal. If the command sits there, let it sit. **Don't re-run**:
> you'll race the root-group provisioning.

### 2. The resource group (tagged from birth)

**where:** `cgeaz/labs/01-sandbox`

```bash
az group create --name rg-grc-sandbox-dev --location eastus \
  --tags env=dev owner=you@example.com purpose=cge-az-labs
```

Replace `you@example.com` with your real email. **Success signal:** the returned JSON
shows `"provisioningState": "Succeeded"` and all three tags under `tags`.

The `owner` tag isn't decoration — Domain 5's POA&M generator resolves finding owners
from it. Boring, predictable names are a control: they make anomalies visible.

### 3. The scoped role assignment

**where:** `cgeaz/labs/01-sandbox`

```bash
az ad group create --display-name grc-auditors --mail-nickname grc-auditors
GROUP_ID=$(az ad group show --group grc-auditors --query id -o tsv)
RG_ID=$(az group show --name rg-grc-sandbox-dev --query id -o tsv)
az role assignment create --assignee-object-id $GROUP_ID \
  --assignee-principal-type Group --role Reader --scope $RG_ID
```

**Success signal:** the final command returns JSON whose `roleDefinitionName` is
`Reader` and whose `scope` ends in `/resourceGroups/rg-grc-sandbox-dev` — group scope,
not subscription scope. That distinction is the whole point of the step.

> **Windows / Git Bash:** Git Bash rewrites arguments that start with `/` into Windows
> paths, which mangles Azure resource IDs like the `--scope` value here. Prefix the
> command with `MSYS_NO_PATHCONV=1` (or export it for the session) whenever an argument
> is a resource ID:
>
> ```bash
> export MSYS_NO_PATHCONV=1
> ```

Read it back — and save it, because this is your first evidence artifact of the course:

```bash
az role assignment list --resource-group rg-grc-sandbox-dev --output json > lab1-evidence.json
```

Role + principal + scope, timestamped, no screenshots. (`lab1-evidence.json` is
gitignored; evidence goes in your evidence store starting in Lab 4, not in the repo.)

### 4. The budget

`az consumption budget create` is broken against the current API. Validated on a fresh
account, and this is the exact error you get:

```
(400) Invalid budget configuration, please use filter interface with 2019-05-01-preview version
```

Don't debug that error; it's not you, it's the CLI calling a retired API. Use the
provided script, which calls the budgets API directly via `az rest`:

**where:** `cgeaz/labs/01-sandbox`

```bash
./create-budget.sh you@example.com
```

**Expected output:**

```
budget-cge-az-labs
budget-cge-az-labs created: $10/month, alerts at 80% actual and 100% forecast.
```

Or do it in the portal: Cost Management → Budgets → $10/month, alert at 80% **actual**
and 100% **forecast**. Yes, your free account already has spending protection and $200
credit. Defense in depth applies to your wallet too.

> **Cost Management can lag on brand-new subscriptions.** If the Budgets blade errors
> or shows nothing right after account creation, give it a little while and check the
> script's own output above: the `az rest` call succeeding is the source of truth.

## Verify

- [ ] `az account management-group show --name mg-grc --expand` shows the tree
- [ ] Resource group exists with all three tags (`az group show --name rg-grc-sandbox-dev --query tags`)
- [ ] `az role assignment list --resource-group rg-grc-sandbox-dev` shows Reader / grc-auditors / RG scope
- [ ] `lab1-evidence.json` saved locally
- [ ] Budget shows in Cost Management with two alert conditions

## Teardown

None — nothing here costs money at rest, and every later lab builds inside it.
