"""
============================================================
Webhook Receiver — Test Alertmanager Notifications
============================================================
Flask app đơn giản nhận webhook POST từ Alertmanager
và hiển thị alerts trên web UI + console.

Endpoints:
  GET  /          → Web UI xem alerts đã nhận
  POST /webhook   → Nhận alerts từ Alertmanager
  GET  /health    → Health check
============================================================
"""

import json
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# Lưu alerts trong memory (mất khi restart)
received_alerts = []
MAX_ALERTS = 200

@app.route("/webhook", methods=["POST"])
def webhook():
    """Nhận alert notification từ Alertmanager"""
    data = request.get_json(force=True)

    entry = {
        "received_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "status": data.get("status", "unknown"),
        "alerts_count": len(data.get("alerts", [])),
        "alerts": data.get("alerts", []),
        "group_labels": data.get("groupLabels", {}),
    }
    received_alerts.insert(0, entry)

    # Giới hạn số lượng lưu
    while len(received_alerts) > MAX_ALERTS:
        received_alerts.pop()

    # In ra console để dễ debug
    print(f"\n{'='*60}")
    print(f"🔔 [{entry['received_at']}] Status: {entry['status'].upper()}")
    for alert in data.get("alerts", []):
        status = alert.get("status", "unknown")
        name = alert.get("labels", {}).get("alertname", "?")
        severity = alert.get("labels", {}).get("severity", "?")
        summary = alert.get("annotations", {}).get("summary", "")
        icon = "🔥" if status == "firing" else "✅"
        print(f"  {icon} {name} [{severity}] — {summary}")
    print(f"{'='*60}\n")

    return jsonify({"status": "ok"}), 200


@app.route("/")
def index():
    """Web UI — hiển thị alerts đã nhận"""
    rows = ""
    for entry in received_alerts:
        status = entry["status"]
        color = "#ff4444" if status == "firing" else "#44bb44"
        for alert in entry["alerts"]:
            a_status = alert.get("status", "?")
            name = alert.get("labels", {}).get("alertname", "?")
            severity = alert.get("labels", {}).get("severity", "?")
            instance = alert.get("labels", {}).get("instance", "—")
            summary = alert.get("annotations", {}).get("summary", "")
            sev_color = "#ff4444" if severity == "critical" else "#ffaa00" if severity == "warning" else "#4488ff"
            icon = "🔥" if a_status == "firing" else "✅"
            rows += f"""
            <tr>
                <td>{entry['received_at']}</td>
                <td>{icon} {a_status}</td>
                <td style="color:{sev_color};font-weight:bold">{severity.upper()}</td>
                <td><strong>{name}</strong></td>
                <td>{instance}</td>
                <td>{summary}</td>
            </tr>"""

    if not rows:
        rows = '<tr><td colspan="6" style="text-align:center;padding:40px;color:#888">Chưa nhận được alert nào. Đợi Alertmanager gửi notification...</td></tr>'

    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Webhook Receiver — Alertmanager Test</title>
    <meta http-equiv="refresh" content="10">
    <style>
        body {{ font-family: -apple-system, sans-serif; background: #1a1a2e; color: #e0e0e0; margin: 0; padding: 20px; }}
        h1 {{ color: #00d4ff; }}
        .info {{ color: #888; margin-bottom: 20px; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th {{ background: #16213e; color: #00d4ff; padding: 12px; text-align: left; }}
        td {{ padding: 10px 12px; border-bottom: 1px solid #2a2a4a; }}
        tr:hover {{ background: #16213e; }}
        .count {{ background: #00d4ff; color: #1a1a2e; padding: 4px 12px; border-radius: 12px; font-weight: bold; }}
    </style>
</head>
<body>
    <h1>🔔 Webhook Receiver</h1>
    <p class="info">
        Total received: <span class="count">{len(received_alerts)}</span> notifications
        &nbsp;|&nbsp; Auto-refresh mỗi 10s
        &nbsp;|&nbsp; POST endpoint: <code>/webhook</code>
    </p>
    <table>
        <tr>
            <th>Time</th>
            <th>Status</th>
            <th>Severity</th>
            <th>Alert</th>
            <th>Instance</th>
            <th>Summary</th>
        </tr>
        {rows}
    </table>
</body>
</html>"""
    return html


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "alerts_received": len(received_alerts)})


if __name__ == "__main__":
    print("🔔 Webhook Receiver started on :9095")
    print("   POST /webhook  — nhận alerts từ Alertmanager")
    print("   GET  /         — web UI xem alerts")
    app.run(host="0.0.0.0", port=9095)
