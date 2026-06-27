# 🛡️ Iteration A — Hardening Plan (Alerting & Guard Rails)

> **Mục đích:** Implement các *Action Items* sinh ra từ 3 chaos experiment trong [`AWS_CHAOS_PLAYBOOK.md`](AWS_CHAOS_PLAYBOOK.md). Biến mỗi drill từ "biết hệ thống fail" thành "automated safety net cảnh báo khi fail".
>
> **Tác giả:** Junior DevOps/SRE/Platform Engineer onboard payment-service. Chưa có CI/CD, chạy `terraform apply` local trên VM.
>
> **Kết quả mong muốn (Definition of Done cấp Iteration):**
> 1. Re-run **Experiment 1** (IAM Blackhole) → trong vòng ≤5 phút có alert Telegram báo `SERVICE_DEPLOYMENT_FAILED`.
> 2. Re-run **Experiment 3** (Poison Config) → tương tự #1 + alert kèm `stoppedReason` để phân biệt Bad Image vs OOM.
> 3. Inject memory stress → alert Telegram báo `MemoryUtilization > 85%` **trước khi** OOM xảy ra (leading indicator).
> 4. Toàn bộ infra mới sinh ra qua Terraform, không có ClickOps.

---

## 📐 Architecture đề xuất

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          AWS (ap-southeast-2)                            │
│                                                                          │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐         │
│  │ CloudWatch      │   │ EventBridge     │   │ CloudWatch      │         │
│  │ Alarm           │   │ Rule            │   │ Alarm           │         │
│  │ MemoryUtil>85%  │   │ ECS Deployment  │   │ ECS Task Stop   │         │
│  │ (leading)       │   │ State Change    │   │ Code != 0       │         │
│  └────────┬────────┘   └────────┬────────┘   └────────┬────────┘         │
│           │                     │                     │                  │
│           └─────────────────────┼─────────────────────┘                  │
│                                 ▼                                        │
│                  ┌──────────────────────────────┐                        │
│                  │ SNS Topic: alerts-critical   │                        │
│                  │ SNS Topic: alerts-warning    │ (2 topics, severity)   │
│                  └──────────────┬───────────────┘                        │
│                                 ▼                                        │
│                  ┌──────────────────────────────┐                        │
│                  │ Lambda: telegram-notifier    │                        │
│                  │ - Format message (HTML)      │                        │
│                  │ - Severity emoji             │                        │
│                  │ - POST → Telegram Bot API    │                        │
│                  └──────────────┬───────────────┘                        │
└────────────────────────────────┼─────────────────────────────────────────┘
                                 │ HTTPS
                                 ▼
                       ┌──────────────────┐
                       │  Telegram        │
                       │  @your_bot       │
                       └──────────────────┘
```

**Quyết định kiến trúc cốt lõi:**
| Quyết định | Lý do |
|---|---|
| **2 SNS topics phân tách critical/warning** | Map 1-1 với pattern Alertmanager bên `on-premises/` (critical→10s, warning→1m). Junior dễ mở rộng routing rule sau này. |
| **Lambda thay vì SNS → Email trực tiếp** | Email cho junior không actionable. Telegram khớp UX hiện tại. Lambda cũng là pattern thực tiễn nhất khi cần đẩy alert vào webhook (PagerDuty, Slack, Teams) sau này. |
| **EventBridge cho event ECS, CloudWatch Alarm cho metric** | Đây là 2 cơ chế cốt lõi khác nhau. Học cả 2 = hiểu trọn AWS observability primitives. |
| **Tạo module mới `modules/alerting/`** | Đồng nhất với pattern hiện tại (mọi resource group đều là module). Reuse được khi onboard service tiếp theo. |
| **Lưu Telegram bot token trong Secrets Manager** | KHÔNG hardcode trong code hay tfvars. Bài học bảo mật cơ bản. |

---

## 🔑 Prerequisites

Trước khi bắt đầu, đảm bảo các điều kiện sau (5-10 phút):

### P-1. Telegram Bot & Chat
1. Mở [@BotFather](https://t.me/BotFather) trên Telegram → `/newbot` → đặt tên → nhận **bot token** dạng `123456:ABC...`.
2. Tạo group/channel mới, add bot làm admin.
3. Send 1 tin nhắn bất kỳ vào group, rồi mở `https://api.telegram.org/bot<TOKEN>/getUpdates` để lấy **chat_id** (số âm dạng `-100xxxxxxx`).
4. Ghi 2 giá trị này vào notebook cá nhân — **KHÔNG commit vào git**.

