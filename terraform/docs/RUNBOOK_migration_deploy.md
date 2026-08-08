# RUNBOOK: Migration Deploy (Phase 2.1)

> **Audience**: Người vận hành (operator) — không cần hiểu kiến trúc, chỉ cần làm đúng bước.
>
> **Khi nào dùng**: Mỗi khi thay đổi `init-app.sql`, `run-migration.sh`, hoặc `Dockerfile` trong `terraform/migration/`.

---

## ⚠️ Bẫy Đồng Bộ (Đọc Trước Khi Làm)

`init-app.sql` tồn tại ở **2 nơi**:

1. **Trong repo** — Terraform dùng `filemd5()` để tính hash, quyết định có re-trigger migration không.
2. **Baked trong Docker image** — Migration task chạy SQL từ `/migrations/init-app.sql` trong container.

**Hậu quả nếu quên rebuild image**: Terraform thấy hash đổi → trigger migration → nhưng container vẫn chạy SQL cũ.

**Quy tắc**: Luôn đi theo cặp: **sửa SQL → rebuild image → push tag mới → bump `image_tags`**.

---

## Các Bước Thực Hiện

### Bước 0: Pre-flight Checklist

```bash
# Verify bạn đang ở đúng repo và branch
git status
git diff --stat   # Xem những gì đã thay đổi

# Verify AWS credentials
aws sts get-caller-identity
```

| Check | Lệnh | Kỳ vọng |
|-------|-------|---------|
| AWS credentials | `aws sts get-caller-identity` | Account ID đúng |
| Docker daemon | `docker info > /dev/null 2>&1 && echo OK` | `OK` |
| Terraform version | `terraform version` | >= 1.7.0 |
| SQL syntax | Đọc lại `init-app.sql` | Không có lỗi cú pháp |

---

### Bước 1: Build & Push Migration Image

```bash
cd terraform/migration

# Login ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin \
  <account>.dkr.ecr.ap-southeast-2.amazonaws.com

# Build (tag = version mới, ví dụ v1.1.0)
docker build -t obs-migration:v1.1.0 .

# Tag + Push
docker tag obs-migration:v1.1.0 \
  <account>.dkr.ecr.ap-southeast-2.amazonaws.com/obs/migration:v1.1.0
docker push \
  <account>.dkr.ecr.ap-southeast-2.amazonaws.com/obs/migration:v1.1.0
```

**Verify**: Image xuất hiện trong ECR console hoặc:

```bash
aws ecr describe-images \
  --repository-name obs/migration \
  --query 'imageDetails[?contains(imageTags, `v1.1.0`)]'
```

---

### Bước 2: Control Plane — Plan Trước, Soi Kỹ

```bash
cd terraform/control-plane/lab

# Bump image tag (nếu dùng tfvars)
# image_tags = { migration = "v1.1.0" }

terraform plan
```

**Checklist khi đọc plan output:**

| Expect | Resource | Action |
|--------|----------|--------|
| ✅ Mới | `aws_secretsmanager_secret.app_user` | `+ create` (lần đầu) |
| ✅ Mới | `aws_ssm_parameter.db_app_secret_arn` | `+ create` (lần đầu) |
| ✅ Update | `aws_ecs_task_definition.migration` | `~ update` (revision mới) |
| ✅ Replace | `null_resource.run_migration` | `-/+ replace` (sẽ chạy migration) |
| 🛑 STOP | Bất kỳ resource nào bị `destroy` ngoài ý muốn | **Dừng lại, kiểm tra** |

```bash
# Nếu plan OK:
terraform apply
```

**Quan sát**: Migration task chạy ~30-60s. Nếu FAIL:

```bash
# Xem logs
aws logs tail /ecs/obs/lab/migration --since 5m --format short
```

---

### Bước 3: Verify SSM Gate

