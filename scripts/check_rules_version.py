#!/usr/bin/env python3
"""Fails when rules.json changed but its version wasn't raised.

The app only replaces its rule list with a downloaded one whose version is higher, so a change
published without a version bump would never reach anyone.

Usage: check_rules_version.py <local rules.json> <published rules.json URL>
"""
import json
import sys
import urllib.error
import urllib.request


def main() -> int:
    local_path, published_url = sys.argv[1], sys.argv[2]
    with open(local_path, encoding="utf-8") as f:
        local = json.load(f)

    try:
        with urllib.request.urlopen(published_url, timeout=30) as response:
            published = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print(f"Nothing published at {published_url} yet; version {local['version']} will be the first.")
            return 0
        raise

    if local == published:
        print(f"rules.json is unchanged (version {local['version']}).")
        return 0
    if local["version"] > published["version"]:
        print(f"rules.json changed: version {published['version']} -> {local['version']}.")
        return 0
    print(
        f"rules.json changed but its version is {local['version']}, published is {published['version']}. "
        "Raise \"version\" in rules.json, otherwise the app ignores the change."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
