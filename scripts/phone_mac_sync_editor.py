#!/usr/bin/env python3
"""Mac counterpart for V2PhoneMacSyncTests; only edits a unique synthetic acceptance file."""
import argparse
import base64
import hashlib
import json
import pathlib
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--path", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
if not re.fullmatch(r"acceptance/phone-mac-[a-z0-9-]+\.md", args.path):
    parser.error("Only a unique phone-mac acceptance path is allowed")
output = pathlib.Path(args.output)
output.mkdir(parents=True, exist_ok=True)
api = f"repos/liuxiaoyusky/tough-trial-sync/contents/{args.path}"


def read():
    result = subprocess.run(["gh", "api", api + "?ref=main"], capture_output=True, text=True)
    if result.returncode:
        if "HTTP 404" in result.stderr:
            return None
        raise RuntimeError("GitHub read failed; check gh authentication and repository access")
    value = json.loads(result.stdout)
    return value["sha"], base64.b64decode(value["content"])


deadline = time.monotonic() + 180
initial = None
while time.monotonic() < deadline:
    initial = read()
    if initial is not None:
        break
    time.sleep(2)
if initial is None:
    raise TimeoutError("The phone did not publish the synthetic file")
initial_sha, original = initial
text = original.decode("utf-8")
if text.count("真机合成同步任务") != 1 or text.count("保留 3 个示例") != 1:
    raise ValueError("Unexpected synthetic baseline; refused to edit")
(output / "initial.md").write_bytes(original)
edited = text.replace("真机合成同步任务", "Mac 修改后的合成任务").replace(
    "保留 3 个示例", "保留 3 个示例，必须配图"
).encode("utf-8")
(output / "schedule.md").write_bytes(edited)
body = {"branch": "main", "sha": initial_sha,
        "message": "test: Mac concurrent schedule title and note edit",
        "content": base64.b64encode(edited).decode("ascii")}
result = subprocess.run(["gh", "api", "--method", "PUT", api, "--input", "-"],
                        input=json.dumps(body), capture_output=True, text=True)
if result.returncode:
    raise RuntimeError("Conditional Mac write failed; refused to overwrite a newer revision")
mac_sha = json.loads(result.stdout)["content"]["sha"]
print(f"MAC_EDIT_APPLIED sha={mac_sha}", flush=True)

deadline = time.monotonic() + 180
while time.monotonic() < deadline:
    final = read()
    if final is not None and "真机离线后恢复任务" in final[1].decode("utf-8"):
        sha, content = final
        expected = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        if sha != expected:
            raise ValueError("Downloaded bytes do not match the GitHub blob SHA")
        (output / "final-received.md").write_bytes(content)
        report = {"path": args.path, "initialSHA": initial_sha, "macWriteSHA": mac_sha,
                  "finalSHA": sha, "downloadedBytesMatchSHA": True}
        (output / "result.json").write_text(json.dumps(report, indent=2))
        print(f"MAC_RECEIVED_PHONE_RESULT sha={sha}", flush=True)
        break
    time.sleep(2)
else:
    raise TimeoutError("The phone did not publish its recovered final state")