```bash
aws ssm get-parameter \
  --name "/obs/lab/migration/status" \
  --query Parameter.Value --output text
# Kỳ vọng: SUCCESS

aws ssm get-parameter \
  --name "/obs/lab/migration/schema_version" \
  --query Parameter.Value --output text
# Kỳ vọng: 2.1.0

aws ssm get-parameter \
  --name "/obs/lab/migration/last_success" \
  --query Parameter.Value --output text
# Kỳ vọng: timestamp gần đây
```

**Nếu status = FAILED**: Xem CloudWatch logs → fix SQL → quay lại Bước 1 với tag mới.

---

### Bước 4: Data Plane — Deploy Order Service

```bash
cd terraform/data-plane/order-service

terraform plan
# check "migration_gate" phải pass (không có warning/error)
# DB_SECRET phải trỏ tới app-secret-arn (DML-only), KHÔNG phải master secret

terraform apply
```

---

### Bước 5: Verification Checklist (Definition of Done)

**✅ 1. Migration audit trail**

```bash
aws logs tail /ecs/obs/lab/migration --since 30m --format short | tail -20
# Kỳ vọng: "Migration verified: X tables, 5 products..." + "app_user: DML-only ✓"
```

**✅ 2. Gate parameters**

```bash
aws ssm get-parameters \
  --names "/obs/lab/migration/status" "/obs/lab/migration/schema_version" \
  --query 'Parameters[*].{Name:Name,Value:Value}' --output table
# Kỳ vọng: status=SUCCESS, schema_version=2.1.0
```

**✅ 3. Data Plane deployed**

```bash
aws ecs describe-services --cluster obs-lab --services order-service \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'
# Kỳ vọng: status=ACTIVE, running=desired
```

**✅ 4. Positive test — app_user connects with DML**

```bash
TASK_ARN=$(aws ecs list-tasks --cluster obs-lab --service-name order-service \
  --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster obs-lab --task "$TASK_ARN" \
  --container order-service --interactive \
  --command 'python -c "
import os, json, psycopg2
s = json.loads(os.environ[\"DB_SECRET\"])
conn = psycopg2.connect(host=os.environ[\"DB_HOST\"], port=os.environ[\"DB_PORT\"],
    dbname=os.environ[\"DB_NAME\"], user=s[\"username\"], password=s[\"password\"],
    sslmode=\"require\")
cur = conn.cursor()
cur.execute(\"SELECT current_user\")
print(\"Connected as:\", cur.fetchone()[0])
cur.execute(\"SELECT count(*) FROM products\")
print(\"Products:\", cur.fetchone()[0])
"'
# Kỳ vọng: Connected as: app_user | Products: 5
```

**✅ 5. NEGATIVE TEST — chứng minh DML-only là THẬT (quan trọng nhất)**

```bash
aws ecs execute-command --cluster obs-lab --task "$TASK_ARN" \
  --container order-service --interactive \
  --command 'python -c "
import os, json, psycopg2
s = json.loads(os.environ[\"DB_SECRET\"])
conn = psycopg2.connect(host=os.environ[\"DB_HOST\"], port=os.environ[\"DB_PORT\"],
    dbname=os.environ[\"DB_NAME\"], user=s[\"username\"], password=s[\"password\"],
    sslmode=\"require\")
cur = conn.cursor()
try:
    cur.execute(\"CREATE TABLE ddl_should_fail(id int)\")
    print(\"🚨 FAIL: DDL succeeded — privilege separation BROKEN\")
except Exception as e:
    print(\"✅ PASS: DDL blocked —\", str(e).strip()[:80])
"'
# Kỳ vọng: ✅ PASS: DDL blocked — permission denied for schema public
```

**✅ 6. E2E — gọi API thật**

```bash
curl -s -w '\nHTTP %{http_code}\n' \
  -X POST https://app.bd-apa-coi.com/process \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 1}'
# Kỳ vọng: HTTP 200, order tạo thành công
```

