"""CGE-AZ pipeline — Stage 4 report generators.

Reports read from Cosmos ONLY — never from live services. Every number in every
artifact resolves to a stored, timestamped document. A report that reads live data
is a report whose numbers can't be reproduced tomorrow; a report that reads the
store is a fact with a receipt.

Generators here: POA&M (xlsx + json) and SAR (markdown), each cut from one recorded collection run, both with
HTTP triggers for labs and demos.
"""

import datetime
import io
import json
import logging
import os
from collections import Counter

import azure.functions as func
from azure.core.exceptions import ResourceExistsError
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from openpyxl import Workbook

app = func.FunctionApp()

# Severity-based SLAs: a POA&M is a plan, not a list.
SLA_DAYS = {"High": 30, "Medium": 90, "Low": 180}
SEVERITY_RANK = {"High": 0, "Medium": 1, "Low": 2}


def _severity(finding: dict) -> str:
    """A finding with no severity is treated as Medium (90-day SLA): a deliberate, visible default."""
    return finding.get("severity") or "Medium"


def _ordered(findings: list) -> list:
    """Severity first, then a stable tie-break, so the same evidence always yields the same POA&M IDs.

    Sorting severity as text would put Low before Medium, and Cosmos does not guarantee query
    order, so an ID could otherwise land on a different finding when a report is regenerated.
    """
    return sorted(
        findings,
        key=lambda f: (SEVERITY_RANK.get(_severity(f), 3), str(f.get("displayName")), str(f.get("resourceId"))),
    )


def _clients():
    credential = DefaultAzureCredential()
    db = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential).get_database_client(os.environ["COSMOS_DATABASE"])
    cosmos = tuple(db.get_container_client(name) for name in ("assessments", "runs", "mappings"))
    blobs = BlobServiceClient(
        account_url=os.environ["REPORTS_ACCOUNT_URL"], credential=credential
    ).get_container_client(os.environ["REPORTS_CONTAINER"])
    return cosmos, blobs


def _latest_run(stores):
    """Pin the report to the newest recorded sweep from the run ledger: a statement about a known moment."""
    runs = stores[1]
    rows = list(
        runs.query_items(
            "SELECT TOP 1 c.runId, c.collectedAt FROM c ORDER BY c.collectedAt DESC",
            enable_cross_partition_query=True,
        )
    )
    return (rows[0]["runId"], rows[0]["collectedAt"]) if rows else (None, None)


def _crosswalk(stores) -> dict:
    """assessmentId -> {framework: [controls]}, read from the stored crosswalk: one collection, any framework."""
    table: dict = {}
    for row in stores[2].query_items(
        "SELECT c.assessmentId, c.frameworkId, c.controls FROM c", enable_cross_partition_query=True
    ):
        table.setdefault(row["assessmentId"], {})[row["frameworkId"]] = row["controls"]
    return table


def _unhealthy(stores, run_id):
    assessments = stores[0]
    return list(
        assessments.query_items(
            "SELECT * FROM c WHERE c.runId = @run AND c.status = 'Unhealthy'",
            parameters=[{"name": "@run", "value": run_id}],
            enable_cross_partition_query=True,
        )
    )


def _run_path(prefix: str, ext: str, collected_at: str) -> str:
    """Named by the sweep it reports on, so a report is reproducible and one run yields one file."""
    at = datetime.datetime.fromisoformat(collected_at)
    return f"{prefix}/{at:%Y/%m}/{prefix}-{at:%Y-%m-%dT%H%MZ}.{ext}"


def _write_once(blobs, path: str, data) -> bool:
    """Immutable upload. False if this run's report already exists: same run, same report."""
    try:
        blobs.upload_blob(path, data, overwrite=False)
        return True
    except ResourceExistsError:
        logging.info("%s already stored; nothing to do", path)
        return False


