# Control Mappings

Every policy, collector, report and gate rule in this repository, mapped to the controls it serves.
This file is what turns the repository from code into a control catalogue, and it is a first-class
criterion on the capstone rubric.

- **NIST CSF 2.0** is the crosswalk the rubric grades: one category per row.
- **NIST SP 800-53 Rev. 5** identifiers are the controls a component implements or supports. They
  are my mapping of each component's behaviour to the control's intent, not a claim that a single
  component satisfies a control on its own. Titles are in the legend at the end.

Marked **(added)** are components I built or changed on top of the starter; the rest shipped with it.
Only components that exist in the code appear here.

## Stage 01: Foundation

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| Management group hierarchy + `cge-grc-baseline` initiative assignment | Controls inherit to every current and future subscription: compliance by design | CM-2, CM-6 | GV.PO, GV.OC |
| `cge-require-env-tag-rg` (Audit) | Inventory hygiene; ownership accountability feeds the POA&M | CM-8 | ID.AM |
| `cge-deny-public-blob` (Deny) | Prevents public blob exposure at the API, before the resource exists | AC-3, AC-4, SC-7 | PR.DS |
| `cge-dine-storage-diagnostics` (DeployIfNotExists) | Logging that enforces its own coverage | AU-2, AU-12 | PR.PS, DE.CM |
| Remediation identity (user-assigned, whitelisted roles) | Every automated change has a named, auditable author | AC-2, AC-6 | PR.AA, GV.RR |
| Log Analytics workspace + Activity Log routing | Central audit trail beyond the 90-day default | AU-2, AU-3, AU-12 | DE.CM, PR.PS |

## Stage 02: Activation

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| Defender plan baseline (discovery-first) | Reads every plan's tier, reports the gap, converges the baseline; plans outside it are never touched | CA-7, RA-5 | ID.RA, DE.CM |
| NIST CSF 2.0 initiative assignment | Maps Defender's continuous assessments to framework controls without re-testing | CA-2, CA-7 | GV.OV, ID.IM |

## Stage 03: Evidence Store

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| Cosmos DB (assessments / frameworks / mappings) | Owned evidence schema; collect once, crosswalk to every framework | CA-2, AU-9 | GV.OV, ID.RA |
| WORM immutability policy on `reports` | Artifacts tamper-proof by platform guarantee; a delete fails for every identity | AU-9, AU-11, SI-7 | PR.DS |
| Shared keys disabled + data-plane RBAC | Identity or nothing; no credentials to steal or rotate | IA-5, AC-3, AC-6 | PR.AA |
| Collector Function (Security Reader + Cosmos write only) | Continuous control-test capture with lineage; cannot alter what it observes | CA-7, AC-6 | DE.CM, ID.RA |
| Deterministic document IDs + `runId` / `collectedAt` (tested) | Re-runs refresh instead of duplicate; every record traces to a run | AU-3, SI-7 | PR.DS, DE.AE |
| Severity via `$expand=metadata` (added) | Stores each finding's severity so reports can rank and date it | CA-5, RA-5 | ID.RA |
| Owner stamping (added) | Every finding carries an accountable owner: the resource group's tag, else visibly unassigned, else the platform owner for subscription-level findings | CM-8(4), CA-5 | ID.AM, GV.RR |
| Collector / reporter identity split | The recorder of facts cannot author the narrative: SoD by role scopes | AC-5, AC-6 | PR.AA, GV.RR |

## Stage 04: Reporting

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| POA&M generator (daily, SLA-dated) | Weakness management with owners and dates, from the store only; findings ranked by severity with stable IDs (added) | CA-5 | ID.IM, GV.RM |
| SAR generator (weekly) | Assessment reporting where every number traces to a stored document; shows severity and owner (added) | CA-2 | ID.RA, GV.OV |
| Store-only reporting (guarded by a unit test) | No report generator references a live platform API, so any number is reproducible by a stored query | AU-7 | ID.RA, GV.OV |
| Reporter identity (Cosmos read + Blob write only) | Cannot write evidence, cannot read Defender | AC-5, AC-6 | PR.AA, GV.RR |

## Stage 06: Enforcement

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| `cge-fix-public-blob` (Modify, mode ladder) | Auto-remediation through the dedicated identity; human-approved in dry-run | CM-6, AC-3 | PR.DS, RS.MI |
| `remediation_mode` variable | Escalation is a reviewed diff: automation acts, humans authorize | CM-3 | GV.PO, GV.RR |