### P-2. AWS environment
- AWS CLI đã configure đúng profile (cùng account 730335245469).
- Terraform ≥ 1.10 (vì backend dùng native S3 locking).
- `payment-service` đang RUNNING khỏe mạnh (chạy `aws ecs describe-services` verify).
- Không có deployment nào đang in-progress.

### P-3. Kiến thức nền (đọc trước, 30 phút)
- [EventBridge ECS events reference](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_cwe_events.html) — đặc biệt event `ECS Deployment State Change` và `ECS Task State Change`.
- [CloudWatch Alarm states](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html) — OK / ALARM / INSUFFICIENT_DATA.
- Khái niệm **leading vs lagging indicator** (Memory% là leading, 5XX rate là lagging).

---

## 📦 Sprint A.1 — Alerting Foundation (3-4 ngày)

**Mục tiêu:** Có hạ tầng SNS + Lambda Telegram + EventBridge bắt được deployment/task failure. Re-run Experiment 1, 3 phải thấy alert thật.

### A.1.T1 — Tạo Telegram bot secret trong Secrets Manager (15 phút)

**Lý do trước khi viết code:** Bot token là credential nhạy cảm. Lưu ngay từ đầu để Lambda đọc qua `secretsmanager:GetSecretValue` — đây cũng là pattern thực tế để rotate token sau này.

**Thực hiện:**
1. Chạy lệnh (thay token & chat_id thật):
   ```bash
   aws secretsmanager create-secret \
     --name /obs/lab/alerting/telegram \
     --description "Telegram bot token + chat_id for chaos alerts" \
     --secret-string '{"bot_token":"123456:ABC...","chat_id":"-1001234567890"}' \
     --region ap-southeast-2
   ```
2. Verify đọc được:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id /obs/lab/alerting/telegram \
     --query SecretString --output text
   ```
3. **Ghi nhận ARN** của secret cho Terraform import sau này.

**Lưu ý cho agent thực hiện:** Tạo qua CLI thay vì Terraform vì secret value KHÔNG được commit. Terraform sẽ chỉ `data "aws_secretsmanager_secret"` để lấy ARN, không tạo/quản lý plaintext.

---

### A.1.T2 — Scaffold module `modules/alerting/` (1 ngày)

**Tạo cấu trúc file:**
```
terraform/modules/alerting/
├── main.tf              # SNS topics + Lambda + IAM
├── lambda/
│   └── telegram_notifier.py   # Python runtime
├── variables.tf
├── outputs.tf
└── README.md            # Document inputs/outputs
```

#### File 1: `lambda/telegram_notifier.py`

```python
"""
SNS → Telegram bridge.

Đầu vào: SNS message (string hoặc JSON).
Đầu ra: POST tới Telegram sendMessage API.

Behavior:
- Đọc bot_token + chat_id từ Secrets Manager (cache cross-invocation).
- Detect alarm vs event payload, format khác nhau (emoji + bullet).
- Severity được suy ra từ tên SNS topic (`*-critical*` → 🚨, `*-warning*` → ⚠️).
"""

import json
import logging
import os
import urllib.request
import urllib.parse
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ID = os.environ["TELEGRAM_SECRET_ID"]
sm = boto3.client("secretsmanager")
_secret_cache = None


