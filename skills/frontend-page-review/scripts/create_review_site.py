#!/usr/bin/env python3
"""Create a self-contained local annotation site from a JSON page manifest."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
ALLOWED_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg"}


def load_pages(path: Path) -> list[dict[str, str]]:
    values = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(values, list) or not values:
        raise ValueError("pages manifest must be a non-empty JSON array")

    normalized: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, value in enumerate(values, 1):
        if not isinstance(value, dict):
            raise ValueError(f"page {index} must be an object")
        page_id = value.get("id")
        title = value.get("title")
        image = value.get("image")
        description = value.get("description", "")
        if not isinstance(page_id, str) or not ID_RE.fullmatch(page_id):
            raise ValueError(f"page {index} has an invalid id")
        if page_id in seen:
            raise ValueError(f"duplicate page id: {page_id}")
        if not isinstance(title, str) or not title.strip():
            raise ValueError(f"page {page_id} needs a title")
        if not isinstance(description, str):
            raise ValueError(f"page {page_id} description must be a string")
        if not isinstance(image, str) or not image.strip():
            raise ValueError(f"page {page_id} needs an image path")
        source = Path(image).expanduser().resolve()
        if not source.is_file():
            raise ValueError(f"page {page_id} image does not exist: {source}")
        if source.suffix.lower() not in ALLOWED_IMAGE_SUFFIXES:
            raise ValueError(f"page {page_id} image type is not supported: {source.suffix}")
        seen.add(page_id)
        normalized.append(
            {
                "id": page_id,
                "title": title.strip(),
                "description": description.strip(),
                "_source": str(source),
            }
        )
    return normalized


def build(output: Path, title: str, pages: list[dict[str, str]]) -> None:
    skill_root = Path(__file__).resolve().parent.parent
    template_root = skill_root / "assets" / "review-site"
    output.mkdir(parents=True, exist_ok=True)
    assets = output / "assets"
    assets.mkdir(exist_ok=True)

    web_pages: list[dict[str, str]] = []
    for page in pages:
        source = Path(page["_source"])
        destination_name = f"{page['id']}{source.suffix.lower()}"
        shutil.copy2(source, assets / destination_name)
        web_pages.append(
            {
                "id": page["id"],
                "title": page["title"],
                "description": page["description"],
                "source": destination_name,
            }
        )

    index_template = (template_root / "index.html.template").read_text(encoding="utf-8")
    rendered = index_template.replace("__REVIEW_TITLE__", title)
    rendered = rendered.replace(
        "__PAGES_JSON__",
        json.dumps(web_pages, ensure_ascii=False, separators=(",", ":")),
    )
    (output / "index.html").write_text(rendered, encoding="utf-8")
    shutil.copy2(template_root / "server.py.template", output / "server.py")
    (output / "pages.json").write_text(
        json.dumps(web_pages, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    if not (output / "feedback.json").exists():
        (output / "feedback.json").write_text("[]\n", encoding="utf-8")
    if not (output / "feedback.md").exists():
        (output / "feedback.md").write_text(
            "# 页面批注\n\n暂无批注。\n",
            encoding="utf-8",
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--title", default="Frontend UI Review")
    parser.add_argument("--pages", required=True, type=Path)
    args = parser.parse_args()

    pages = load_pages(args.pages.resolve())
    build(args.output.resolve(), args.title.strip() or "Frontend UI Review", pages)
    print(f"Created review site: {args.output.resolve()}")
    print(f"Pages: {len(pages)}")


if __name__ == "__main__":
    main()