## Repository gates and operations

| Component | What it does | 800-53 Rev. 5 | CSF 2.0 |
|---|---|---|---|
| `policy/storage.rego` | Pipeline storage below the pipeline's own standard (public blob, shared keys) is unmergeable | CM-3, AC-3, IA-5 | PR.DS |
| `policy/policy_identity.rego` | Intended to block remediation that silently never runs; **does not fire today** (see README, Known gaps) | CM-3, CM-6 | PR.PS |
| `policy/broad_roles.rego` | Owner/Contributor grants in governance code are unmergeable | CM-3, AC-6 | PR.AA |
| `compliance-gate` workflow (hardened, added) | Terraform validate + plan for four stages, then a pinned, checksum-verified conftest; required on `main` | CM-3, CM-4 | ID.IM, PR.PS |
| Branch protection on `main` | Four required gate checks; force pushes disabled | CM-3, CM-5 | PR.PS |
| `drift-detection` workflow | Scheduled `terraform plan`: does reality match code | CM-2, CM-3, CM-6, CA-7 | DE.CM |
| `unit-tests` workflow and `tests/` (added) | 24 tests on the evidence path, run on pull requests and nightly | SA-11 | PR.PS |
| `guide-ci` workflow | Every code block and relative link in the guides is machine-checked | SA-11 | PR.PS |

## Blast radius and rollback

What each enforcement change would break, and how to undo it.

| Policy | What changes | What could break | Rollback |
|---|---|---|---|
| `cge-deny-public-blob` (Deny) | Creating or updating a storage account with public blob access is rejected at the API. Existing public accounts are not changed by a Deny. | Anything relying on anonymous blob access, such as static-site hosting. Infrastructure code that sets `allow_nested_items_to_be_public = true` fails to apply. | Set `public_blob_policy_effect` to `Audit` through a reviewed change; it takes effect within minutes. |
| `cge-require-env-tag-rg` (Audit) | Nothing is blocked; resource groups without an `env` tag are marked non-compliant. | Nothing operational; it adds compliance noise. | Set `tag_policy_effect` to `Disabled`. |
| `cge-dine-storage-diagnostics` (DeployIfNotExists) | Deploys a diagnostic setting on storage accounts, routing to the GRC workspace. | Adds log ingestion cost. Needs the remediation identity's Monitoring Contributor role. | Remove the assignment; diagnostic settings already deployed remain and must be deleted separately. |
| `cge-fix-public-blob` (Modify, dry-run) | Sets `allowBlobPublicAccess` to `false` on non-compliant storage accounts under `mg-grc-sandbox`. In dry-run nothing changes until a person creates a remediation task. It cannot delete resources or read data. | Anything that needs anonymous blob access to an existing account. | Set `remediation_mode` to `audit` and merge; in-flight tasks fail closed. |
| Remediation identity roles | Monitoring Contributor (stage 01) and Storage Account Contributor (stage 06), both at `mg-grc-sandbox`. | The Storage Account Contributor built-in role can also list and regenerate account keys; a custom role limited to writing storage accounts would be narrower. | Remove the role assignment. |

## Legend: NIST SP 800-53 Rev. 5 controls used

AC-2 Account Management · AC-3 Access Enforcement · AC-4 Information Flow Enforcement ·
AC-5 Separation of Duties · AC-6 Least Privilege · AU-2 Event Logging · AU-3 Content of Audit Records ·
AU-7 Audit Record Reduction and Report Generation · AU-9 Protection of Audit Information ·
AU-11 Audit Record Retention · AU-12 Audit Record Generation · CA-2 Control Assessments ·
CA-5 Plan of Action and Milestones · CA-7 Continuous Monitoring · CM-2 Baseline Configuration ·
CM-3 Configuration Change Control · CM-4 Impact Analyses · CM-5 Access Restrictions for Change ·
CM-6 Configuration Settings · CM-8 System Component Inventory · CM-8(4) Accountability Information ·
IA-5 Authenticator Management · RA-5 Vulnerability Monitoring and Scanning · SA-11 Developer Testing
and Evaluation · SC-7 Boundary Protection · SI-7 Software, Firmware, and Information Integrity