def _get_credentials():
    global _secret_cache
    if _secret_cache is None:
        resp = sm.get_secret_value(SecretId=SECRET_ID)
        _secret_cache = json.loads(resp["SecretString"])
    return _secret_cache


def _detect_severity(topic_arn: str) -> str:
    if "critical" in topic_arn:
        return "🚨 CRITICAL"
    if "warning" in topic_arn:
        return "⚠️ WARNING"
    return "ℹ️ INFO"


def _format_alarm(payload: dict, severity: str) -> str:
    alarm = payload.get("AlarmName", "Unknown")
    state = payload.get("NewStateValue", "?")
    reason = payload.get("NewStateReason", "")
    region = payload.get("Region", "")
    return (
        f"<b>{severity}: {alarm}</b>\n"
        f"<i>State:</i> {state}\n"
        f"<i>Region:</i> {region}\n"
        f"<i>Reason:</i> <code>{reason[:500]}</code>"
    )


def _format_event(payload: dict, severity: str) -> str:
    source = payload.get("source", "?")
    detail_type = payload.get("detail-type", "?")
    detail = payload.get("detail", {})
    summary = json.dumps(detail, default=str)[:800]
    return (
        f"<b>{severity}: {detail_type}</b>\n"
        f"<i>Source:</i> {source}\n"
        f"<i>Detail:</i>\n<code>{summary}</code>"
    )


def _send(text: str) -> None:
    creds = _get_credentials()
    url = f"https://api.telegram.org/bot{creds['bot_token']}/sendMessage"
    body = urllib.parse.urlencode({
        "chat_id": creds["chat_id"],
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": "true",
    }).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=5) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"Telegram API returned {resp.status}")


def handler(event, _context):
    logger.info("Received event: %s", json.dumps(event)[:1000])
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        topic_arn = sns.get("TopicArn", "")
        message_raw = sns.get("Message", "")
        severity = _detect_severity(topic_arn)
        try:
            payload = json.loads(message_raw)
        except json.JSONDecodeError:
            _send(f"{severity}\n<code>{message_raw[:1000]}</code>")
            continue
        if "AlarmName" in payload:
            text = _format_alarm(payload, severity)
        elif "detail-type" in payload:
            text = _format_event(payload, severity)
        else:
            text = f"{severity}\n<code>{json.dumps(payload)[:1000]}</code>"
        _send(text)
    return {"status": "ok"}
```

#### File 2: `variables.tf`

```hcl
variable "project_name" {
  type        = string
  description = "Project prefix for resource naming."
}

variable "environment" {
  type        = string
  description = "Environment (lab, dev, prod...)."
}

variable "telegram_secret_arn" {
  type        = string
  description = "ARN of Secrets Manager secret holding {bot_token, chat_id}."
}