---

## RDS Failover Recovery

> Dùng khi RDS Multi-AZ failover xảy ra (planned hoặc unplanned).
> Điền số liệu thực đo vào bảng sau khi chạy Drill 11.

**Hành vi kỳ vọng**: App tự phục hồi, không cần human intervention.

**Nếu cần can thiệp**:

```bash
# 1. Kiểm tra RDS status
aws rds describe-db-instances \
  --db-instance-identifier obs-lab-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone}'
# Kỳ vọng: Status=available

# 2. Kiểm tra app reconnect
aws ecs describe-services --cluster obs-lab --services order-service \
  --query 'services[0].{running:runningCount,desired:desiredCount}'
# Nếu running < desired: ECS đang restart tasks (bình thường)

# 3. Force restart nếu app không tự phục hồi sau 5 phút
aws ecs update-service --cluster obs-lab --service order-service \
  --force-new-deployment
```

**Bảng đo lường (điền sau Drill 11):**

| Metric | Thực đo |
|--------|---------|
| Failover duration | ___ s |
| Tổng 5xx / tổng requests | ___ / ___ |
| User Pain Score | ___ % |
| App tự phục hồi? | Có / Không |

---

## Troubleshooting

### Migration task timeout (>10 phút)

```bash
# Kiểm tra task đang ở state nào
aws ecs describe-tasks \
  --cluster obs-lab \
  --tasks <task-arn> \
  --query 'tasks[0].{status:lastStatus,reason:stoppedReason}'
```

Nguyên nhân phổ biến:
- **PROVISIONING**: Fargate đang pull image → kiểm tra ECR permissions
- **PENDING**: Không đủ ENI → kiểm tra subnet capacity
- **RUNNING quá lâu**: SQL chạy lâu → kiểm tra `statement_timeout` (120s)

### Data Plane bị chặn bởi migration gate

```bash
# Kiểm tra gate value
aws ssm get-parameter --name "/obs/lab/migration/status" \
  --query Parameter.Value --output text

# Nếu FAILED hoặc parameter không tồn tại:
# → Chạy lại Bước 1-3 trước khi deploy Data Plane
```

### App crash loop sau deploy

```bash
# Kiểm tra app_user có đúng privileges không
# (Cần master credentials để chạy lệnh này)
psql -h <rds-host> -U <master-user> -d app_db -c \
  "SELECT has_table_privilege('app_user', 'orders', 'SELECT');"
# Kỳ vọng: t (true)

psql -h <rds-host> -U <master-user> -d app_db -c \
  "SELECT has_schema_privilege('app_user', 'public', 'CREATE');"
# Kỳ vọng: f (false) — app_user KHÔNG có DDL
```

---

## Rollback

Nếu migration mới gây lỗi:

1. **Revert SQL** trong repo về version trước
2. **Rebuild image** với tag mới (e.g., `v1.0.9-rollback`)
3. **Apply control-plane** → migration re-run với SQL cũ
4. **Verify gate** = SUCCESS
5. **Apply data-plane** nếu cần

> ⚠️ Rollback SQL phải idempotent. `CREATE TABLE IF NOT EXISTS` và `ON CONFLICT DO NOTHING` đảm bảo re-run an toàn. Tuy nhiên, nếu migration mới đã `ALTER TABLE` hoặc `DROP COLUMN`, cần viết reverse migration.

---

## Lưu Ý Đặc Biệt

- **RDS Multi-AZ**: Nếu đổi `multi_az = false → true`, RDS sẽ tạo standby + có downtime ngắn. Làm lúc không có traffic.
- **Secret rotation**: `app_user` secret do Terraform quản lý, **không** auto-rotate như master secret. Khi cần rotate: đổi `random_password` → apply control-plane → migration sync password.
- **Image tag convention**: Dùng semver (`v1.1.0`, `v1.2.0`). Không dùng `latest` — mất traceability.
