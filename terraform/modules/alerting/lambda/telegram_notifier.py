"""
SNS → Telegram bridge.

Input : SNS notification record (CloudWatch Alarm payload hoặc EventBridge event
        được wrap qua SNS).
Output: POST tới Telegram Bot sendMessage API.

Behavior:
- Đọc bot_token + chat_id từ Secrets Manager (cache cross-invocation).
- Tự detect loại payload (CloudWatch Alarm vs EventBridge event) và format khác nhau.
- Severity suy ra từ tên SNS Topic ARN:
    *-alerts-critical* → 🚨 CRITICAL
    *-alerts-warning*  → ⚠️ WARNING
    (khác)             → ℹ️ INFO
"""

import json
import logging
import os
import urllib.parse
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ID = os.environ["TELEGRAM_SECRET_ID"]

_sm = boto3.client("secretsmanager")
_secret_cache: dict | None = None  # cached across warm invocations


# ---------------------------------------------------------------------------
# Credential helpers
# ---------------------------------------------------------------------------

def _get_credentials() -> dict:
    """Return {bot_token, chat_id} — fetched once then cached in module scope."""
    global _secret_cache
    if _secret_cache is None:
        resp = _sm.get_secret_value(SecretId=SECRET_ID)
        _secret_cache = json.loads(resp["SecretString"])
    return _secret_cache


# ---------------------------------------------------------------------------
# Severity detection
# ---------------------------------------------------------------------------

def _severity_label(topic_arn: str) -> str:
    if "alerts-critical" in topic_arn:
        return "🚨 CRITICAL"
    if "alerts-warning" in topic_arn:
        return "⚠️ WARNING"
    return "ℹ️ INFO"


# ---------------------------------------------------------------------------
# Message formatters
# ---------------------------------------------------------------------------

def _format_cloudwatch_alarm(payload: dict, severity: str) -> str:
    """Format a CloudWatch Alarm state-change notification."""
    alarm_name = payload.get("AlarmName", "Unknown")
    state      = payload.get("NewStateValue", "?")
    reason     = payload.get("NewStateReason", "")[:500]
    region     = payload.get("Region", "")
    account    = payload.get("AWSAccountId", "")

    return (
        f"<b>{severity}: CloudWatch Alarm</b>\n"
        f"<i>Alarm:</i>  <code>{alarm_name}</code>\n"
        f"<i>State:</i>  {state}\n"
        f"<i>Region:</i> {region}  |  <i>Account:</i> {account}\n"
        f"<i>Reason:</i>\n<code>{reason}</code>"
    )


def _format_eventbridge_event(payload: dict, severity: str) -> str:
    """Format an EventBridge event forwarded through SNS."""
    detail_type = payload.get("detail-type", "?")
    source      = payload.get("source", "?")
    region      = payload.get("region", "?")
    detail      = payload.get("detail", {})

    # For ECS events, surface the most useful fields directly
    cluster_arn  = detail.get("clusterArn", "")
    service_arn  = detail.get("serviceArn", "") or detail.get("group", "")
    reason       = detail.get("reason", "") or detail.get("stoppedReason", "")
    rollout      = detail.get("rolloutState", "")
    event_name   = detail.get("eventName", "")

    lines = [f"<b>{severity}: {detail_type}</b>"]
    if event_name:
        lines.append(f"<i>Event:</i>    <code>{event_name}</code>")
    if cluster_arn:
        cluster_name = cluster_arn.split("/")[-1]
        lines.append(f"<i>Cluster:</i>  <code>{cluster_name}</code>")
    if service_arn:
        svc_name = service_arn.split("/")[-1]
        lines.append(f"<i>Service:</i>  <code>{svc_name}</code>")
    if rollout:
        lines.append(f"<i>Rollout:</i>  {rollout}")
    if reason:
        lines.append(f"<i>Reason:</i>   <code>{reason[:400]}</code>")

    lines.append(f"<i>Source:</i>  {source}  |  <i>Region:</i> {region}")

    # If no ECS-specific fields found, dump full detail for debugging
    if len(lines) == 2:
        summary = json.dumps(detail, default=str)[:600]
        lines.append(f"<i>Detail:</i>\n<code>{summary}</code>")

    return "\n".join(lines)


def _format_raw(message_raw: str, severity: str) -> str:
    """Fallback: non-JSON or unrecognised payload."""
    return f"<b>{severity}</b>\n<code>{message_raw[:1000]}</code>"


# ---------------------------------------------------------------------------
# Telegram sender
# ---------------------------------------------------------------------------

def _send_telegram(text: str) -> None:
    creds = _get_credentials()
    url   = f"https://api.telegram.org/bot{creds['bot_token']}/sendMessage"
    body  = urllib.parse.urlencode({
        "chat_id":                creds["chat_id"],
        "text":                   text,
        "parse_mode":             "HTML",
        "disable_web_page_preview": "true",
    }).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=8) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"Telegram API returned HTTP {resp.status}")


# ---------------------------------------------------------------------------
# Lambda handler
# ---------------------------------------------------------------------------

def handler(event, _context):
    logger.info("Received SNS event with %d record(s)", len(event.get("Records", [])))

    for record in event.get("Records", []):
        sns         = record.get("Sns", {})
        topic_arn   = sns.get("TopicArn", "")
        message_raw = sns.get("Message", "")
        severity    = _severity_label(topic_arn)

        try:
            payload = json.loads(message_raw)
        except (json.JSONDecodeError, ValueError):
            _send_telegram(_format_raw(message_raw, severity))
            continue

        # Route to correct formatter
        if "AlarmName" in payload:
            text = _format_cloudwatch_alarm(payload, severity)
        elif "detail-type" in payload:
            text = _format_eventbridge_event(payload, severity)
        else:
            text = _format_raw(json.dumps(payload, default=str), severity)

        logger.info("Sending Telegram message (severity=%s, ~%d chars)", severity, len(text))
        _send_telegram(text)

    return {"status": "ok"}