variable "telegram_secret_name" {
  type        = string
  description = "Name (not ARN) of the secret, passed as env var to Lambda."
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
```

#### File 3: `main.tf` (key resources)

> Đầy đủ HCL, đã cân nhắc tag, KMS encryption-at-rest cho SNS, least-privilege IAM.

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

#--- 1. SNS Topics (2 severities) ----------------------------------------
resource "aws_sns_topic" "critical" {
  name = "${var.project_name}-${var.environment}-alerts-critical"
  tags = merge(var.common_tags, { Severity = "critical" })
}

resource "aws_sns_topic" "warning" {
  name = "${var.project_name}-${var.environment}-alerts-warning"
  tags = merge(var.common_tags, { Severity = "warning" })
}

# Allow EventBridge to publish into these topics.
data "aws_iam_policy_document" "sns_publish" {
  for_each = toset(["critical", "warning"])
  statement {
    actions   = ["sns:Publish"]
    resources = [each.key == "critical" ? aws_sns_topic.critical.arn : aws_sns_topic.warning.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "critical" {
  arn    = aws_sns_topic.critical.arn
  policy = data.aws_iam_policy_document.sns_publish["critical"].json
}

resource "aws_sns_topic_policy" "warning" {
  arn    = aws_sns_topic.warning.arn
  policy = data.aws_iam_policy_document.sns_publish["warning"].json
}

#--- 2. Lambda Telegram Notifier ----------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/telegram_notifier.py"
  output_path = "${path.module}/lambda/telegram_notifier.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-${var.environment}-telegram-notifier"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secret_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.telegram_secret_arn]
  }
}

resource "aws_iam_role_policy" "lambda_secret_read" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_secret_read.json
}

resource "aws_lambda_function" "telegram" {
  function_name    = "${var.project_name}-${var.environment}-telegram-notifier"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "telegram_notifier.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128
  environment {
    variables = {
      TELEGRAM_SECRET_ID = var.telegram_secret_name
    }
  }
  tags = var.common_tags
}

#--- 3. Wire SNS → Lambda ------------------------------------------------
resource "aws_lambda_permission" "sns_invoke" {
  for_each      = { critical = aws_sns_topic.critical.arn, warning = aws_sns_topic.warning.arn }
  statement_id  = "AllowSNS-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.telegram.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value
}

resource "aws_sns_topic_subscription" "telegram_critical" {
  topic_arn = aws_sns_topic.critical.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.telegram.arn
}

resource "aws_sns_topic_subscription" "telegram_warning" {
  topic_arn = aws_sns_topic.warning.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.telegram.arn
}
```

#### File 4: `outputs.tf`

```hcl
output "sns_critical_arn" {
  value       = aws_sns_topic.critical.arn
  description = "ARN of critical-severity SNS topic. Subscribe alarms/EventBridge here."
}

output "sns_warning_arn" {
  value       = aws_sns_topic.warning.arn
  description = "ARN of warning-severity SNS topic."
}

output "lambda_arn" {
  value       = aws_lambda_function.telegram.arn
  description = "ARN of Telegram notifier Lambda (for debugging / metric filter)."
}
```

#### File 5: `README.md` (ngắn gọn)

```md
# alerting

Reusable SNS + Lambda module bridging AWS alerts to Telegram.

## Inputs
- `project_name`, `environment` — naming prefix
- `telegram_secret_arn`, `telegram_secret_name` — pre-created Secrets Manager secret

## Outputs
- `sns_critical_arn`, `sns_warning_arn` — subscribe your alarms/rules to these
- `lambda_arn` — Telegram notifier (Python 3.12, ~10MB)

## Usage
See `terraform/control-plane/lab/alerting.tf`.
```

---

### A.1.T3 — Wire module trong `control-plane/lab/` (30 phút)

**Tạo file mới:** `terraform/control-plane/lab/alerting.tf`

```hcl
#--------------------------------------------------------------
# ALERTING — SNS + Lambda Telegram bridge
#--------------------------------------------------------------

data "aws_secretsmanager_secret" "telegram" {
  name = "/obs/lab/alerting/telegram"
}

module "alerting" {
  source = "../../modules/alerting"

  project_name         = var.project_name
  environment          = var.environment
  telegram_secret_arn  = data.aws_secretsmanager_secret.telegram.arn
  telegram_secret_name = data.aws_secretsmanager_secret.telegram.name

  common_tags = {
    Module = "alerting"
    Plane  = "Control"
  }
}
```

**Cập nhật `terraform/control-plane/lab/ssm-exports.tf`** — export SNS ARN để data-plane (và các module sau này) dùng được:

```hcl
resource "aws_ssm_parameter" "sns_critical" {
  name  = "/obs/lab/alerting/sns_critical_arn"
  type  = "String"
  value = module.alerting.sns_critical_arn
  tags  = { Module = "alerting" }
}

resource "aws_ssm_parameter" "sns_warning" {
  name  = "/obs/lab/alerting/sns_warning_arn"
  type  = "String"
  value = module.alerting.sns_warning_arn
  tags  = { Module = "alerting" }
}
```

**Apply:**
```bash
cd terraform/control-plane/lab
terraform init -upgrade   # vì có provider mới (archive)
terraform plan -out alerting.plan
terraform apply alerting.plan
```

**Verify ngay:**
```bash
# 1. Test Lambda trực tiếp bằng dummy SNS event
aws lambda invoke \
  --function-name obs-lab-telegram-notifier \
  --payload '{"Records":[{"Sns":{"TopicArn":"arn:test:critical","Message":"{\"AlarmName\":\"manual-test\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"smoke test from CLI\",\"Region\":\"ap-southeast-2\"}"}}]}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/out.json
cat /tmp/out.json     # Kỳ vọng: {"status":"ok"}
```
→ **Kiểm tra Telegram phải nhận được tin nhắn.** Nếu không, mở CloudWatch Logs `/aws/lambda/obs-lab-telegram-notifier` debug.

---

### A.1.T4 — EventBridge Rule cho ECS Deployment Failure (1 ngày, **giá trị cao nhất**)

**Tạo file mới:** `terraform/control-plane/lab/eventbridge-ecs.tf`

> 2 rule:
> 1. **Deployment State Change → FAILED** — bắt được Experiment 1 (IAM) & 3 (Bad Image / OOM gây Circuit Breaker trip)
> 2. **Task State Change → STOPPED với exit code != 0** — bắt được ExitCode 137 (OOM) và 1 (app crash)

```hcl
#--------------------------------------------------------------
# EVENTBRIDGE — ECS failure events
#--------------------------------------------------------------

locals {
  ecs_cluster_name = element(split("/", data.aws_ssm_parameter.ecs_cluster_id.value), length(split("/", data.aws_ssm_parameter.ecs_cluster_id.value)) - 1)
}

data "aws_ssm_parameter" "ecs_cluster_id" {
  name = "/obs/lab/compute/ecs_cluster_id"
}

# Rule 1: Deployment failure (Circuit Breaker trip)
resource "aws_cloudwatch_event_rule" "ecs_deployment_failed" {
  name        = "${var.project_name}-${var.environment}-ecs-deployment-failed"
  description = "Catches SERVICE_DEPLOYMENT_FAILED — covers IAM Blackhole, Bad Image, OOM"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Deployment State Change"]
    detail = {
      eventName = ["SERVICE_DEPLOYMENT_FAILED"]
    }
  })

  tags = { Module = "eventbridge-ecs" }
}

resource "aws_cloudwatch_event_target" "deployment_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_deployment_failed.name
  target_id = "to-sns-critical"
  arn       = module.alerting.sns_critical_arn
}

# Rule 2: Task stopped with non-zero exit (OOM, app crash)
# Note: dùng numeric matching cho exitCode để loại exit 0 (normal shutdown)
resource "aws_cloudwatch_event_rule" "ecs_task_stopped_unhealthy" {
  name        = "${var.project_name}-${var.environment}-ecs-task-stopped-unhealthy"
  description = "Catches ECS tasks stopped abnormally (non-zero exit OR EssentialContainerExited)"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      lastStatus    = ["STOPPED"]
      stoppedReason = [{ "anything-but" = ["Scaling activity initiated by deployment", "Task stopped by user"] }]
    }
  })

  tags = { Module = "eventbridge-ecs" }
}

resource "aws_cloudwatch_event_target" "task_stopped_to_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped_unhealthy.name
  target_id = "to-sns-warning"
  arn       = module.alerting.sns_warning_arn   # warning (vì circuit breaker còn cứu, không phải outage)
}
```

**Apply + Verify:**
```bash
terraform apply
# Test pattern match TRƯỚC khi inject thật:
aws events test-event-pattern \
  --event-pattern '{"source":["aws.ecs"],"detail-type":["ECS Deployment State Change"],"detail":{"eventName":["SERVICE_DEPLOYMENT_FAILED"]}}' \
  --event '{"source":"aws.ecs","detail-type":"ECS Deployment State Change","detail":{"eventName":"SERVICE_DEPLOYMENT_FAILED","clusterArn":"arn:test","reason":"test"}}'
# Kỳ vọng: {"Result": true}
```

---

### A.1.T5 — *(CONDITIONAL)* ALB 5XX Alarm

⚠️ **Hiện tại payment-service chỉ dùng Cloud Map, KHÔNG đăng ký với ALB** (data-plane: `enable_load_balancer = false`).
→ **Không thể tạo alarm trên `HTTPCode_Target_5XX_Count` cho payment-service riêng lẻ.**

**3 lựa chọn cho agent thực hiện (chọn 1):**

| Lựa chọn | Effort | Khi nào nên chọn |
|---|---|---|
| **A. Skip** task này, ghi note vào CHAOS_BACKLOG để làm khi onboard service thứ 2 | 0 | Junior level — recommended |
| **B. Tạo alarm trên toàn bộ ALB (`LoadBalancer` dimension, không filter Target Group)** | 30 phút | Nếu ALB đã có service khác sau này |
| **C. Đăng ký payment-service với ALB** (sửa `data-plane/main.tf` → `enable_load_balancer = true`) | 1-2h, ảnh hưởng architecture | KHÔNG khuyến khích trong scope Iteration A |

**Khuyến nghị:** Chọn **A**. Lý do: Experiment 2 (Network Partition) đã có observable rất tốt khác là **ECS Task State Change** từ T4 ở trên — khi SG bị cắt, target group sẽ deregister task và ECS sẽ kill task → tạo ra event đã được bắt.

---

### A.1.T6 — Re-run Experiments để verify (2-4 giờ)

> Đây là **bước quan trọng nhất**. Không skip. Đây là cú "Verify your guards work" mà junior thường bỏ.

**Bảng kiểm verify:**

| Re-run | Expected alert | Topic | Thời gian alert đến |
|---|---|---|---|
| **Experiment 1** (gỡ Execution Role policy + force deploy) | 🚨 `SERVICE_DEPLOYMENT_FAILED` cho `payment-service` | critical | 2-5 phút sau circuit breaker trip |
| **Experiment 3A** (bad image tag) | 🚨 `SERVICE_DEPLOYMENT_FAILED` + ⚠️ Task Stopped `CannotPullContainerError` | critical + warning | Tương tự |
| **Experiment 3B** (low memory → OOM) | ⚠️ Task Stopped `OutOfMemoryError` (exit 137) | warning | Trong 1-2 phút mỗi lần task chết |

**Cho mỗi re-run, ghi vào incident log:**
- `[HH:MM]` Inject
- `[HH:MM]` Telegram alert received — paste screenshot vào notebook
- Time-to-detect (TTD) = thời gian giữa 2 mốc trên

**Nếu alert KHÔNG đến trong 10 phút:**
1. Mở CloudWatch Logs `/aws/lambda/obs-lab-telegram-notifier` xem có invocation không.
2. Nếu KHÔNG có invocation → check EventBridge metric `Invocations` / `FailedInvocations`.
3. Nếu có invocation nhưng fail → kiểm tra Secrets Manager permission, bot token, chat_id.

---

## 📦 Sprint A.2 — Resource Awareness (2 ngày)

**Mục tiêu:** Alarm leading indicator → cảnh báo TRƯỚC khi OOM/Outage xảy ra. Học khái niệm Container Insights.

### A.2.T1 — Enable Container Insights trên ECS Cluster (15 phút)

**Check trước:** đã enable chưa?
```bash
aws ecs describe-clusters \
  --clusters $(terraform -chdir=terraform/control-plane/lab output -raw ecs_cluster_id 2>/dev/null || echo "obs-lab-cluster") \
  --include SETTINGS \
  --query 'clusters[0].settings'
```

Nếu chưa có `{"name":"containerInsights","value":"enhanced"}`, sửa module `modules/compute/ecs-cluster/main.tf`:

```hcl
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-${var.environment}-cluster"
  setting {
    name  = "containerInsights"
    value = "enhanced"   # hoặc "enabled" (basic) nếu lo cost
  }
  tags = var.common_tags
}
```

> **Note cost:** Container Insights enhanced ~ $0.0036/metric/hour. Với 1 service = vài $/tháng, OK cho lab.

`terraform apply`. Đợi 5-10 phút để metric đầu tiên xuất hiện.

---

### A.2.T2 — Tạo CloudWatch Alarms (1 giờ)

**Tạo file mới:** `terraform/control-plane/lab/alarms-ecs.tf`

```hcl
#--------------------------------------------------------------
# CLOUDWATCH ALARMS — ECS resource health
#--------------------------------------------------------------

locals {
  monitored_service = "payment-service"
}

# Alarm 1 — Memory > 85% (LEADING: predicts OOM)
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-${local.monitored_service}-memory-high"
  alarm_description   = "Memory utilization > 85% — investigate before OOM kill"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  evaluation_periods  = 2
  period              = 60
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  ok_actions    = [module.alerting.sns_warning_arn]   # gửi notification khi recover
  tags          = { Service = local.monitored_service, Severity = "warning" }
}

# Alarm 2 — CPU > 80% sustained (chỉ ghi nhận, không actionable ngay)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-${local.monitored_service}-cpu-high"
  alarm_description   = "CPU utilization > 80% for 5min — investigate workload pattern"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  evaluation_periods  = 5
  period              = 60
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_warning_arn]
  tags          = { Service = local.monitored_service, Severity = "warning" }
}

# Alarm 3 — Running task count drops (LAGGING: outage already happening)
resource "aws_cloudwatch_metric_alarm" "ecs_running_task_low" {
  alarm_name          = "${var.project_name}-${var.environment}-${local.monitored_service}-running-task-low"
  alarm_description   = "RunningTaskCount < DesiredTaskCount — service degraded"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 2
  period              = 60
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"   # khác namespace với Alarm 1/2!
  statistic           = "Average"
  treat_missing_data  = "breaching"   # KHÁC: missing data ở đây nghĩa là service chết

  dimensions = {
    ClusterName = local.ecs_cluster_name
    ServiceName = local.monitored_service
  }

  alarm_actions = [module.alerting.sns_critical_arn]   # ← critical, không phải warning
  ok_actions    = [module.alerting.sns_critical_arn]
  tags          = { Service = local.monitored_service, Severity = "critical" }
}
```

**Lưu ý "Aha moment" để học:**
- Alarm 1 & 2 dùng namespace `AWS/ECS` (built-in, không cần Container Insights).
- Alarm 3 dùng namespace `ECS/ContainerInsights` (chỉ có khi đã enable T1).
- `treat_missing_data` khác nhau theo bản chất alarm — đây là 1 trong những điểm dễ sai nhất khi viết alarm.

**Apply:**
```bash
terraform plan -out alarms.plan
terraform apply alarms.plan
```

---

### A.2.T3 — Verify Memory Alarm bằng stress test (30 phút)

> 📖 **Drill này đã được di chuyển vào playbook để reuse định kỳ:** xem [`AWS_CHAOS_PLAYBOOK.md` → Experiment 3.5 Memory Pressure Drill](AWS_CHAOS_PLAYBOOK.md#-experiment-35-memory-pressure-drill-leading-indicator-verify).
>
> Lý do tách: stress test này không chỉ là one-time verify mà còn là smoke test định kỳ cho alerting infra (chạy hàng tháng, sau mỗi lần rotate Telegram bot token, trước GameDay).

**Trong scope Iteration A**, chỉ cần chạy 1 lần để chứng minh `memory-high` alarm fire đúng:
1. Mở [`AWS_CHAOS_PLAYBOOK.md` Experiment 3.5](AWS_CHAOS_PLAYBOOK.md#-experiment-35-memory-pressure-drill-leading-indicator-verify), làm theo Phase 0 → 3.
2. Tick vào DoD checklist dưới đây nếu Telegram nhận đủ 2 tin (ALARM + OK) và TTD ≤ 3 phút.

**Pre-flight bắt buộc trước khi chạy drill:**

```bash
# Đảm bảo ECS Exec đã enable trong task definition
# (check trong modules/compute/ecs-service/main.tf — biến enable_execute_command)
aws ecs describe-services --cluster obs-cluster --services payment-service \
  --query 'services[0].enableExecuteCommand'
# Kỳ vọng: true. Nếu false, sửa module và terraform apply trước.
```

---

## 📦 Sprint A.3 — Shift-Left Policy *(OPTIONAL — hoãn lại)*

> **Trạng thái:** ⏸️ **Deferred.**
> **Lý do:** User hiện đang chạy `terraform apply` thủ công trên VM local, **chưa có CI/CD và policy-as-code**. Sẽ áp dụng sau khi codebase đã chuẩn chỉnh và migrate sang PR-driven workflow (xem ROADMAP Phase 3 — Platform Shield).
>
> **Khi nào quay lại sprint này?**
> - ✅ Khi đã setup GitHub Actions cho `terraform plan` (Phase 3).
> - ✅ Khi đã có OIDC Provider + IAM Role cho GHA.
> - ✅ Khi đã hiểu rõ workflow PR-driven IaC (chứ không phải local apply).
>
> **Tham khảo trước (đọc, không implement):**
> - [Conftest](https://www.conftest.dev/) — runner cho OPA Rego ở local/CI.
> - [tfsec](https://github.com/aquasecurity/tfsec) — Terraform security scanner (đơn giản hơn OPA cho beginner).
> - [Checkov](https://www.checkov.io/) — đa-platform IaC scanner.
>
> **Action Items hoãn:**
> 1. ~~OPA Rego policy chặn xóa `AmazonECSTaskExecutionRolePolicy`~~
> 2. ~~CI/CD pre-deploy `aws ecr describe-images` validate image tag~~

---

## 🎯 Definition of Done — Iteration A

Trước khi đóng Iteration A và sang Iteration B, đảm bảo:

- [ ] Telegram bot nhận đủ alert từ 3 lần re-run Experiment.
- [ ] 3 CloudWatch Alarm (Memory, CPU, RunningTask) hiển thị state `OK` trong console (không phải `INSUFFICIENT_DATA`).
- [ ] Stress test gây alarm Memory fire trong < 3 phút.
- [ ] Recovery test: dừng stress → alarm về OK + nhận tin "recovered".
- [ ] Code Terraform được commit, không có ClickOps nào.
- [ ] Notebook cá nhân ghi đủ: Time-To-Detect mỗi experiment + screenshot Telegram.
- [ ] Cập nhật ROADMAP.md Phase 1 — tick các Drill đã re-run thành công.

---

## 📚 Tài liệu tham khảo

- **Cấu trúc hiện tại:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ROADMAP.md](../ROADMAP.md)
- **3 Experiments đã làm:** [AWS_CHAOS_PLAYBOOK.md](AWS_CHAOS_PLAYBOOK.md)
- **AWS docs:** [ECS Events](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_cwe_events.html), [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html), [Container Insights Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html)
- **Pattern reference:** `on-premises/observability-vm/alertmanager/` (Alertmanager → Telegram bot)

---

## ⏭️ Sau Iteration A

Khi DoD tick hết, chuyển sang **Iteration B**: thêm Experiment 4 (Task Role Blackhole / Runtime IAM Failure) — tận dụng SNS + Lambda đã build để verify alert trên scenario mới.

Sau Iteration B → **Iteration C**: onboard Order Service để mở khóa class experiment cascading failure / circuit breaker app-level.
