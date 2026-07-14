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

def _extract_service_name(alarm_name: str) -> str:
    """Extract service name from alarm like 'obs-lab-payment-service-memory-high'."""
    # Pattern: {project}-{env}-{service-name}-{metric-type}
    # Try to find known service name patterns
    for svc in ("payment-service", "order-service", "api-gateway", "web-ui"):
        if svc in alarm_name:
            return svc
    # Fallback: return full alarm name
    return alarm_name


def _alarm_type_badge(alarm_name: str) -> str:
    """Return a badge based on alarm type."""
    if "app-error" in alarm_name:
        return "📋 APP"
    if "memory" in alarm_name:
        return "🧠 MEM"
    if "cpu" in alarm_name:
        return "⚙️ CPU"
    if "running-task" in alarm_name:
        return "💀 TASK"
    return "📊 METRIC"


def _format_cloudwatch_alarm(payload: dict, severity: str) -> str:
    """Format a CloudWatch Alarm state-change notification."""
    alarm_name  = payload.get("AlarmName", "Unknown")
    state       = payload.get("NewStateValue", "?")
    reason      = payload.get("NewStateReason", "")
    region      = payload.get("Region", "")
    description = payload.get("AlarmDescription", "")
    timestamp   = payload.get("StateChangeTime", "")[:19]  # trim to YYYY-MM-DDTHH:MM:SS

    service = _extract_service_name(alarm_name)
    badge   = _alarm_type_badge(alarm_name)

    # State-based header
    if state == "ALARM":
        header = f"🔴 ALARM FIRING"
    elif state == "OK":
        header = f"🟢 RECOVERED"
    else:
        header = f"🟡 {state}"

    # Truncate reason smartly — keep first line only for readability
    reason_short = reason.split(".")[0][:200] if reason else ""

    lines = [
        f"<b>{header}</b>",
        f"━━━━━━━━━━━━━━━━━━",
        f"📌 <b>{service}</b>  [{badge}]",
        f"",
        f"<b>Alarm:</b>  <code>{alarm_name}</code>",
    ]

    if description:
        lines.append(f"<b>What:</b>   {description[:200]}")

    if reason_short:
        lines.append(f"<b>Why:</b>    <code>{reason_short}</code>")

    lines.append(f"")

    if timestamp:
        lines.append(f"🕐 {timestamp}  |  🌏 {region}")
    else:
        lines.append(f"🌏 {region}")

    lines.append(f"━━━━━━━━━━━━━━━━━━")
    lines.append(f"{severity}")

    return "\n".join(lines)


def _format_eventbridge_event(payload: dict, severity: str) -> str:
    """Format an EventBridge event forwarded through SNS."""
    detail_type = payload.get("detail-type", "?")
    source      = payload.get("source", "?")
    region      = payload.get("region", "?")
    timestamp   = payload.get("time", "")[:19]
    detail      = payload.get("detail", {})

    # ECS-specific fields
    cluster_arn  = detail.get("clusterArn", "")
    service_arn  = detail.get("serviceArn", "") or detail.get("group", "")
    reason       = detail.get("reason", "") or detail.get("stoppedReason", "")
    rollout      = detail.get("rolloutState", "")
    event_name   = detail.get("eventName", "")
    stop_code    = detail.get("stopCode", "")
    exit_code    = detail.get("containers", [{}])[0].get("exitCode", "") if detail.get("containers") else ""
    last_status  = detail.get("lastStatus", "")

    cluster_name = cluster_arn.split("/")[-1] if cluster_arn else ""
    svc_name     = service_arn.split("/")[-1] if service_arn else ""

    # Determine event icon
    if "FAILED" in detail_type.upper() or "FAILED" in str(rollout).upper():
        icon = "🔴"
    elif stop_code in ("TaskFailedToStart", "EssentialContainerExited"):
        icon = "🔴"
    elif "COMPLETED" in detail_type.upper() or "STEADY_STATE" in str(rollout).upper():
        icon = "🟢"
    else:
        icon = "🟡"

    lines = [
        f"<b>{icon} {detail_type}</b>",
        f"━━━━━━━━━━━━━━━━━━",
    ]

    if svc_name:
        lines.append(f"📌 <b>{svc_name}</b>")
        lines.append(f"")

    if event_name:
        lines.append(f"<b>Event:</b>    <code>{event_name}</code>")
    if cluster_name:
        lines.append(f"<b>Cluster:</b>  <code>{cluster_name}</code>")
    if rollout:
        rollout_icon = "❌" if "FAILED" in rollout else "✅" if "COMPLETED" in rollout or "STEADY" in rollout else "🔄"
        lines.append(f"<b>Rollout:</b>  {rollout_icon} {rollout}")
    if stop_code:
        lines.append(f"<b>StopCode:</b> <code>{stop_code}</code>")
    if exit_code != "":
        lines.append(f"<b>ExitCode:</b> <code>{exit_code}</code>")
    if last_status:
        lines.append(f"<b>Status:</b>   {last_status}")
    if reason:
        lines.append(f"<b>Reason:</b>")
        lines.append(f"<code>{reason[:300]}</code>")

    lines.append(f"")

    time_region = []
    if timestamp:
        time_region.append(f"🕐 {timestamp}")
    time_region.append(f"🌏 {region}")
    lines.append("  |  ".join(time_region))

    lines.append(f"━━━━━━━━━━━━━━━━━━")
    lines.append(f"{severity}  |  <i>{source}</i>")

    # If no ECS-specific fields found, dump full detail
    if not any([cluster_arn, service_arn, event_name, rollout, stop_code]):
        summary = json.dumps(detail, default=str)[:600]
        lines.insert(2, f"<code>{summary}</code>")

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
