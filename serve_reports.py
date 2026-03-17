#!/usr/bin/env python3
"""
serve_reports.py — pg_gather report viewer

Starts a local HTTP server on http://localhost:8080 that:
  - Shows an index page listing all HTML reports in ./reports/
  - Each entry shows filename, generation timestamp, file size
  - Sorted newest first
  - Serves the actual HTML report files when clicked
"""

import http.server
import os
import sys
from datetime import datetime
from pathlib import Path

PORT = 8080
REPORTS_DIR = Path(__file__).parent / "reports"

# ── HTML template for the index page ─────────────────────────────────────────
INDEX_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>pg_gather Report Viewer</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0f172a;
      color: #e2e8f0;
      margin: 0;
      padding: 2rem;
      min-height: 100vh;
    }}
    .header {{
      max-width: 900px;
      margin: 0 auto 2rem;
      display: flex;
      align-items: center;
      gap: 1rem;
    }}
    .header h1 {{
      font-size: 1.75rem;
      font-weight: 700;
      color: #f1f5f9;
      margin: 0;
    }}
    .badge {{
      background: #1e40af;
      color: #bfdbfe;
      font-size: 0.7rem;
      font-weight: 600;
      padding: 0.2rem 0.6rem;
      border-radius: 9999px;
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }}
    .subtitle {{
      max-width: 900px;
      margin: 0 auto 2rem;
      color: #94a3b8;
      font-size: 0.9rem;
    }}
    .subtitle code {{
      background: #1e293b;
      padding: 0.1rem 0.4rem;
      border-radius: 4px;
      font-size: 0.85rem;
      color: #7dd3fc;
    }}
    .table-wrap {{
      max-width: 900px;
      margin: 0 auto;
      background: #1e293b;
      border-radius: 12px;
      overflow: hidden;
      border: 1px solid #334155;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
    }}
    thead {{
      background: #0f172a;
    }}
    th {{
      text-align: left;
      padding: 0.9rem 1.2rem;
      font-size: 0.75rem;
      font-weight: 600;
      color: #64748b;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      border-bottom: 1px solid #334155;
    }}
    td {{
      padding: 0.85rem 1.2rem;
      font-size: 0.875rem;
      border-bottom: 1px solid #1e293b;
      vertical-align: middle;
    }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background: #263348; }}
    .report-link {{
      color: #38bdf8;
      text-decoration: none;
      font-weight: 500;
      display: flex;
      align-items: center;
      gap: 0.4rem;
    }}
    .report-link:hover {{ color: #7dd3fc; text-decoration: underline; }}
    .icon {{ font-size: 1rem; }}
    .label {{
      display: inline-block;
      font-size: 0.7rem;
      font-weight: 600;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
      text-transform: lowercase;
    }}
    .label-lab   {{ background: #14532d; color: #86efac; }}
    .label-base  {{ background: #1e3a5f; color: #93c5fd; }}
    .label-prod  {{ background: #3b1f5e; color: #d8b4fe; }}
    .label-other {{ background: #1e293b; color: #94a3b8; }}
    .date   {{ color: #94a3b8; font-size: 0.82rem; }}
    .size   {{ color: #64748b; font-size: 0.82rem; font-variant-numeric: tabular-nums; }}
    .empty {{
      text-align: center;
      padding: 3rem;
      color: #475569;
    }}
    .empty p {{ margin: 0.5rem 0; }}
    .empty code {{
      background: #0f172a;
      padding: 0.2rem 0.5rem;
      border-radius: 4px;
      color: #7dd3fc;
    }}
    .stats {{
      max-width: 900px;
      margin: 1.5rem auto 0;
      display: flex;
      gap: 1.5rem;
    }}
    .stat {{
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 8px;
      padding: 0.75rem 1.25rem;
      font-size: 0.8rem;
    }}
    .stat-val {{ font-size: 1.4rem; font-weight: 700; color: #f1f5f9; }}
    .stat-lbl {{ color: #64748b; margin-top: 0.1rem; }}
  </style>
</head>
<body>
  <div class="header">
    <h1>📊 pg_gather Reports</h1>
    <span class="badge">PostgreSQL 16</span>
  </div>
  <p class="subtitle">
    Serving from <code>{reports_dir}</code> &nbsp;·&nbsp;
    Refresh to pick up new reports &nbsp;·&nbsp;
    <code>make report</code> to generate a new one
  </p>

  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>Report</th>
          <th>Generated</th>
          <th>Size</th>
        </tr>
      </thead>
      <tbody>
        {rows}
      </tbody>
    </table>
  </div>

  <div class="stats">
    <div class="stat">
      <div class="stat-val">{total_reports}</div>
      <div class="stat-lbl">HTML reports</div>
    </div>
    <div class="stat">
      <div class="stat-val">{total_size}</div>
      <div class="stat-lbl">total size</div>
    </div>
    <div class="stat">
      <div class="stat-val">{latest_age}</div>
      <div class="stat-lbl">latest report age</div>
    </div>
  </div>
</body>
</html>"""

ROW_TEMPLATE = """
        <tr>
          <td>
            <a class="report-link" href="/reports/{filename}" target="_blank">
              <span class="icon">📄</span>{filename}
            </a>
            &nbsp;<span class="label {label_class}">{label}</span>
          </td>
          <td class="date">{date}</td>
          <td class="size">{size}</td>
        </tr>"""

EMPTY_ROW = """
        <tr>
          <td colspan="3" class="empty">
            <p>No HTML reports found in <code>./reports/</code></p>
            <p>Run <code>make report</code> to generate one.</p>
          </td>
        </tr>"""


def human_size(n_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n_bytes < 1024:
            return f"{n_bytes:.0f} {unit}"
        n_bytes /= 1024
    return f"{n_bytes:.1f} GB"


def label_for(filename: str) -> tuple[str, str]:
    name = filename.lower()
    if "baseline" in name:
        return "baseline", "label-base"
    if "prodsafe" in name or "production" in name:
        return "prod-safe", "label-prod"
    for i in range(1, 8):
        if f"lab{i}" in name:
            return f"lab{i}", "label-lab"
    return "report", "label-other"


def age_str(mtime: float) -> str:
    delta = datetime.now().timestamp() - mtime
    if delta < 60:
        return "just now"
    if delta < 3600:
        return f"{int(delta/60)}m ago"
    if delta < 86400:
        return f"{int(delta/3600)}h ago"
    return f"{int(delta/86400)}d ago"


def build_index() -> str:
    html_files = sorted(
        REPORTS_DIR.glob("*.html"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )

    if not html_files:
        rows = EMPTY_ROW
        total_reports = 0
        total_size = "0 B"
        latest_age = "—"
    else:
        rows_list = []
        for p in html_files:
            stat = p.stat()
            mtime = stat.st_mtime
            label, label_class = label_for(p.name)
            rows_list.append(ROW_TEMPLATE.format(
                filename=p.name,
                label=label,
                label_class=label_class,
                date=datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S"),
                size=human_size(stat.st_size),
            ))
        rows = "".join(rows_list)
        total_bytes = sum(p.stat().st_size for p in html_files)
        total_reports = len(html_files)
        total_size = human_size(total_bytes)
        latest_age = age_str(html_files[0].stat().st_mtime)

    return INDEX_TEMPLATE.format(
        reports_dir=str(REPORTS_DIR),
        rows=rows,
        total_reports=total_reports,
        total_size=total_size,
        latest_age=latest_age,
    )


class ReportHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            content = build_index().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        elif self.path.startswith("/reports/"):
            # Strip leading slash and serve from project root
            rel = self.path.lstrip("/")
            abs_path = Path(__file__).parent / rel
            if abs_path.exists() and abs_path.suffix == ".html":
                content = abs_path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_error(404, "Report not found")
        else:
            self.send_error(404)

    def log_message(self, fmt, *args):
        # Suppress the default noisy per-request log; print a cleaner version
        print(f"  {self.address_string()} → {args[0]} {args[1]}")


if __name__ == "__main__":
    if not REPORTS_DIR.exists():
        print(f"Creating reports directory: {REPORTS_DIR}")
        REPORTS_DIR.mkdir(parents=True)

    reports_count = len(list(REPORTS_DIR.glob("*.html")))
    print(f"\n  pg_gather Report Viewer")
    print(f"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"  Serving {reports_count} report(s) from: {REPORTS_DIR}")
    print(f"  URL : http://localhost:{PORT}")
    print(f"  Stop: Ctrl+C")
    print(f"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

    with http.server.HTTPServer(("", PORT), ReportHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n  Server stopped.")
            sys.exit(0)
