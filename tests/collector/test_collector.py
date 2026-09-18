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


def test_id_is_deterministic_across_runs():
    first = collector.build_document(assessment(), SUB, "run-1", "2026-09-18T00:00:00+00:00")
    later = collector.build_document(assessment(), SUB, "run-2", "2026-09-19T00:00:00+00:00")
    assert first["id"] == later["id"], "a re-run must upsert the same document, never duplicate it"


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


class FakeContainer:
    def __init__(self):
        self.items = []

    def upsert_item(self, item):
        self.items.append(item)


def test_collect_requests_expand_and_follows_next_link(monkeypatch):
    monkeypatch.setenv("SUBSCRIPTION_ID", SUB)
    monkeypatch.setenv("COSMOS_ENDPOINT", "https://example.invalid:443/")
    monkeypatch.setenv("COSMOS_DATABASE", "grc")

    container = FakeContainer()
    urls = []
    pages = {
        0: {"value": [assessment(name="r1"), assessment(name="r2")], "nextLink": "https://next-page"},
        1: {"value": [assessment(name="r3")]},
    }

    class FakeResponse:
        def __init__(self, payload):
            self.payload = payload

        def raise_for_status(self):
            pass

        def json(self):
            return self.payload

    def fake_get(url, headers, timeout):
        urls.append(url)
        assert headers["Authorization"] == "Bearer fake-token"
        return FakeResponse(pages[len(urls) - 1])

    fake_client = types.SimpleNamespace(
        get_database_client=lambda _: types.SimpleNamespace(get_container_client=lambda _: container)
    )
    monkeypatch.setattr(collector.requests, "get", fake_get)
    monkeypatch.setattr(collector, "CosmosClient", lambda *a, **k: fake_client)
    monkeypatch.setattr(
        collector,
        "DefaultAzureCredential",
        lambda: types.SimpleNamespace(get_token=lambda scope: types.SimpleNamespace(token="fake-token")),
    )

    result = collector._collect()

    assert "$expand=metadata" in urls[0], "without expand the API returns no severity"
    assert urls[1] == "https://next-page", "the collector must walk every page"
    assert result["written"] == 3 == len(container.items)
    assert {d["runId"] for d in container.items} == {result["runId"]}, "one run id per sweep"
