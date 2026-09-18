"""Unit tests for the stage 3 collector. No network, no Azure: every dependency is faked."""

import importlib.util
import pathlib
import types

import pytest

SRC = pathlib.Path(__file__).resolve().parents[2] / "functions" / "collect_assessments" / "function_app.py"
spec = importlib.util.spec_from_file_location("collector", SRC)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

SUB = "00000000-0000-0000-0000-000000000000"
RES_A = f"/subscriptions/{SUB}/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/a"
RES_B = f"/subscriptions/{SUB}/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/b"


def assessment(name="rule-1", resource=RES_A, **props):
    base = {
        "displayName": "Storage accounts should prevent shared key access",
        "status": {"code": "Unhealthy", "cause": "x"},
        "resourceDetails": {"Id": resource},
    }
    base.update(props)
    return {"name": name, "properties": base}


def test_a_retried_write_upserts_but_the_next_sweep_keeps_history():
    first = collector.build_document(assessment(), SUB, "run-1", "2026-09-18T00:00:00+00:00")
    retry = collector.build_document(assessment(), SUB, "run-1", "2026-09-18T00:00:00+00:00")
    later = collector.build_document(assessment(), SUB, "run-2", "2026-09-19T00:00:00+00:00")
    assert first["id"] == retry["id"], "a retried write of the same sweep must not duplicate"
    assert first["id"] != later["id"], "the next sweep must not overwrite this one"


def test_id_differs_per_resource_and_per_rule():
    a = collector.build_document(assessment(resource=RES_A), SUB, "r", "t")
    b = collector.build_document(assessment(resource=RES_B), SUB, "r", "t")
    c = collector.build_document(assessment(name="rule-2", resource=RES_A), SUB, "r", "t")
    assert len({a["id"], b["id"], c["id"]}) == 3


def test_every_document_carries_lineage():
    doc = collector.build_document(assessment(), SUB, "run-9", "2026-09-18T20:11:38+00:00")
    assert doc["runId"] == "run-9"
    assert doc["collectedAt"] == "2026-09-18T20:11:38+00:00"
    assert doc["subscriptionId"] == SUB
    assert doc["assessmentId"] == "rule-1"
    assert doc["status"] == "Unhealthy"


def test_severity_and_categories_come_from_expanded_metadata():
    doc = collector.build_document(
        assessment(metadata={"severity": "High", "categories": ["Data"]}), SUB, "r", "t"
    )
    assert doc["severity"] == "High"
    assert doc["categories"] == ["Data"]


@pytest.mark.parametrize("props", [{}, {"metadata": None}, {"metadata": {}}])
def test_missing_or_null_metadata_never_crashes(props):
    doc = collector.build_document(assessment(**props), SUB, "r", "t")
    assert doc["severity"] is None


def test_resource_id_accepts_either_key_casing():
    lower = assessment()
    lower["properties"]["resourceDetails"] = {"id": RES_A}
    assert collector.build_document(lower, SUB, "r", "t")["resourceId"] == RES_A
    assert collector.build_document(assessment(), SUB, "r", "t")["resourceId"] == RES_A


TAGGED_RG = f"/subscriptions/{SUB}/resourceGroups/RG-Tagged/providers/Microsoft.Storage/storageAccounts/a"
BARE_RG = f"/subscriptions/{SUB}/resourcegroups/rg-bare/providers/Microsoft.Storage/storageAccounts/b"
SUB_LEVEL = f"/subscriptions/{SUB}"
OWNERS = {"rg-tagged": "owner@example.com"}


def test_resource_group_is_read_from_the_id_in_either_casing():
    assert collector.resource_group_of(TAGGED_RG) == "RG-Tagged"
    assert collector.resource_group_of(BARE_RG) == "rg-bare"
    assert collector.resource_group_of(SUB_LEVEL) is None
    assert collector.resource_group_of("") is None


def test_owner_comes_from_the_resource_group_tag_whatever_the_casing():
    doc = collector.build_document(assessment(resource=TAGGED_RG), SUB, "r", "t", owners=OWNERS)
    assert (doc["owner"], doc["ownerSource"], doc["resourceGroup"]) == (
        "owner@example.com", "resource-group-tag", "RG-Tagged")


def test_untagged_group_stays_visibly_unassigned_even_with_a_default():
    doc = collector.build_document(
        assessment(resource=BARE_RG), SUB, "r", "t", owners=OWNERS, default_owner="platform@example.com")
    assert doc["owner"] is None and doc["ownerSource"] == "unassigned", "a tagging gap must show, not be papered over"


