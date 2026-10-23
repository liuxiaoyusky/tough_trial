#!/usr/bin/env python3
"""Resolve review pages from Feature Map; validate links without claiming UI parity."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
REVIEW = "outputs/contacts-design-review"


def local(root, name):
    relative = Path(name)
    path = (root / relative).resolve()
    if relative.is_absolute() or ".." in relative.parts or not path.is_relative_to(root):
        raise ValueError(f"Unsafe reference: {name}")
    if not path.is_file():
        raise ValueError(f"Missing reference: {name}")
    return path


def inspect(root=ROOT):
    root = root.resolve()
    data = json.loads(local(root, "docs/feature-map.json").read_text())
    html = local(root, f"{REVIEW}/index.html").read_text()
    listed = dict(re.findall(r"\{id:'([^']+)',title:'[^']*',description:'[^']*',source:'([^']+)'", html))
    links, features, errors = {}, [], []
    ontology_ids = {node["id"] for node in json.loads(local(root, "ontology/task-workspace.json").read_text())["nodes"]}
    for feature in data["features"]:
        ui = feature.get("ui")
        if not ui:
            continue
        stale = []
        for evidence in feature["evidence"]:
            try:
                digest = hashlib.sha256(local(root, evidence["path"]).read_bytes()).hexdigest()
                if digest != evidence["sha256"]:
                    stale.append(evidence["path"])
            except ValueError:
                stale.append(evidence["path"])
        for ref in feature["ontology_refs"]:
            if ref not in ontology_ids:
                errors.append(f"Unknown ontology entity: {ref}")
        for source in ui["code"]:
            local(root, source["path"])
        for page in ui["review_pages"]:
            page_id = page["id"]
            if page_id in links:
                errors.append(f"Duplicate page mapping: {page_id}")
            if listed.get(page_id) != Path(page["image"]).name:
                errors.append(f"Page/image mismatch: {page_id}")
            local(root, page["image"])
            if page["kind"] not in ("design", "simulator", "device"):
                errors.append(f"Invalid evidence kind: {page_id}")
            links[page_id] = {**page, "feature_id": feature["id"], "feature_title": feature["title"],
                              "route": ui["route"], "implementation_status": ui["implementation_status"],
                              "code": ui["code"], "acceptance": feature["acceptance"],
                              "ontology_refs": feature["ontology_refs"],
                              "freshness": "needs_review" if stale else "current", "stale_references": stale}
        features.append({"id": feature["id"], "title": feature["title"], "pages": [p["id"] for p in ui["review_pages"]]})
    errors.extend(f"Unmapped review page: {name}" for name in listed.keys() - links.keys())
    return {"ok": not errors, "scope": "review_feature_reference_consistency", "errors": errors,
            "page_count": len(links), "features": features, "pages": links,
            "product_verification": "not_assessed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-index", action="store_true")
    args = parser.parse_args()
    try:
        result = inspect()
        if args.write_index and result["ok"]:
            lines = ["# UI 与 Feature Map 对照", "", "由 `python3 Tools/FeatureCLI/review_links.py --write-index` 从 `docs/feature-map.json` 生成。不要手改。",
                     "", "图片来源和功能实现状态是两层信息；关联正确不代表已通过视觉或交互验收。评审服务运行于 8770 时可点击下列入口。", "",
                     "| Feature | App 入口 | 评审页面 | 图像来源 | 版本 / 日期 | 验收说明 |", "| --- | --- | --- | --- | --- | --- |"]
            for page in result["pages"].values():
                lines.append(f"| `{page['feature_id']}` | {page['route']} | [{page['id']}](http://127.0.0.1:8770/#{page['id']}) | {page['kind']} | {page['provenance']} | {page['verification']} |")
            (ROOT / "docs/ui-feature-index.md").write_text("\n".join(lines) + "\n")
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["ok"] else 1
    except (ValueError, OSError, KeyError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
