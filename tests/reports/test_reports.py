"""Unit tests for the stage 4 report generators. No network, no Azure: Cosmos and Blob are faked."""

import datetime
import importlib.util
import io
import json
import pathlib

import openpyxl

SRC = pathlib.Path(__file__).resolve().parents[2] / "functions" / "reports" / "function_app.py"
spec = importlib.util.spec_from_file_location("reports", SRC)
reports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)

RG = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg/providers/Microsoft.Storage/storageAccounts/"


def finding(name, severity, owner, resource="a"):
    return {"displayName": name, "severity": severity, "owner": owner, "resourceId": RG + resource}


class FakeCosmos:
    def __init__(self, findings, run=("run-1", "2026-09-18T20:42:05+00:00")):
        self.findings, self.run = findings, run

    def query_items(self, query, parameters=None, enable_cross_partition_query=False):
        if "TOP 1" in query:
            return iter([{"runId": self.run[0], "collectedAt": self.run[1]}] if self.run else [])
        return iter(self.findings)


class FakeBlobs:
    def __init__(self):
        self.uploads = []

    def upload_blob(self, name, data, overwrite=False):
        self.uploads.append((name, data, overwrite))

    def get(self, suffix):
        return next(data for name, data, _ in self.uploads if name.endswith(suffix))


def generate(monkeypatch, findings, run=("run-1", "2026-09-18T20:42:05+00:00"), kind="poam"):
    blobs = FakeBlobs()
    monkeypatch.setattr(reports, "_clients", lambda: (FakeCosmos(findings, run), blobs))
    result = reports.generate_poam() if kind == "poam" else reports.generate_sar()
    return result, blobs


def poam_items(blobs):
    return json.loads(blobs.get(".json"))["items"]


def test_owner_is_the_stored_one_and_a_missing_owner_says_so(monkeypatch):
    _, blobs = generate(monkeypatch, [finding("A", "High", "a@example.com"), finding("B", "Low", None)])
    owners = {i["weakness"]: i["owner"] for i in poam_items(blobs)}
    assert owners == {"A": "a@example.com", "B": "unassigned"}
    assert "resource-group owner tag" not in blobs.get(".json"), "the starter's placeholder text must be gone"


def test_owner_lands_in_the_owner_column_of_the_spreadsheet(monkeypatch):
    _, blobs = generate(monkeypatch, [finding("A", "High", "a@example.com")])
    sheet = openpyxl.load_workbook(io.BytesIO(blobs.get(".xlsx"))).active
    header = [c.value for c in sheet[1]]
    assert sheet.cell(row=2, column=header.index("Owner") + 1).value == "a@example.com"


def test_severity_is_ranked_not_alphabetical_and_the_sla_follows_it(monkeypatch):
    findings = [
        finding("low", "Low", "o"), finding("high", "High", "o"),
        finding("med", "Medium", "o"), finding("unrated", None, "o"),
    ]
    _, blobs = generate(monkeypatch, findings)
    items = poam_items(blobs)
    assert [i["severity"] for i in items] == ["High", "Medium", "Medium", "Low"], "text order would put Low before Medium"
    today = datetime.date.today()
    days = {i["weakness"]: (datetime.date.fromisoformat(i["scheduledCompletion"]) - today).days for i in items}
    assert days == {"high": 30, "med": 90, "unrated": 90, "low": 180}, "no severity is treated as Medium"


def test_poam_ids_do_not_depend_on_the_order_cosmos_returns(monkeypatch):
    findings = [finding(n, s, "o", resource=n) for n, s in
                [("a", "High"), ("b", "High"), ("c", "Medium"), ("d", "Low"), ("e", "Low")]]
    _, forward = generate(monkeypatch, findings)
    _, backward = generate(monkeypatch, list(reversed(findings)))
    assert ({i["poamId"]: i["weakness"] for i in poam_items(forward)}
            == {i["poamId"]: i["weakness"] for i in poam_items(backward)})


def test_nothing_is_ever_overwritten_in_the_immutable_container(monkeypatch):
    _, poam = generate(monkeypatch, [finding("A", "High", "o")])
    _, sar = generate(monkeypatch, [finding("A", "High", "o")], kind="sar")
    assert poam.uploads and sar.uploads
    assert all(overwrite is False for _, _, overwrite in poam.uploads + sar.uploads)


def test_an_empty_store_yields_a_valid_empty_report(monkeypatch):
    result, blobs = generate(monkeypatch, [], run=None)
    assert result["items"] == 0 and result["runId"] is None
    assert poam_items(blobs) == [] and len(blobs.uploads) == 2


def test_the_sar_carries_owner_and_severity_order(monkeypatch):
    result, blobs = generate(
        monkeypatch, [finding("low one", "Low", "l@example.com"), finding("high one", "High", "h@example.com")], kind="sar")
    text = blobs.get(".md")
    assert result["findings"] == 2
    assert "- Owner: h@example.com" in text and "- Owner: l@example.com" in text
    assert text.index("high one") < text.index("low one")


def test_reports_read_the_evidence_store_only():
    """The rule that makes every report number reproducible: no live platform API, ever."""
    source = SRC.read_text()
    for forbidden in ("management.azure.com", "import requests", "Microsoft.Security", "DefenderForCloud"):
        assert forbidden not in source, f"report generators must not touch {forbidden}"