def generate_poam() -> dict:
    cosmos, blobs = _clients()
    run_id, collected_at = _latest_run(cosmos)
    if not run_id:
        # No recorded sweep yet: an empty report would be a claim about nothing.
        logging.warning("POA&M skipped: the run ledger is empty")
        return {"items": 0, "runId": None, "skipped": "no recorded collection run"}
    findings = _unhealthy(cosmos, run_id)
    crosswalk = _crosswalk(cosmos)
    # Dates come from the sweep, not the wall clock, so regenerating a report gives the same report.
    sweep = datetime.datetime.fromisoformat(collected_at)
    today = sweep.date()

    wb = Workbook()
    ws = wb.active
    ws.title = "POA&M"
    ws.append(
        ["POA&M ID", "Weakness", "Affected Resource", "Severity",
         "Detected (run)", "Scheduled Completion", "Owner", "Status", "NIST 800-53 Rev.5", "CSF 2.0"]
    )
    rows = []
    for i, f in enumerate(_ordered(findings), 1):
        severity = _severity(f)
        due = today + datetime.timedelta(days=SLA_DAYS.get(severity, 90))
        row = {
            "poamId": f"POAM-{sweep:%Y%m%dT%H%M}-{i:03d}",
            "weakness": f.get("displayName"),
            "resourceId": f.get("resourceId"),
            "severity": severity,
            "detectedRun": run_id,
            "scheduledCompletion": due.isoformat(),
            # Stamped on the document at collection time; reports never call live APIs.
            "owner": f.get("owner") or "unassigned",
            "status": "Open",
            "nist80053r5": ", ".join(crosswalk.get(f.get("assessmentId"), {}).get("nist-800-53-r5", [])),
            "csf2": ", ".join(crosswalk.get(f.get("assessmentId"), {}).get("nist-csf-2.0", [])),
        }
        rows.append(row)
        ws.append(list(row.values()))

    xlsx = io.BytesIO()
    wb.save(xlsx)
    xlsx_path = _run_path("poam", "xlsx", collected_at)
    json_path = _run_path("poam", "json", collected_at)
    _write_once(blobs, xlsx_path, xlsx.getvalue())
    _write_once(
        blobs,
        json_path,
        json.dumps({"runId": run_id, "collectedAt": collected_at, "items": rows}, indent=2),
    )
    logging.info("POA&M: %d items -> %s", len(rows), xlsx_path)
    return {"items": len(rows), "runId": run_id, "xlsx": xlsx_path, "json": json_path}


def generate_sar() -> dict:
    cosmos, blobs = _clients()
    run_id, collected_at = _latest_run(cosmos)
    if not run_id:
        logging.warning("SAR skipped: the run ledger is empty")
        return {"findings": 0, "runId": None, "skipped": "no recorded collection run"}
    findings = _unhealthy(cosmos, run_id)
    by_severity = Counter(f.get("severity") or "Unknown" for f in findings)

    lines = [
        "# Security Assessment Report (SAR)",
        "",
        f"- **Collection run:** `{run_id}`",
        f"- **Collected at:** {collected_at}",
        f"- **Open findings:** {len(findings)}",
        f"- **By severity:** " + (", ".join(f"{k}: {v}" for k, v in sorted(by_severity.items())) or "none"),
        "",
        "## Findings",
        "",
    ]
    for f in _ordered(findings):
        lines += [
            f"### {f.get('displayName')}",
            f"- Severity: {f.get('severity')}",
            f"- Owner: {f.get('owner') or 'unassigned'}",
            f"- Resource: `{f.get('resourceId')}`",
            f"- Assessment ID: `{f.get('assessmentId')}` (trace: query the assessments container)",
            "",
        ]

    path = _run_path("sar", "md", collected_at)
    _write_once(blobs, path, "\n".join(lines))
    logging.info("SAR: %d findings -> %s", len(findings), path)
    return {"findings": len(findings), "runId": run_id, "path": path}


@app.timer_trigger(schedule="0 10 * * * *", arg_name="timer", run_on_startup=False)
def poam_scheduled(timer: func.TimerRequest) -> None:
    """Ten minutes after each sweep, so the report always has a fresh run to cut from."""
    generate_poam()


@app.timer_trigger(schedule="0 20 * * * *", arg_name="timer", run_on_startup=False)
def sar_scheduled(timer: func.TimerRequest) -> None:
    generate_sar()


@app.route(route="poam", auth_level=func.AuthLevel.FUNCTION)
def poam_now(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(generate_poam()) + "\n", status_code=200)


@app.route(route="sar", auth_level=func.AuthLevel.FUNCTION)
def sar_now(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(generate_sar()) + "\n", status_code=200)
