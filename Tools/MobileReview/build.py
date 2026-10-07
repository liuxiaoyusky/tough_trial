#!/usr/bin/env python3
"""Export a static, device-local review workspace from the canonical Feature Map."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tools/FeatureCLI"))
from review_links import inspect, local


def build(destination):
    data = inspect(ROOT)
    if not data["ok"]:
        raise ValueError(data["errors"])
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "assets").mkdir(exist_ok=True)
    for source in (Path(__file__).parent / "web").iterdir():
        if source.is_file():
            shutil.copy2(source, destination / source.name)
    pages = []
    for page in data["pages"].values():
        source = local(ROOT, page["image"])
        revision = hashlib.sha256(source.read_bytes()).hexdigest()
        # Immutable asset names keep image pixels and annotation coordinates together.
        name = revision + source.suffix
        shutil.copy2(source, destination / "assets" / name)
        pages.append({**page, "image": "assets/" + name, "revision": revision})
    manifest = {"schema": 1, "project": "tough-trial", "title": "Tough Trial",
                "features": data["features"], "pages": pages}
    (destination / "review.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f"Exported {len(pages)} versioned screens to {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/mobile-review")
    build(parser.parse_args().output.resolve())
