#!/usr/bin/env python3
"""Collect local UI references; never claim pixel parity or a runtime diagnosis."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    "Sources/ToughTrialV2App/ToughTrialV2App.swift": ["V2RootView()", "#else"],
    "Sources/ToughTrialV2App/V2RootView.swift": ["V2CaptureView(", "V2BottomNavigationBar("],
    "Sources/ToughTrialV2App/V2CaptureView.swift": [
        'navigationTitle("随手记")', 'Text("想到什么，就记下来。")',
        "TextEditor(text:", "private var editor:", "private var captureContent:",
    ],
    "Sources/ToughTrialV2App/V2Theme.swift": ["static let canvas", "static let surface ="],
    "Sources/ToughTrialV2App/V2BottomNavigationBar.swift": [".foregroundStyle(", ".background("],
}


def inspect(baseline):
    supplied = Path(baseline)
    path = (ROOT / supplied).resolve()
    if ".." in supplied.parts or not path.is_relative_to(ROOT):
        raise ValueError("baseline must stay inside the project root")
    relative = path.relative_to(ROOT)
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("baseline must have a PNG header; visual validity needs separate review")
    width, height = struct.unpack(">II", data[16:24])
    sources = []
    for name, needles in SOURCES.items():
        content = (ROOT / name).read_bytes()
        lines = content.decode("utf-8").splitlines()
        sources.append({
            "path": name, "sha256": hashlib.sha256(content).hexdigest(),
            "locations": [{"line": number, "text": line.strip()}
                          for number, line in enumerate(lines, 1)
                          if any(needle in line for needle in needles)],
            "appearance_declarations": [{"line": number, "text": line.strip()}
                                       for number, line in enumerate(lines, 1)
                                       if "preferredColorScheme" in line or "overrideUserInterfaceStyle" in line],
        })
    # Use Git's existing history/status rather than creating a second version registry.
    history = subprocess.run(
        ["git", "log", "-1", "--format=%h %s", "--", *SOURCES],
        cwd=ROOT, check=True, capture_output=True, text=True, timeout=10,
    ).stdout.strip()
    changes = subprocess.run(
        ["git", "status", "--short", "--", *SOURCES],
        cwd=ROOT, check=True, capture_output=True, text=True, timeout=10,
    ).stdout.splitlines()
    return {
        "schema_version": 1, "scope": "local_source_and_review_reference_inventory",
        "run_id": os.environ.get("FEATURE_CLI_RUN_ID"),
        "baseline": {"path": relative.as_posix(), "sha256": hashlib.sha256(data).hexdigest(),
                     "width": width, "height": height},
        "sources": sources, "latest_source_commit": history, "working_tree_changes": changes,
        "acceptance_source": "docs/qa/2026-09-30-testflight-preparation.md",
        "product_verification": "not_assessed", "installed_binary_identity": "not_assessed",
        "limitations": ["No simulator/device interaction is performed.",
                        "Line matches are navigation hints, not semantic proof or a root cause.",
                        "PNG metadata does not prove visual parity or user approval."],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    args = parser.parse_args()
    try:
        result = inspect(args.baseline)
        destination = ROOT / ".runtime/ui-audit/capture.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "report": str(destination.relative_to(ROOT)),
                          "product_verification": "not_assessed"}))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": "audit_failed", "message": str(error)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
