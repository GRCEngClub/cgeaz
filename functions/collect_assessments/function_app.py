"""CGE-AZ pipeline — Stage 3 collector.

Hourly timer -> managed identity -> Defender assessments API -> Cosmos.
One document per assessment per resource per run, keyed on a deterministic ID that
includes the run, so every sweep is kept and a retried write refreshes instead of
duplicating. Each sweep also writes one ledger entry to the `runs` container. Deliberately
boring: if you can read this file, you can defend this pipeline's data lineage.
"""

import datetime
import hashlib
import logging
import os
import re
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
RG_API_VERSION = "2021-04-01"
_RESOURCE_GROUP = re.compile(r"/resourcegroups/([^/]+)", re.IGNORECASE)


def resource_group_of(resource_id: str) -> str | None:
    """Resource group named in an ARM resource ID, or None for subscription-level resources."""
    match = _RESOURCE_GROUP.search(resource_id or "")
    return match.group(1) if match else None


def resource_group_owners(token: str, subscription_id: str) -> dict[str, str]:
    """Resource group name (lower-cased) -> its `owner` tag. Groups without the tag are omitted.

    Reports read only from the evidence store, so ownership has to be captured here, at
    collection time, and stamped on each document. Security Reader already includes
    Microsoft.Resources/subscriptions/resourceGroups/read: no new permission is needed.
    """
    owners: dict[str, str] = {}
    url = f"{ARM}/subscriptions/{subscription_id}/resourcegroups?api-version={RG_API_VERSION}"
    while url:
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=60)
        resp.raise_for_status()
        payload = resp.json()
        for group in payload.get("value", []):
            owner = (group.get("tags") or {}).get("owner")
            if owner:
                owners[group["name"].lower()] = owner
        url = payload.get("nextLink")
    return owners


def build_document(
    assessment: dict,
    subscription_id: str,
    run_id: str,
    collected_at: str,
    owners: dict[str, str] | None = None,
    default_owner: str | None = None,
) -> dict:
    """Map one Defender assessment to its evidence document. Pure (no I/O) so it is unit-tested."""
    props = assessment.get("properties") or {}
    details = props.get("resourceDetails") or {}
    status = props.get("status") or {}
    metadata = props.get("metadata") or {}
    resource_id = details.get("Id") or details.get("id", "")
    # Deterministic ID: assessment + resource + run. A retried write of the same sweep upserts
    # the same document; the next sweep gets new documents, so history is never overwritten.
    # Ownership is deliberately not part of it: a re-tag must not fork a record.
    doc_id = hashlib.sha256(f"{assessment['name']}|{resource_id}|{run_id}".encode()).hexdigest()[:32]

    resource_group = resource_group_of(resource_id)
    if resource_group:
        owner = (owners or {}).get(resource_group.lower())
        # A group with no owner tag stays visibly unassigned: that is a tagging gap to fix,
        # not something to paper over with a default.
        owner_source = "resource-group-tag" if owner else "unassigned"
    elif default_owner:
        owner, owner_source = default_owner, "subscription-default"
    else:
        owner, owner_source = None, "unassigned"

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
        "resourceGroup": resource_group,
        "owner": owner,
        "ownerSource": owner_source,
        "collectedAt": collected_at,
        "runId": run_id,
    }


def build_run_record(
    run_id: str, subscription_id: str, collected_at: str, documents: int, unhealthy: int,
    by_severity: dict[str, int], trigger: str,
) -> dict:
    """Ledger entry for one sweep: what ran, when, how it was started, and what it found."""
    return {
        "id": run_id,
        "runId": run_id,
        "subscriptionId": subscription_id,
        "collectedAt": collected_at,
        "trigger": trigger,
        "documents": documents,
        "unhealthy": unhealthy,
        "unhealthyBySeverity": by_severity,
    }


def _collect(trigger: str) -> dict:
    subscription_id = os.environ["SUBSCRIPTION_ID"]
    cosmos_endpoint = os.environ["COSMOS_ENDPOINT"]
    database = os.environ["COSMOS_DATABASE"]

    # DefaultAzureCredential resolves to the Function App's managed identity in Azure
    # (and to your `az login` session when run locally). No keys, anywhere.
    credential = DefaultAzureCredential()
    token = credential.get_token(f"{ARM}/.default").token

    run_id = str(uuid.uuid4())
    collected_at = datetime.datetime.now(datetime.timezone.utc).isoformat()

    db = CosmosClient(cosmos_endpoint, credential).get_database_client(database)
    container = db.get_container_client("assessments")
    runs = db.get_container_client("runs")

    try:
        owners = resource_group_owners(token, subscription_id)
    except requests.RequestException:
        # Ownership is enrichment. Losing it must not cost the sweep its evidence, but it must
        # not be silent either: every affected document is stamped ownerSource=unassigned.
        logging.exception("could not read resource group tags; findings will be unassigned")
        owners = {}
    # Subscription-level findings have no resource group to carry a tag.
    default_owner = os.environ.get("DEFAULT_OWNER")

    url = (
        f"{ARM}/subscriptions/{subscription_id}"
        f"/providers/Microsoft.Security/assessments?api-version={API_VERSION}&$expand={EXPAND}"
    )
    written = 0
    unhealthy = 0
    by_severity: dict[str, int] = {}
    while url:
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=60)
        resp.raise_for_status()
        payload = resp.json()

        for assessment in payload.get("value", []):
            doc = build_document(assessment, subscription_id, run_id, collected_at, owners, default_owner)
            container.upsert_item(doc)
            written += 1
            if doc["status"] == "Unhealthy":
                unhealthy += 1
                severity = doc["severity"] or "Medium"
                by_severity[severity] = by_severity.get(severity, 0) + 1

        url = payload.get("nextLink")

    # Written last: a run with a ledger entry is a run whose documents are all present.
    runs.upsert_item(build_run_record(run_id, subscription_id, collected_at, written, unhealthy, by_severity, trigger))
    logging.info("collection run %s complete: %d documents", run_id, written)
    return {"runId": run_id, "written": written, "collectedAt": collected_at}


@app.timer_trigger(schedule="0 0 * * * *", arg_name="timer", run_on_startup=False)
def collect_scheduled(timer: func.TimerRequest) -> None:
    """Sweep at the top of every hour (UTC)."""
    _collect("timer")


@app.route(route="collect", auth_level=func.AuthLevel.FUNCTION)
def collect_now(req: func.HttpRequest) -> func.HttpResponse:
    """Manual trigger for labs and demos: hit the endpoint, get the run summary."""
    result = _collect("manual")
    return func.HttpResponse(
        f"run {result['runId']}: {result['written']} documents at {result['collectedAt']}\n",
        status_code=200,
    )
