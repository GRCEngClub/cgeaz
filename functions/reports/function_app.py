"""CGE-AZ pipeline — Stage 4 report generators.

Reports read from Cosmos ONLY — never from live services. Every number in every
artifact resolves to a stored, timestamped document. A report that reads live data
is a report whose numbers can't be reproduced tomorrow; a report that reads the
store is a fact with a receipt.

Generators here: POA&M (xlsx + json, daily) and SAR (markdown, weekly), both with
HTTP triggers for labs and demos.
"""

import datetime
import io
import json
import logging
import os
from collections import Counter

import azure.functions as func
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from openpyxl import Workbook

app = func.FunctionApp()

# Severity-based SLAs: a POA&M is a plan, not a list.
SLA_DAYS = {"High": 30, "Medium": 90, "Low": 180}


def _clients():
    credential = DefaultAzureCredential()
    cosmos = (
        CosmosClient(os.environ["COSMOS_ENDPOINT"], credential)
        .get_database_client(os.environ["COSMOS_DATABASE"])
        .get_container_client("assessments")
    )
    blobs = BlobServiceClient(
        account_url=os.environ["REPORTS_ACCOUNT_URL"], credential=credential
    ).get_container_client(os.environ["REPORTS_CONTAINER"])
    return cosmos, blobs


def _latest_run(cosmos):
    """Pin the report to a specific collection sweep — a statement about a known moment."""
    rows = list(
        cosmos.query_items(
            "SELECT TOP 1 c.runId, c.collectedAt FROM c ORDER BY c.collectedAt DESC",
            enable_cross_partition_query=True,
        )
    )
    return (rows[0]["runId"], rows[0]["collectedAt"]) if rows else (None, None)


def _unhealthy(cosmos, run_id):
    return list(
        cosmos.query_items(
            "SELECT * FROM c WHERE c.runId = @run AND c.status = 'Unhealthy'",
            parameters=[{"name": "@run", "value": run_id}],
            enable_cross_partition_query=True,
        )
    )


def _dated_path(prefix: str, ext: str) -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    return f"{prefix}/{now:%Y/%m}/{prefix}-{now:%Y-%m-%d}.{ext}"


def generate_poam() -> dict:
    cosmos, blobs = _clients()
    run_id, collected_at = _latest_run(cosmos)
    findings = _unhealthy(cosmos, run_id) if run_id else []
    today = datetime.date.today()

    wb = Workbook()
    ws = wb.active
    ws.title = "POA&M"
    ws.append(
        ["POA&M ID", "Weakness", "Affected Resource", "Severity",
         "Detected (run)", "Scheduled Completion", "Owner", "Status"]
    )
    rows = []
    for i, f in enumerate(sorted(findings, key=lambda x: x.get("severity") or ""), 1):
        severity = f.get("severity") or "Medium"
        due = today + datetime.timedelta(days=SLA_DAYS.get(severity, 90))
        row = {
            "poamId": f"POAM-{today:%Y%m%d}-{i:03d}",
            "weakness": f.get("displayName"),
            "resourceId": f.get("resourceId"),
            "severity": severity,
            "detectedRun": run_id,
            "scheduledCompletion": due.isoformat(),
            "owner": "resource-group owner tag",  # resolved during Domain 5's lab extension
            "status": "Open",
        }
        rows.append(row)
        ws.append(list(row.values()))

    xlsx = io.BytesIO()
    wb.save(xlsx)
    xlsx_path = _dated_path("poam", "xlsx")
    json_path = _dated_path("poam", "json")
    blobs.upload_blob(xlsx_path, xlsx.getvalue(), overwrite=False)
    blobs.upload_blob(
        json_path,
        json.dumps({"runId": run_id, "collectedAt": collected_at, "items": rows}, indent=2),
        overwrite=False,
    )
    logging.info("POA&M: %d items -> %s", len(rows), xlsx_path)
    return {"items": len(rows), "runId": run_id, "xlsx": xlsx_path, "json": json_path}


def generate_sar() -> dict:
    cosmos, blobs = _clients()
    run_id, collected_at = _latest_run(cosmos)
    findings = _unhealthy(cosmos, run_id) if run_id else []
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
    for f in sorted(findings, key=lambda x: x.get("severity") or ""):
        lines += [
            f"### {f.get('displayName')}",
            f"- Severity: {f.get('severity')}",
            f"- Resource: `{f.get('resourceId')}`",
            f"- Assessment ID: `{f.get('assessmentId')}` (trace: query the assessments container)",
            "",
        ]

    path = _dated_path("sar", "md")
    blobs.upload_blob(path, "\n".join(lines), overwrite=False)
    logging.info("SAR: %d findings -> %s", len(findings), path)
    return {"findings": len(findings), "runId": run_id, "path": path}


@app.timer_trigger(schedule="0 0 6 * * *", arg_name="timer", run_on_startup=False)
def poam_daily(timer: func.TimerRequest) -> None:
    generate_poam()


@app.timer_trigger(schedule="0 0 7 * * 1", arg_name="timer", run_on_startup=False)
def sar_weekly(timer: func.TimerRequest) -> None:
    generate_sar()


@app.route(route="poam", auth_level=func.AuthLevel.FUNCTION)
def poam_now(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(generate_poam()) + "\n", status_code=200)


@app.route(route="sar", auth_level=func.AuthLevel.FUNCTION)
def sar_now(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(generate_sar()) + "\n", status_code=200)
