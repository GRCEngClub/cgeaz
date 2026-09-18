"""CGE-AZ pipeline — Stage 3 collector.

Timer fires every 4 hours -> managed identity -> Defender assessments API -> Cosmos.
One document per assessment per run, upserted on a deterministic ID so re-runs
refresh instead of duplicate. Deliberately boring: if you can read this file,
you can defend this pipeline's data lineage.
"""

import datetime
import hashlib
import logging
import os
import uuid

import azure.functions as func
import requests
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

app = func.FunctionApp()

ARM = "https://management.azure.com"
API_VERSION = "2021-06-01"
# The list call returns no `metadata`, and so no severity, unless it is asked to expand it.
EXPAND = "metadata"


def build_document(assessment: dict, subscription_id: str, run_id: str, collected_at: str) -> dict:
    """Map one Defender assessment to its evidence document. Pure (no I/O) so it is unit-tested."""
    props = assessment.get("properties") or {}
    details = props.get("resourceDetails") or {}
    status = props.get("status") or {}
    metadata = props.get("metadata") or {}
    resource_id = details.get("Id") or details.get("id", "")
    # Deterministic ID: same assessment+resource upserts, never duplicates.
    doc_id = hashlib.sha256(f"{assessment['name']}|{resource_id}".encode()).hexdigest()[:32]
    return {
        "id": doc_id,
        "subscriptionId": subscription_id,
        "assessmentId": assessment["name"],
        "displayName": props.get("displayName"),
        "status": status.get("code"),
        "statusCause": status.get("cause"),
        "severity": metadata.get("severity"),
        "categories": metadata.get("categories"),
        "resourceId": resource_id,
        "collectedAt": collected_at,
        "runId": run_id,
    }


def _collect() -> dict:
    subscription_id = os.environ["SUBSCRIPTION_ID"]
    cosmos_endpoint = os.environ["COSMOS_ENDPOINT"]
    database = os.environ["COSMOS_DATABASE"]

    # DefaultAzureCredential resolves to the Function App's managed identity in Azure
    # (and to your `az login` session when run locally). No keys, anywhere.
    credential = DefaultAzureCredential()
    token = credential.get_token(f"{ARM}/.default").token

    run_id = str(uuid.uuid4())
    collected_at = datetime.datetime.now(datetime.timezone.utc).isoformat()

    container = (
        CosmosClient(cosmos_endpoint, credential)
        .get_database_client(database)
        .get_container_client("assessments")
    )

    url = (
        f"{ARM}/subscriptions/{subscription_id}"
        f"/providers/Microsoft.Security/assessments?api-version={API_VERSION}&$expand={EXPAND}"
    )
    written = 0
    while url:
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=60)
        resp.raise_for_status()
        payload = resp.json()

        for assessment in payload.get("value", []):
            container.upsert_item(build_document(assessment, subscription_id, run_id, collected_at))
            written += 1

        url = payload.get("nextLink")

    logging.info("collection run %s complete: %d documents", run_id, written)
    return {"runId": run_id, "written": written, "collectedAt": collected_at}


@app.timer_trigger(schedule="0 0 */4 * * *", arg_name="timer", run_on_startup=False)
def collect_nightly(timer: func.TimerRequest) -> None:
    """Sweep every 4 hours (00/04/08/12/16/20 UTC)."""
    _collect()


@app.route(route="collect", auth_level=func.AuthLevel.FUNCTION)
def collect_now(req: func.HttpRequest) -> func.HttpResponse:
    """Manual trigger for labs and demos: hit the endpoint, get the run summary."""
    result = _collect()
    return func.HttpResponse(
        f"run {result['runId']}: {result['written']} documents at {result['collectedAt']}\n",
        status_code=200,
    )
