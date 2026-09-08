# Control Mappings

Every policy, collector, and gate rule in this repo, mapped to the NIST CSF 2.0
category it serves. This file is what turns the repo from code into a control catalog —
and it's a first-class criterion on the capstone rubric.

## Stage 01 — Foundation

| Component | What it does | CSF 2.0 |
|---|---|---|
| Management group hierarchy + initiative assignment | Controls inherit to every current and future subscription — compliance by design | GV.PO, GV.OC |
| `cge-require-env-tag-rg` (Audit) | Inventory hygiene; owner accountability feeds the POA&M | ID.AM |
| `cge-deny-public-blob` (Deny) | Prevents public blob exposure at the API, before the resource exists | PR.DS |
| `cge-dine-storage-diagnostics` (DeployIfNotExists) | Logging that enforces its own coverage | PR.PS, DE.CM |
| Remediation identity (user-assigned, whitelist roles) | Every automated change has a named, auditable author | PR.AA, GV.RR |
| Log Analytics workspace + Activity Log routing | Central audit trail beyond the 90-day default | DE.CM, PR.PS |

## Stage 03 — Evidence Store

| Component | What it does | CSF 2.0 |
|---|---|---|
| Cosmos DB (assessments / frameworks / mappings) | Owned evidence schema; collect once, crosswalk to every framework | GV.OV, ID.RA |
| WORM immutability policy on `reports` | Artifacts tamper-proof by platform guarantee | PR.DS |
| Shared keys disabled + data-plane RBAC | Identity or nothing; no credentials to steal or rotate | PR.AA |
| Collector Function (Security Reader + Cosmos write only) | Continuous control-test capture with lineage; cannot alter what it observes | DE.CM, ID.RA |
| Collector/reporter identity split | The recorder of facts cannot author the narrative — SoD by role scopes | PR.AA, GV.RR |

## Stage 04 — Reporting

| Component | What it does | CSF 2.0 |
|---|---|---|
| POA&M generator (daily, SLA-dated) | Weakness management with owners and dates, from the store only | ID.IM, GV.RM |
| SAR generator (weekly) | Assessment reporting where every number traces to a stored document | ID.RA, GV.OV |

## Stage 06 — Enforcement

| Component | What it does | CSF 2.0 |
|---|---|---|
| `cge-fix-public-blob` (Modify, mode ladder) | Auto-remediation through the dedicated identity; human-approved in dry-run | PR.DS, RS.MI |
| `remediation_mode` variable | Escalation is a reviewed diff — automation acts, humans authorize | GV.PO, GV.RR |

## Repo gates (policy/)

| Rule | Mistake it makes unmergeable | CSF 2.0 |
|---|---|---|
| `storage.rego` | Pipeline storage below the pipeline's own standard | PR.DS |
| `policy_identity.rego` | Remediation that silently never runs | PR.PS |
| `broad_roles.rego` | Owner/Contributor grants in governance code | PR.AA |
| `drift.yml` + KQL tripwire | Out-of-band change going unnoticed | DE.CM, DE.AE |
