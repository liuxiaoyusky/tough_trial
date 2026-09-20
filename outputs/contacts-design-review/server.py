"""Local screenshot review; only this directory is served. Run: python3 server.py."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import re

ROOT = Path(__file__).resolve().parent
def page_ids():
    return set(re.findall(r"\{id:'([^']+)'", (ROOT / "index.html").read_text(encoding="utf-8")))
PORT = 8768


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path == "/api/feedback":
            data = (ROOT / "feedback.json").read_bytes() if (ROOT / "feedback.json").exists() else b"[]"
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        else:
            super().do_GET()

    def do_POST(self):
        if self.path != "/api/feedback":
            self.send_error(404)
            return
        if self.headers.get("Origin") != f"http://127.0.0.1:{PORT}":
            self.send_error(403)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1_000_000:
                raise ValueError("Invalid size")
            values = json.loads(self.rfile.read(size))
            if not isinstance(values, list) or len(values) > 500:
                raise ValueError("Invalid list")
            for value in values:
                if not isinstance(value, dict) or set(value) != {"id", "page", "x", "y", "text", "resolved"}:
                    raise ValueError("Invalid annotation")
                if value["page"] not in page_ids() or not isinstance(value["id"], str) or len(value["id"]) > 80:
                    raise ValueError("Invalid identity")
                if not isinstance(value["text"], str) or not 0 < len(value["text"].strip()) <= 4000:
                    raise ValueError("Invalid text")
                if not isinstance(value["resolved"], bool):
                    raise ValueError("Invalid status")
                if any(type(value[k]) not in (int, float) or not 0 <= value[k] <= 1 for k in ("x", "y")):
                    raise ValueError("Invalid position")
            if len({v["id"] for v in values}) != len(values):
                raise ValueError("Duplicate identity")
            temporary = ROOT / "feedback.json.tmp"
            temporary.write_text(json.dumps(values, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(temporary, ROOT / "feedback.json")
            lines = ["# Tough Trial 页面批注", "", "坐标为截图比例，从左上角 (0, 0) 到右下角 (1, 1)。", ""]
            for index, value in enumerate(values, 1):
                lines.extend([f"## {index}. {value['page']} · {'已处理' if value['resolved'] else '待处理'}", "",
                              f"位置：x={value['x']:.4f}, y={value['y']:.4f}；ID：{value['id']}", "",
                              value["text"], ""])
            (ROOT / "feedback.md").write_text("\n".join(lines), encoding="utf-8")
        except (ValueError, TypeError, KeyError, json.JSONDecodeError):
            self.send_error(400, "Invalid annotations")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"saved":true}')


if __name__ == "__main__":
    print(f"Profile share review: http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
