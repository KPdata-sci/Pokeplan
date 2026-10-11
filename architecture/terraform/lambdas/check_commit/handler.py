"""Publish ingest.requested with the latest PokeAPI/api-data commit SHA.

Runs nightly from EventBridge Scheduler. It does not remember what it saw last:
the Dagster sensor uses the SHA as the run key, so a repeat SHA is skipped there.
"""
import json
import os
import urllib.request

import boto3

events = boto3.client("events")


def handler(event, context):
    repo = os.environ["REPO"]
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/commits/master",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "pokeplan"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        sha = json.load(resp)["sha"]

    detail = {"source_commit": sha, "mode": "incremental", "requested_by": "schedule"}
    events.put_events(
        Entries=[{
            "EventBusName": os.environ["EVENT_BUS_NAME"],
            "Source": "pokeplan",
            "DetailType": "ingest.requested",
            "Detail": json.dumps(detail),
        }]
    )
    return detail
