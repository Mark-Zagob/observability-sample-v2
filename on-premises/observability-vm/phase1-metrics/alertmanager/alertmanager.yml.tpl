# ============================================================
# Alertmanager Configuration - Phase 4
# ============================================================
# Alertmanager nhận alerts từ Prometheus và quyết định:
#   - Route tới receiver nào (dựa trên labels)
#   - Group alerts lại (tránh spam)
#   - Khi nào gửi lại (repeat_interval)
#   - Inhibit alerts nào (critical suppress warning)
# ============================================================

# ============================================================
# Global Settings
# ============================================================
global:
  resolve_timeout: 5m               # Sau 5m không nhận lại alert → resolved
  telegram_api_url: "https://api.telegram.org"

# ============================================================
# Route Tree - Quyết định alert đi đâu
# ============================================================
route:
  # Default route (catch-all)
  receiver: "telegram-alerts"
  group_by: ["alertname", "severity"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  # Child routes
  routes:
    # Watchdog → chỉ gửi webhook (tránh spam Telegram)
    - match:
        alertname: Watchdog
      receiver: "webhook-alerts"
      group_wait: 30s
      repeat_interval: 12h
      continue: false

    # Critical → gửi Telegram nhanh (10s), nhắc lại mỗi 1h
    - match:
        severity: critical
      receiver: "telegram-alerts"
      group_wait: 10s
      repeat_interval: 1h
      continue: true                   # Tiếp tục gửi webhook nữa

    # Warning → gửi Telegram, nhắc lại mỗi 4h
    - match:
        severity: warning
      receiver: "telegram-alerts"
      group_wait: 1m
      repeat_interval: 4h
      continue: true                   # Tiếp tục gửi webhook nữa

    # Catch-all webhook (nhận tất cả do continue: true ở trên)
    - match_re:
        severity: ".+"
      receiver: "webhook-alerts"
      continue: false

# ============================================================
# Receivers
# ============================================================
receivers:
  # Telegram — nhận alert notifications trên điện thoại
  - name: "telegram-alerts"
    telegram_configs:
      - bot_token: "${TELEGRAM_BOT_TOKEN}"
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: "HTML"
        message: |
          {{ if eq .Status "firing" }}🔥 <b>FIRING</b>{{ else }}✅ <b>RESOLVED</b>{{ end }}

          {{ range .Alerts }}
          <b>{{ .Labels.alertname }}</b> [{{ .Labels.severity }}]
          {{ .Annotations.summary }}
          {{ if .Annotations.description }}📝 {{ .Annotations.description }}{{ end }}
          {{ end }}
        send_resolved: true

  # Webhook — test receiver (web UI)
  - name: "webhook-alerts"
    webhook_configs:
      - url: "http://webhook-receiver:9095/webhook"
        send_resolved: true

# ============================================================
# Inhibition Rules
# ============================================================
inhibit_rules:
  - source_match:
      severity: "critical"
    target_match:
      severity: "warning"
    equal: ["instance"]

