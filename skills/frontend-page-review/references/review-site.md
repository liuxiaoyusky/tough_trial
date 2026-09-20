# Review site manifest

Use a JSON array. Each entry must contain an `id`, `title`, and `image`. `description` is optional.

```json
[
  {
    "id": "dashboard",
    "title": "Dashboard",
    "description": "Normal state",
    "image": "/absolute/path/to/dashboard.png"
  }
]
```

The generator copies each image into `assets/`, so the review workspace remains self-contained. IDs must use letters, digits, `-`, `_`, or `.`.

Generated files are `index.html`, `server.py`, `feedback.json`, `feedback.md`, `pages.json`, and `assets/`.

Run from the generated directory with:

```bash
python3 server.py --port 8768
```

Use another free localhost port if 8768 is occupied.
