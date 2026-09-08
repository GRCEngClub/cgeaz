# CGE-AZ Pipeline Starter

The lab and capstone repo for **CGE-AZ: Certified GRC Engineer — Azure Specialty**
(GRC Engineering Club Training Academy).

Over six labs you build a complete, automated GRC engineering pipeline in your own
Azure subscription:

```
1 Discovery → 2 Activation → 3 Evidence Store → 4 Reporting → 5 Narrative → 6 Enforcement ↺
   detect        enable         Cosmos + WORM      SAR/POA&M      AI digest     Azure Policy
   what runs     what's         Blob + collector   OSCAL SSP      (describes,   + remediation
                 missing        Functions          from the       never         identity
                                                   store ONLY     decides)
```

Automated, continuous, defensible, self-correcting. Most tooling reports findings —
this pipeline reports them **and fixes them**, and every fix shows up, documented, in
the next collection.

## Start here

1. **[docs/SETUP.md](docs/SETUP.md)** — one-time setup (free account, providers,
   regional quirks, cost guardrails). Do not skip it.
2. **labs/01-sandbox → labs/06-loop** — one lab per course domain, in order.
3. **[docs/VALIDATION-LOG.md](docs/VALIDATION-LOG.md)** — every lab was run end-to-end
   on a brand-new free account before shipping; this is what broke and how the labs
   route around it. If a step surprises you, look here first.

## Layout

```
stages/     one directory per pipeline stage — each a Terraform root module with its own state
functions/  the collector and report generators (Python, timer-triggered, managed identity)
labs/       the six lab guides + helper scripts
policy/     OPA/conftest rules that gate this repo's own changes
docs/       setup guide, architecture, control mappings, validation log
.github/    the compliance gate (PR) and drift detection (nightly)
```

## The rules the repo lives by

- **Discovers first, then acts.** Stage one changes nothing; activation closes only
  the measured gap.
- **Collect once.** One assessment document serves every framework through the
  mappings crosswalk.
- **Reports read from Cosmos only.** Every number is a fact with a receipt.
- **Zero keys.** Managed identity end to end; the evidence store disables shared keys
  entirely.
- **Automation acts; humans authorize.** Escalation (audit → dry-run → enforce) is a
  reviewed one-line diff.
- **Changes go through the repo, never the portal.** The drift detectors are watching —
  that's the point of them.

## Capstone

Your graded capstone is this pipeline, running in your subscription, from your fork,
with your own modifications. Rubric and submission checklist: `docs/RUBRIC.md`
(published with the course). Stage 5 is optional — extra credit if present, zero
penalty if absent.

---

*Built by the community, for the community · www.grcengclub.com*
