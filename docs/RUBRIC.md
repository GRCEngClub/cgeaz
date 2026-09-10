# CGE-AZ Capstone Rubric

Your capstone is the pipeline itself: foundations, evidence plane, at least two live
reports, and enforcement in dry-run, deployed as code in your own subscription and
submitted as a public GitHub repo. This rubric is public on purpose. Read it on day
one; run it against yourself before you submit.

The canonical machine-graded version lives at
**[cert.grcengclub.com/rubric/cge-az](https://cert.grcengclub.com/rubric/cge-az)** —
this file mirrors it for offline reading. If they ever disagree, the Academy page wins.

**Pass = weighted average ≥ 70 across five dimensions AND no auto-fail triggers.**
Two attempts, 24-hour cooldown between them. Written feedback either way. Appeals
after both attempts: hello@grcengclub.com.

## Submission requirements

- Public GitHub repository, ≤ 50 MB, ≤ 10,000 files
- README.md describing the pipeline and how to deploy it from an empty subscription
- Terraform (azurerm) for at minimum: the governed hierarchy/foundation, the evidence
  store (Cosmos DB + immutable Blob), and enforcement in dry-run
- At least two report generators that read from the evidence store only, with real
  run history (live timers, not a burst of manual runs the night before)
- A CI gate (OPA/conftest or equivalent) on the repo's own Terraform, plus scheduled
  drift detection
- CONTROLS.md mapping every policy, collector, and gate rule to NIST CSF 2.0 categories

## The five dimensions (20% each)

### 1. Infrastructure-as-Code Quality
Staged root modules with separate state and output contracts; pinned azurerm; explicit
subscription targeting; discovery-first (data sources interrogate before activation
acts, and activation is conditional on the measured gap); hardened remote state.
Tier 0: terraform fmt/validate, tflint, checkov.

### 2. Control Implementation & Identity Design
Every remediation-effect assignment carries an identity block; ONE named user-assigned
remediation identity whose roles are a whitelist of its job (never Owner/Contributor);
collector and reporter as separate identities (SoD by role scopes); deliberate effects
(audit for new controls, deny where earned, escalation wired to a reviewed variable);
**at least one policy/control of your own beyond the starter**, correctly effected and
mapped.

### 3. Evidence Integrity & Traceability
WORM immutability on the reports container (show the failed-delete proof); idempotent,
runId + collectedAt-stamped collection; **reports read from the store ONLY** — any
report number reproducible by a stored query; framework crosswalk as data
(collect once).

### 4. Pipeline Operations
Run history that accumulates over time; the gate demonstrably blocks a non-compliant
plan (a closed test PR counts); enforcement in dry-run with a human at the approval
gate; drift detection in both directions (does reality match code; who is touching
reality).

### 5. Documentation & Control Mapping
Cold-readable README with deploy order; CONTROLS.md current with the code; blast-radius
notes on every enforcement policy; architecture doc showing stage flow and identity
boundaries; the why documented for non-obvious choices.

## Auto-fail triggers

Any one of these fails the submission regardless of score:

- Repository is private or inaccessible at grading time
- Active secrets detected (the design requires **zero** stored credentials)
- Real PII or production credentials in the repo
- An unmodified or trivially-modified fork of GRCEngClub/cgeaz or another published
  reference solution
- No README

## Before you submit

```bash
./self-check.sh
```

runs the mechanical half of this rubric locally (plans clean, fmt, gate green, WORM
config present, identity scopes, docs exist). It cannot judge your writing or your
run history — but if it's red, the grader will be too.
