#!/usr/bin/env python3
"""Seed the mappings container: the crosswalk from a Defender assessment to the controls it evidences.

Collect once, report against any framework: the collector stores each assessment once, and this data
says which NIST SP 800-53 Rev.5 controls and CSF 2.0 subcategories it supports. Adding a framework
means adding rows here, never re-collecting.

    COSMOS_ENDPOINT=$(cd ../../stages/03-evidence-store && terraform output -raw cosmos_endpoint) \
        python3 seed_mappings.py            # add --dry-run to print without writing

Authenticates as you (az login). Idempotent: one document per assessment per framework, upserted.
"""

import argparse
import json
import os
import pathlib
import sys

FRAMEWORKS = {"nist-800-53-r5": "nist80053r5", "nist-csf-2.0": "csf2"}
SOURCE = pathlib.Path(__file__).with_name("csf-mappings.json")


def build_documents(entries: list[dict]) -> list[dict]:
    """One mapping document per (assessment, framework). Partition key is frameworkId."""
    return [
        {
            "id": f"{entry['assessmentId']}:{framework}",
            "frameworkId": framework,
            "assessmentId": entry["assessmentId"],
            "displayName": entry["displayName"],
            "controls": entry[field],
        }
        for entry in entries
        for framework, field in FRAMEWORKS.items()
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the documents instead of writing them")
    args = parser.parse_args()

    documents = build_documents(json.loads(SOURCE.read_text()))
    if args.dry_run:
        print(json.dumps(documents[:2], indent=2))
        print(f"{len(documents)} documents would be written")
        return 0

    endpoint = os.environ.get("COSMOS_ENDPOINT")
    if not endpoint:
        print("Set COSMOS_ENDPOINT (see the docstring).", file=sys.stderr)
        return 1

    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential

    database = CosmosClient(endpoint, DefaultAzureCredential()).get_database_client(os.environ.get("COSMOS_DATABASE", "grc"))
    # The 800-53 catalog is a framework record we own, next to CSF 2.0 (seed_frameworks.py).
    database.get_container_client("frameworks").upsert_item(
        {"id": "nist-800-53-r5", "frameworkId": "nist-800-53-r5", "name": "NIST SP 800-53 Rev. 5"}
    )
    mappings = database.get_container_client("mappings")
    for document in documents:
        mappings.upsert_item(document)
    print(f"seeded {len(documents)} mapping documents")
    return 0


if __name__ == "__main__":
    sys.exit(main())
