# Decisions

The choices that shaped this build, what was rejected, and what each costs.

## Every sweep is kept (per-run document IDs and a run ledger)
The starter keyed a document on assessment and resource, so each sweep overwrote the last. That made a report
untraceable as soon as the next sweep ran: its `runId` matched nothing. The ID now includes the run, and each
sweep writes one ledger entry last. **Cost:** one document per assessment per run (about 100 an hour,
serverless Cosmos, still pennies). **Rejected:** keeping a `latest` copy alongside history; a second copy is a
second source of truth.

## Reports are named after the run and written once
A report is a statement about one sweep, so it is named for that sweep (`poam-2026-09-19T0000Z.json`) rather
than for the calendar day. One run gives one immutable file, and asking for the same run again is a no-op
instead of a `BlobAlreadyExists` failure. With no recorded run a report is skipped, not written empty: an empty
report would be a claim about nothing.

## Dates in a report come from the sweep, not the wall clock
Scheduled completion and POA&M IDs derive from the run's `collectedAt`, so regenerating a report from the same
run yields the same report.

## Timers run hourly
The rubric grades pipeline operations, and a daily or weekly schedule cannot show a run history inside the
grading window. The same functions run on a compressed cadence, and that compression is stated in the docs
rather than hidden. Restoring daily and weekly is a one-line schedule change per function.

## The crosswalk is data
Mapping an assessment to controls lives in `mappings`, seeded from `labs/04-evidence/csf-mappings.json`.
The POA&M reads it from the store. Adding a framework is adding rows. **Limit:** the mapping is my judgement of
each assessment's intent, not an authoritative catalogue, and it says so in [CONTROLS.md](CONTROLS.md).

## Drift opens one issue per stage
A nightly plan that opened a new issue every night would bury the signal. The workflow keeps one open issue per
stage, comments while the drift persists, and closes it when the plan is clean. The plan exit code is captured
without a pipe: piping through `tee` lets `tee`'s status replace terraform's, and drift (exit 2) is then lost.

## Two detectors for change
`terraform plan` answers whether reality matches the code. The activity-log tripwire answers who has been
changing reality. Each misses what the other sees: a change that leaves the plan clean (a tag on an unmanaged
resource) or a change that is made and reverted between plans.

## Shared keys stay on for the Functions scratch accounts only
The Consumption runtime needs key auth on its own scratch storage for zip deploys and timers. The evidence
account and the Terraform state account have shared keys disabled. checkov's two findings for the scratch
accounts are skipped with that reason in `.checkov.yaml`.

## Skips in `.checkov.yaml` are decisions
Private endpoints, customer-managed keys, zone redundancy and replication are production upgrades that cost
money in a lab subscription and do not change the identity, WORM and least-privilege design. Each skip is
listed with its reason.

## Deploying the Function code
`az functionapp deployment source config-zip --build-remote` removes and re-adds `ENABLE_ORYX_BUILD` on every
deploy, which Terraform then saw as drift. The setting is in `ignore_changes` on both apps.

## The remediation identity's Storage Account Contributor role is broader than the job
The built-in role can also list and regenerate account keys. A custom role limited to writing storage accounts
would be narrower. It is kept as a built-in role for clarity and recorded here as a known limit.