def test_subscription_level_finding_gets_the_platform_owner():
    doc = collector.build_document(
        assessment(resource=SUB_LEVEL), SUB, "r", "t", owners=OWNERS, default_owner="platform@example.com")
    assert (doc["owner"], doc["ownerSource"], doc["resourceGroup"]) == (
        "platform@example.com", "subscription-default", None)


def test_subscription_level_finding_without_a_default_is_unassigned():
    doc = collector.build_document(assessment(resource=SUB_LEVEL), SUB, "r", "t")
    assert doc["owner"] is None and doc["ownerSource"] == "unassigned"


def test_ownership_never_changes_the_document_id():
    untagged = collector.build_document(assessment(resource=TAGGED_RG), SUB, "r", "t", owners={})
    tagged = collector.build_document(assessment(resource=TAGGED_RG), SUB, "r", "t", owners=OWNERS)
    assert untagged["id"] == tagged["id"], "re-tagging must refresh the record, not create a second one"


class FakeContainer:
    def __init__(self):
        self.items = []

    def upsert_item(self, item):
        self.items.append(item)


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self.payload


def wire(monkeypatch, pages, rg_error=None):
    """Fake every Azure dependency. Returns (cosmos container, every URL requested)."""
    monkeypatch.setenv("SUBSCRIPTION_ID", SUB)
    monkeypatch.setenv("COSMOS_ENDPOINT", "https://example.invalid:443/")
    monkeypatch.setenv("COSMOS_DATABASE", "grc")
    monkeypatch.setenv("DEFAULT_OWNER", "platform@example.com")

    container, runs, urls, served = FakeContainer(), FakeContainer(), [], {"assessment_pages": 0}

    def fake_get(url, headers, timeout):
        urls.append(url)
        assert headers["Authorization"] == "Bearer fake-token"
        if "/resourcegroups" in url:
            if rg_error:
                raise rg_error
            return FakeResponse({"value": [{"name": "RG-Tagged", "tags": {"owner": "owner@example.com"}}, {"name": "rg-bare"}]})
        served["assessment_pages"] += 1
        return FakeResponse(pages[served["assessment_pages"] - 1])

    fake_client = types.SimpleNamespace(
        get_database_client=lambda _: types.SimpleNamespace(
            get_container_client=lambda name: {"assessments": container, "runs": runs}[name]
        )
    )
    monkeypatch.setattr(collector.requests, "get", fake_get)
    monkeypatch.setattr(collector, "CosmosClient", lambda *a, **k: fake_client)
    monkeypatch.setattr(
        collector,
        "DefaultAzureCredential",
        lambda: types.SimpleNamespace(get_token=lambda scope: types.SimpleNamespace(token="fake-token")),
    )
    container.runs = runs
    return container, urls


def test_collect_requests_expand_follows_next_link_and_stamps_owners(monkeypatch):
    pages = {
        0: {"value": [assessment(name="r1", resource=TAGGED_RG), assessment(name="r2", resource=SUB_LEVEL)],
            "nextLink": "https://next-page"},
        1: {"value": [assessment(name="r3", resource=BARE_RG)]},
    }
    container, urls = wire(monkeypatch, pages)

    result = collector._collect("manual")

    assessment_urls = [u for u in urls if "/resourcegroups" not in u]
    assert "$expand=metadata" in assessment_urls[0], "without expand the API returns no severity"
    assert assessment_urls[1] == "https://next-page", "the collector must walk every page"
    assert result["written"] == 3 == len(container.items)
    assert {d["runId"] for d in container.items} == {result["runId"]}, "one run id per sweep"
    by_name = {d["assessmentId"]: d for d in container.items}
    assert by_name["r1"]["owner"] == "owner@example.com"
    assert by_name["r2"]["owner"] == "platform@example.com"
    assert by_name["r3"]["owner"] is None and by_name["r3"]["ownerSource"] == "unassigned"
    (ledger,) = container.runs.items
    assert ledger["runId"] == result["runId"] and ledger["documents"] == 3
    assert ledger["unhealthy"] == 3 and ledger["trigger"] == "manual"
    assert ledger["collectedAt"] == result["collectedAt"]


def test_a_failed_tag_read_costs_the_sweep_nothing_but_is_not_silent(monkeypatch, caplog):
    pages = {0: {"value": [assessment(name="r1", resource=TAGGED_RG)]}}
    container, _ = wire(monkeypatch, pages, rg_error=collector.requests.RequestException("403"))

    result = collector._collect("manual")

    assert result["written"] == 1, "the evidence itself must still land"
    assert container.items[0]["ownerSource"] == "unassigned"
    assert "could not read resource group tags" in caplog.text, "degrading silently would hide a permissions fault"
