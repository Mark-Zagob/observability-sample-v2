# 📐 Kế Hoạch Mở Rộng Ứng Dụng

> Đề xuất mở rộng hệ thống e-commerce từ 6 services lên 10 services, tập trung vào **architectural diversity** để maximize kiến thức DevOps/SRE/Platform khi deploy lên AWS.

---
## Document Metadata
| Field | Value |
|---|---|
| Document Status | 🔄 In Progress (Syncing with Codebase) |
| Last Updated | 2026-07-10 |
| Version | 2.1 (Phase 0 Reality Check & Guardrails Update) |
| Owner | dungtt (Platform Engineering) |

## Document History
| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-05-20 | dungtt | Initial expansion roadmap (6 → 10 services) |
| 2.0 | 2026-06-15 | dungtt | Added Saga Orchestration, CQRS, PgBouncer strategy |
| 2.1 | 2026-07-10 | dungtt | **Reality Check:** Marked Phase 0 App-level as COMPLETED (Codebase over-delivered). Added new Production Guardrails to "Patterns đã có". Updated PgBouncer Risk Assessment based on new DB Driver Resilience. Adjusted Phase 4 SLO math to leverage existing Traffic Source Tagging. |
---

## Mục Tiêu

| # | Mục tiêu | Đo lường |
|---|---------|---------|
| 1 | Tăng **architectural diversity** | Thêm ≥ 3 communication patterns mới |
| 2 | Tạo **failure scenarios phức tạp hơn** | Cascading failures qua ≥ 4 services |
| 3 | Học thêm **design patterns production-grade** | Saga, CQRS, Circuit Breaker |
| 4 | Giữ chi phí AWS hợp lý | Không tăng quá 40% so với hiện tại |

---

## Hiện Trạng (6 Services)

```
Web UI → API Gateway → Order Service → Payment Service
                              ↕                ↕
                         PostgreSQL          Redis
                              ↕
                           Kafka
                         ↙      ↘
            Notification Worker  Inventory Worker
```

**Patterns đã có:**
- ✅ Sync HTTP (request-response)
- ✅ Async Event-driven (Kafka pub/sub)
- ✅ Cache-Aside (Redis)
- ✅ BFF (API Gateway)
- ✅ Idempotent Processing (processed_events table + Redis Lua Script IdempotencyGuard)
- ✅ Pessimistic Locking (SELECT FOR UPDATE)
- ✅ Distributed Trace Propagation (W3C traceparent qua Kafka headers)
- ✅ Circuit Breaker (`pybreaker` trong Payment Service)
- ✅ Health check endpoint chuẩn (liveness/readiness via `shared/health.py`)
- ✅ Structured error response chuẩn (RFC 7807 via `shared/errors.py`)
- ✅ Graceful shutdown (`shared/shutdown_handler.py` — callback registry pattern)
- ✅ HTTP Semantic Mapping (`shared/errors.py` — map business status → HTTP code)
- ✅ Auto-migration (schema on startup, cross-env compatible)
- ✅ Feature flags (`ENABLE_REDIS`, `ENABLE_KAFKA` cho AWS Phase 1)
- ✅ Database Driver Resilience (`shared/db_utils.py` — TCP Keep-Alive, `statement_timeout=30s`, `connect_timeout=5s`)
- ✅ Frontend SRE (`web-ui/app.js` — Page Visibility API chống Phantom Traffic)
- ✅ OTel Histogram Custom Buckets (`shared/otel_setup.py` — Custom boundaries 5ms→10s để P95/P99 chính xác)
- ✅ Kafka Natural Batching (`order-service/app.py` — `linger.ms=50`, `batch.size=16KB`, Backpressure buffer)
- ✅ Traffic Source Tagging (`api-gateway/app.py` — Phân loại `synthetic_probe`, `synthetic_loadtest`, `browser`)
- ✅ Redis Idempotency State Machine (`shared/idempotency.py` — Split TTLs, Lua Scripts atomicity)
- ✅ OTel Sidecar Watchdog (`shared/otel_watchdog.py` — Auto-seppuku nếu ADOT sidecar chết trên ECS)

**Thiếu:**
- ❌ Saga pattern (distributed transaction)
- ❌ CQRS/Data sync (read model khác write model)
- ❌ Authentication/Authorization (JWT propagation)
- ❌ Rate limiting
- ❌ TLS termination (HTTPS)
- ❌ Secrets management (JWT keys, DB passwords)
- ❌ Network segmentation (Docker networks per tier)
- ❌ Resource limits (CPU/memory per container)
- ❌ Backup/Restore procedures
- ❌ Log rotation & retention
- ❌ CI pipeline (lint, test, build)
- ❌ Horizontal scaling (multiple instances + load balancing)

---

## Database Strategy

### Approach: Hybrid (1 Instance, Multiple Databases)

Không dùng shared database (tất cả dùng chung 1 DB), cũng không dùng database-per-instance (mỗi service 1 PostgreSQL riêng). Thay vào đó: **1 PostgreSQL instance, nhiều databases tách biệt theo domain**.

```
PostgreSQL instance (:5432)
  ├── app_db          ← Order, Payment, Inventory, Notification (shared — cùng domain)
  ├── auth_db         ← Auth Service (riêng — sensitive credentials)
  └── shipping_db     ← Shipping Service + Worker (riêng — khác lifecycle)

Redis (:6379)         ← Cache (shared, tất cả services)
OpenSearch (:9200)    ← Search Service (riêng)
```

### Tại sao Hybrid?

| Quyết định | Lý do |
|-----------|-------|
| **app_db shared** | Order, Payment, Inventory cần JOIN bảng `orders` + `products`. Tách ra = phải sync qua event, phức tạp không cần thiết |
| **auth_db riêng** | User credentials (password hash) PHẢI tách biệt — security best practice. Không service nào nên truy cập trực tiếp bảng users |
| **shipping_db riêng** | Khác domain, khác lifecycle. Shipping có thể deploy/migrate schema độc lập mà không ảnh hưởng orders |
| **OpenSearch riêng** | Khác engine hoàn toàn — optimized cho full-text search, không phải relational data |

### DevOps/SRE Learning Value

| Skill | Với Hybrid approach |
|-------|--------------------|
| **Backup/Restore** | Backup từng database riêng: `pg_dump app_db`, `pg_dump auth_db` |
| **Migration** | Migration scripts per-database, deploy độc lập |
| **Connection pooling** | Mỗi service connect đúng database của mình |
| **Access control** | PostgreSQL roles: `app_user` chỉ access `app_db`, `auth_user` chỉ access `auth_db` |
| **Monitoring** | Per-database metrics: connections, query latency, disk usage |
| **AWS mapping** | 1 RDS instance + multiple databases = cost-effective. Hoặc tách auth_db ra RDS riêng khi scale |

### Connection Strings

```bash
# Order, Payment, Inventory, Notification Workers
DATABASE_URL=postgresql://app_user:***@postgres:5432/app_db

# Auth Service
AUTH_DATABASE_URL=postgresql://auth_user:***@postgres:5432/auth_db

# Shipping Service + Worker
SHIPPING_DATABASE_URL=postgresql://shipping_user:***@postgres:5432/shipping_db
```
## Database Migration Plan (`orders` → `app_db`)

Đây là migration procedure bắt buộc trước khi bắt đầu Phase 1 (Auth Service) vì Auth Service cần kết nối tới `auth_db` trên cùng PostgreSQL instance. Migration này cũng là template để tái sử dụng khi tạo `shipping_db` ở Phase 2.

**Migration Approach:** Logical migration với brief downtime (~5-10 phút)

**Rationale:**

- Đơn giản, an toàn, dễ rollback
- Phù hợp với database size nhỏ-vừa (< 10GB)
- Đủ cho lab environment và production giai đoạn đầu

> Alternative (zero-downtime với logical replication) được đề cập ở cuối section này cho trường hợp database lớn hoặc không chấp nhận downtime.

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Data loss trong quá trình dump/restore | Low | Critical | Backup verification trước khi migrate |
| Migration kéo dài hơn dự kiến | Medium | Medium | Test trên staging với production-size data trước |
| Connection string update thiếu service | Medium | High | Verification checklist với `curl /health/ready` |
| Rollback fail | Low | Critical | Giữ nguyên backup file, không xóa cho đến khi verify xong |

### Pre-Migration Checklist (BẮT BUỘC)

Hoàn thành **TẤT CẢ** các bước này TRƯỚC KHI bắt đầu migration:

- [ ] Thông báo stakeholders (nếu production): maintenance window 30 phút
- [ ] Stop traffic generator: `curl -X POST http://localhost:5003/stop`
- [ ] Verify không có in-flight transactions:

```bash
  docker exec postgres psql -U app -d orders \
    -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
  # Expected: 0 hoặc chỉ có chính query này
```

- [ ] Tạo backup và verify:

```bash
  mkdir -p backup
  docker exec postgres pg_dump -U app -d orders > backup/orders_$(date +%Y%m%d_%H%M%S).sql
  ls -lh backup/              # Verify file size > 0
  head -20 backup/orders_*.sql  # Verify có CREATE TABLE statements
```

- [ ] Chuẩn bị rollback script (lưu vào `rollback.sh`)
- [ ] Đảm bảo có đủ disk space (backup size × 2):

```bash
  df -h /var/lib/docker  # hoặc path chứa PostgreSQL volume
```

### Migration Steps

#### Step 0: Tạo script migration (`migration.sh`)

Tạo file `migration.sh` với nội dung sau để đảm bảo reproducibility:

```bash
#!/bin/bash
# Database Migration: orders → app_db
# Run from project root: bash migration.sh
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backup"
mkdir -p "$BACKUP_DIR"

echo "=========================================="
echo "🚀 Database Migration: orders → app_db"
echo "   Started at: $(date)"
echo "=========================================="

# Step 1: Stop application services (giữ postgres + redis chạy)
echo ""
echo "📦 Step 1/6: Stopping application services..."
cd applications-vm/applications
docker compose stop api-gateway order-service payment-service \
  notification-worker inventory-worker traffic-gen web-ui
cd ../..

# Step 2: Backup current database
echo ""
echo "💾 Step 2/6: Backing up 'orders' database..."
docker exec postgres pg_dump -U app -d orders \
  > "$BACKUP_DIR/orders_${TIMESTAMP}.sql"

BACKUP_SIZE=$(stat -c%s "$BACKUP_DIR/orders_${TIMESTAMP}.sql" 2>/dev/null || stat -f%z "$BACKUP_DIR/orders_${TIMESTAMP}.sql")
echo "   ✅ Backup created: $BACKUP_DIR/orders_${TIMESTAMP}.sql ($BACKUP_SIZE bytes)"

if [ "$BACKUP_SIZE" -lt 1000 ]; then
  echo "   ❌ Backup too small, aborting!"
  exit 1
fi

# Step 3: Create new databases + users
echo ""
echo "🏗️  Step 3/6: Creating new databases and users..."
docker exec postgres psql -U app -d postgres <<'EOF'
-- Create app_user với password (change in production!)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user WITH LOGIN PASSWORD 'app_user_secret';
  END IF;
END
$$;

-- Create app_db
SELECT 'CREATE DATABASE app_db OWNER app_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'app_db')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE app_db TO app_user;
EOF

echo "   ✅ Created: app_db + app_user"

# Step 4: Restore data vào app_db
echo ""
echo "♻️  Step 4/6: Restoring data to app_db..."
docker exec -i postgres psql -U app_user -d app_db \
  < "$BACKUP_DIR/orders_${TIMESTAMP}.sql"

# Fix ownership (pg_dump dùng user 'app', cần đổi sang 'app_user')
docker exec postgres psql -U app_user -d app_db <<'EOF'
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Change table ownership
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' OWNER TO app_user';
  END LOOP;

  -- Change sequence ownership
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public' LOOP
    EXECUTE 'ALTER SEQUENCE ' || quote_ident(r.sequencename) || ' OWNER TO app_user';
  END LOOP;
END
$$;

-- Grant schema usage
GRANT ALL ON SCHEMA public TO app_user;
GRANT ALL ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app_user;
EOF

echo "   ✅ Data restored to app_db"

# Step 5: Verify data integrity
echo ""
echo "🔍 Step 5/6: Verifying data integrity..."
ORDERS_OLD=$(docker exec postgres psql -U app -d orders -tAc "SELECT count(*) FROM orders;")
ORDERS_NEW=$(docker exec postgres psql -U app_user -d app_db -tAc "SELECT count(*) FROM orders;")
PRODUCTS_OLD=$(docker exec postgres psql -U app -d orders -tAc "SELECT count(*) FROM products;")
PRODUCTS_NEW=$(docker exec postgres psql -U app_user -d app_db -tAc "SELECT count(*) FROM products;")

echo "   Orders:   old=$ORDERS_OLD  new=$ORDERS_NEW"
echo "   Products: old=$PRODUCTS_OLD new=$PRODUCTS_NEW"

if [ "$ORDERS_OLD" != "$ORDERS_NEW" ] || [ "$PRODUCTS_OLD" != "$PRODUCTS_NEW" ]; then
  echo "   ❌ Data mismatch! Aborting, keeping old database intact."
  exit 1
fi

echo "   ✅ Data integrity verified"

# Step 6: Update docker-compose.yml
echo ""
echo "📝 Step 6/6: Updating connection strings..."
cd applications-vm/applications

# Backup docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak.${TIMESTAMP}

# Update DATABASE_URL cho tất cả services
sed -i.bak 's|postgresql://app:app_secret@postgres:5432/orders|postgresql://app_user:***@postgres:5432/app_db|g' docker-compose.yml

echo "   ✅ docker-compose.yml updated (backup: docker-compose.yml.bak.${TIMESTAMP})"

echo ""
echo "=========================================="
echo "✅ Migration completed successfully!"
echo "   Next: Start services với 'docker compose up -d'"
echo "=========================================="
```

```bash
chmod +x migration.sh
```

#### Step 1: Chạy migration

```bash
bash migration.sh
```

Script sẽ tự động:

1. Stop 7 application services (giữ `postgres`, `redis`, `kafka` chạy)
2. Backup database `orders` → `backup/orders_TIMESTAMP.sql`
3. Tạo `app_db` + `app_user`
4. Restore data vào `app_db`, fix ownership
5. Verify row counts match
6. Update connection strings trong `docker-compose.yml`

#### Step 2: Start services với connection string mới

```bash
cd applications-vm/applications
docker compose up -d
```

#### Step 3: Verification Checklist

- [ ] Health endpoints trả về 200:

```bash
  for port in 5000 5001 5002 5004 5005; do
    echo "Port $port: $(curl -s http://localhost:$port/health/ready | jq -r .status)"
  done
  # Expected: tất cả = "ready"
```

- [ ] Data accessible qua API:

```bash
  curl -s http://localhost:5001/products | jq '.products | length'
  # Expected: 5 (số products trong seed data)

  curl -s http://localhost:5001/orders?limit=5 | jq '.count'
  # Expected: số orders hiện có
```

- [ ] Kafka workers processing events mới:

```bash
  # Tạo test order
  curl -X POST http://localhost:5000/order \
    -H "Content-Type: application/json" \
    -d '{"product_id": 1, "quantity": 1}' | jq .

  # Check workers
  curl -s http://localhost:5004/status | jq '.stats.processed'
  curl -s http://localhost:5005/status | jq '.stats.reserved'
```

- [ ] Metrics flowing tới Prometheus:

```bash
  # Trên Observability VM
  curl -s 'http://localhost:9090/api/v1/query?query=up{job="app-metrics"}' | jq .
```

- [ ] Không có error logs:

```bash
  docker compose logs --tail=50 | grep -i error
  # Expected: không có output hoặc chỉ warnings không liên quan
```

### Rollback Procedure

**Khi nào rollback?**

- Bất kỳ bước nào trong Verification Checklist fail
- Migration chạy quá 15 phút (expected 5-10 phút)
- Data integrity check fail ở Step 5

**Rollback Steps** (restore về trạng thái cũ):

```bash
#!/bin/bash
# rollback.sh - Restore về database 'orders' cũ
set -euo pipefail

echo "🔄 Rolling back to old 'orders' database..."

# Find latest backup
LATEST_BACKUP=$(ls -t ./backup/orders_*.sql | head -1)
echo "   Using backup: $LATEST_BACKUP"

# Stop services
cd applications-vm/applications
docker compose stop

# Restore docker-compose.yml từ backup
LATEST_COMPOSE_BACKUP=$(ls -t docker-compose.yml.bak.* 2>/dev/null | head -1)
if [ -n "$LATEST_COMPOSE_BACKUP" ]; then
  cp "$LATEST_COMPOSE_BACKUP" docker-compose.yml
  echo "   ✅ docker-compose.yml restored"
fi

# Start services (sẽ dùng lại connection string cũ: orders database)
docker compose up -d

echo ""
echo "✅ Rollback completed. Services running với old 'orders' database."
echo "   Old database 'orders' vẫn còn nguyên, data không mất."
```

```bash
bash rollback.sh
```

### Post-Migration Cleanup

> ⚠️ Chỉ chạy **SAU KHI** verify thành công 100%, và giữ 24h để đề phòng.

```bash
# DROP old 'orders' database (CẨN THẬN!)
docker exec postgres psql -U app -d postgres -c "DROP DATABASE orders;"

# Remove old 'app' user (nếu không còn service nào dùng)
docker exec postgres psql -U postgres -c "DROP ROLE app;"

# Xóa backup files (optional - keep 7 days)
find ./backup -name "orders_*.sql" -mtime +7 -delete
```

### Zero-Downtime Alternative (cho database lớn / production critical)

**Khi nào dùng approach này thay vì brief downtime?**

- Database > 10GB (`pg_dump`/restore mất > 30 phút)
- SLA không cho phép downtime > 1 phút
- Có read-heavy workload (có thể switch reads trước, writes sau)

**Approach: Logical Replication với Blue-Green Switch**

**Phase A: Setup replication (zero downtime)**

```sql
-- Trên database cũ (orders) - publisher
ALTER SYSTEM SET wal_level = logical;
-- Restart PostgreSQL để apply
SELECT pg_reload_conf();

CREATE PUBLICATION orders_pub FOR ALL TABLES;

-- Trên PostgreSQL instance (cùng host, khác DB) - subscriber
CREATE SUBSCRIPTION orders_sub
  CONNECTION 'host=localhost port=5432 dbname=orders user=app password=***'
  PUBLICATION orders_pub;

-- Monitor replication lag
SELECT * FROM pg_stat_subscription;
```

**Phase B: Verify sync hoàn tất**

```sql
-- Check all tables synced
SELECT * FROM pg_stat_subscription;
-- srsubstate should be 'r' (ready) for all tables

-- Row count comparison
SELECT schemaname, relname, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

**Phase C: Cutover (downtime ~30 giây)**

1. Stop writes (maintenance mode trên API Gateway)
2. Wait cho replication lag = 0
3. Drop subscription, promote subscriber thành primary
4. Update connection strings
5. Start writes

**Phase D: Cleanup**

```sql
DROP SUBSCRIPTION orders_sub;
DROP PUBLICATION orders_pub;
```

**Trade-offs:**

- ✅ Pros: Downtime < 1 phút, an toàn (có thể abort bất kỳ lúc nào)
- ❌ Cons: Phức tạp, cần hiểu PostgreSQL internals, cần disk space ×2 trong quá trình sync

### DevOps/SRE Learning Value

| Skill | Thực hành qua migration này |
|-------|---------------------------|
| Backup/Restore | `pg_dump`, `pg_restore`, verification queries |
| PostgreSQL administration | `CREATE ROLE`, `GRANT`, ownership transfer, WAL level |
| Script automation | Bash scripting, `set -euo pipefail`, atomic operations |
| Rollback planning | Blue-green approach, backup retention, rollback triggers |
| Zero-downtime techniques | Logical replication, publisher/subscriber model |
| Observability during migration | `pg_stat_activity`, connection count monitoring, health checks |
| Risk management | Pre-flight checklist, verification gates, abort criteria |

---

### 🔧 Các files KHÁC cần update (sau khi migration thành công)

#### 1. `applications-vm/applications/init.sql`

File này hiện tại được mount vào `/docker-entrypoint-initdb.d/init.sql` và chỉ chạy khi PostgreSQL volume trống. Sau migration, bạn cần tạo file mới cho các database mới:

```
applications-vm/applications/
├── init.sql          # Giữ nguyên - seed data cho orders DB (legacy)
├── init-app.sql      # MỚI - sẽ dùng cho app_db
├── init-auth.sql     # MỚI - cho Phase 1 (auth_db)
└── init-shipping.sql # MỚI - cho Phase 2 (shipping_db)
```

> **KHÔNG sửa `init.sql` cũ** vì nó sẽ không chạy nữa (volume đã có data). Thay vào đó, tạo `init-app.sql` chứa schema mới cho Phase 1+ (khi bạn reset volume để test):

```sql
-- init-app.sql (schema cho app_db - dùng khi tạo mới từ đầu)
-- Các bảng: orders, products, processed_events, notifications, inventory_log
-- (copy từ init.sql cũ, chỉ đổi ownership)
```

#### 2. `applications-vm/applications/docker-compose.yml`

Sau khi chạy `migration.sh`, file này đã được tự động update. Nhưng bạn cần review lại và thêm healthcheck cho database mới:

```yaml
services:
  postgres:
    # ... giữ nguyên ...
    environment:
      POSTGRES_DB: postgres        # Đổi từ 'orders' → 'postgres' (default DB)
      POSTGRES_USER: postgres      # Superuser
      POSTGRES_PASSWORD: ***       # Superuser password
    # volumes giữ nguyên

  order-service:
    environment:
      # Đã được migration.sh update:
      - DATABASE_URL=postgresql://app_user:***@postgres:5432/app_db
```
---
### Connection Pooling Strategy (PgBouncer Integration)

**Vấn đề khi scale lên 10 services (The Connection Exhaustion Trap):**

Hiện tại, mỗi Python service sử dụng `ThreadedConnectionPool` của `psycopg2` với `maxconn=10`.

- Với 6 services: ~60 connections (PostgreSQL chịu đựng tốt).
- Với 10 services + Gunicorn gthread (2 workers × 8 threads = 16 concurrent requests/service): Nếu mỗi thread giữ 1 connection, chúng ta cần 160+ connections.
- **Hậu quả:** PostgreSQL mặc định có `max_connections = 100`. Mỗi connection tốn ~2-10MB RAM và tốn CPU cho context switching. Vượt ngưỡng 200 connections, PostgreSQL sẽ bị "connection thrashing" (CPU tăng vọt nhưng throughput giảm do chuyển đổi context liên tục), dẫn đến cascading failure toàn bộ hệ thống.

**Giải pháp: Thêm PgBouncer (Transaction Pooling Mode)**

Thêm PgBouncer làm middleware đứng giữa Python Services và PostgreSQL để multiplex (ghép kênh) connections.

> 🛡️ **SRE REALITY CHECK: Driver-Level Defenses Already Active**
> Trước khi thêm PgBouncer, cần ghi nhận rằng codebase (`shared/db_utils.py`) đã implement các chốt chặn chống Connection Thrashing ở tầng vi mô:
> 1. **`statement_timeout=30s`**: Tự động kill các runaway queries (query treo vô hạn), giải phóng connection slot ngay lập tức.
> 2. **TCP Keep-Alive (60s idle, 15s interval)**: Phát hiện và loại bỏ "Ghost Connections" do network partition/firewall drop.
> 3. **`close_pool()` on SIGTERM**: Giải phóng slots khi ECS Fargate scale-in/deploy.
> 
> **👉 Kết luận:** PostgreSQL sẽ KHÔNG BỊ SẬP (Death Spiral) khi lên 10 services nhờ các chốt chặn trên. Tuy nhiên, việc thêm PgBouncer ở Phase 2 vẫn là **BẮT BUỘC** để *Multiplexing* (ghép kênh), giảm RAM/CPU cho PostgreSQL và chuẩn bị cho mô hình Microservices scale-out hàng chục instances.

```
[Python Apps] --(100+ client conns)--> [PgBouncer :6432] --(20 server conns)--> [PostgreSQL :5432]
```

#### 1. Docker Compose Setup (Future State)

```yaml
pgbouncer:
  image: edoburu/pgbouncer:latest
  container_name: pgbouncer
  environment:
    # Kết nối tới PostgreSQL với user có quyền cao nhất (hoặc user chung)
    DATABASE_URL: "postgresql://postgres:***@postgres:5432/app_db"
    POOL_MODE: transaction       # QUAN TRỌNG: Xem giải thích bên dưới
    MAX_CLIENT_CONN: 200         # Số connections tối đa từ Python Apps
    DEFAULT_POOL_SIZE: 20        # Số connections thực sự mở tới PostgreSQL
    RESERVE_POOL_SIZE: 5         # Dự phòng cho traffic spike
    RESERVE_POOL_TIMEOUT: 3      # Chờ 3s trước khi dùng reserve pool
    SERVER_IDLE_TIMEOUT: 600     # Đóng server conn nếu idle 10 phút
  ports:
    - "6432:6432"
  depends_on:
    postgres:
      condition: service_healthy
  networks:
    - data
```

#### 2. Updated Connection Strings

Tất cả Python services sẽ **KHÔNG** connect trực tiếp tới port `5432` nữa, mà đi qua PgBouncer port `6432`:

```
# Order, Payment, Inventory, Notification, Auth, Shipping...
DATABASE_URL=postgresql://app_user:***@pgbouncer:6432/app_db
```

#### 3. Sizing Math (Công thức chuẩn Production)

| Tầng | Cấu hình | Giải thích |
|------|---------|-----------|
| Python App | `maxconn=20` | App thoải mái mở connection tới PgBouncer (vì PgBouncer rất nhẹ, tốn ~10KB/conn) |
| PgBouncer | `DEFAULT_POOL_SIZE=20` | Giữ ổn định 20 connections tới Postgres. Phục vụ hàng trăm requests từ App |
| PostgreSQL | `max_connections=120` | 100 cho PgBouncer + 20 dành cho Admin/Backup/Migration tools connect trực tiếp |

#### 4. ⚠️ PgBouncer Transaction Mode Caveats

PgBouncer có 3 chế độ: `session`, `transaction`, và `statement`. Chúng ta **BẮT BUỘC** dùng `transaction` mode cho E-commerce, nhưng cần lưu ý các điểm sau trong code Python:

**✅ An toàn (Đã implement đúng):**

- `SELECT ... FOR UPDATE` (Pessimistic locking trong `inventory-worker`): Hoạt động hoàn hảo vì nó nằm gọn trong 1 `BEGIN ... COMMIT` transaction. PgBouncer sẽ giữ connection cho đến khi `COMMIT`.
- Idempotency checks (`processed_events`): Hoạt động tốt.

**❌ Chống chỉ định (Cần tránh trong tương lai):**

- **Session-level features:** Không dùng `SET SESSION ...`, `LISTEN/NOTIFY`, hoặc temporary tables. Vì sau mỗi `COMMIT`, PgBouncer sẽ thu hồi connection và trả về pool — session state sẽ bị mất hoặc rò rỉ sang request của user khác.
- **Prepared Statements:** Mặc định PgBouncer transaction mode không hỗ trợ PostgreSQL `PREPARE` statements (do statement bị tách khỏi session). `psycopg2` cơ bản không dùng cái này trừ khi bật explicit server-side cursors. Nếu sau này dùng SQLAlchemy, phải set `pool_pre_ping=True` và tắt prepared statements.

---

### 💡 Phân tích sâu

**Tại sao document rõ các Caveats ở mục 4?**

**Góc nhìn Staff SWE:** Rất nhiều team khi đưa PgBouncer vào đã gặp lỗi `"Prepared statement does not exist"` hoặc `"Lock bị mất giữa chừng"` do dùng `statement` mode hoặc Session-level locks. Việc document rõ điều này ngay từ đầu sẽ bảo vệ các Dev junior/mid trong team không viết những đoạn code "phá vỡ" pooling contract khi scale lên 10 services.

**Góc nhìn Staff SRE:** Việc định nghĩa rõ `MAX_CLIENT_CONN=200` và `DEFAULT_POOL_SIZE=20` giúp SRE team hiểu được **Blast Radius**. Nếu App bị lỗi (VD: Infinite loop query DB), nó sẽ làm tràn `MAX_CLIENT_CONN` (200) và gây timeout ở tầng PgBouncer, nhưng **PostgreSQL vẫn sống khỏe** vì chỉ phải chịu tối đa 20 connections. Đây là nguyên tắc **Bulkhead Pattern** (Vách ngăn chống chìm tàu) kinh điển trong System Design.

---

### 🛠️ Files cần update sau này (Checklist cho Phase 0)

1. **`applications-vm/applications/docker-compose.yml`:** Thêm service `pgbouncer`, đổi network của `postgres` thành `data` (chỉ cho `pgbouncer` và app truy cập), ẩn port `5432` khỏi host.

2. **`applications-vm/applications/shared/db_utils.py`:** Hiện tại đang hardcode parse URL. Sau này khi dùng PgBouncer, cần thêm tham số `connect_timeout` ngắn hơn (ví dụ `2s`) để fail-fast nếu PgBouncer queue đầy.

3. **`observability-vm/phase1-metrics/prometheus/prometheus.yml`:** Cần thêm job scrape metrics cho PgBouncer (dùng `prometheus-community/pgbouncer_exporter`) để SRE team có thể alert khi `pgbouncer_pools_cl_active` (số client đang chờ) tăng cao.
---
### So sánh với các approaches khác

| Approach | Services 6 | Services 10 | Services 30+ |
|----------|-----------|-------------|---------------|
| Shared DB (1 DB, all tables) | ✅ Đủ | ⚠️ Bắt đầu coupling | ❌ Nightmare |
| **Hybrid (1 instance, N DBs)** | ✅ | **✅ Sweet spot** | ⚠️ Cần tách instance |
| DB-per-instance | ❌ Overkill | ⚠️ Tốn resource | ✅ Cần thiết |

---

## Đề Xuất Mở Rộng (+4 Services)

### Tổng quan kiến trúc mới

```
                                    ┌──────────────┐
                                    │ Auth Service  │ (NEW)
                                    │   JWT/RBAC    │
                                    │  [auth_db]    │
                                    └──────┬───────┘
                                           │ verify token
                                           ▼
Web UI → API Gateway → Order Service → Payment Service
                │             ↕                ↕
                │        [app_db]            Redis
                │             ↕
                │          Kafka
                │        ↙   ↓    ↘
                │  Notif.  Inv.   Shipping Worker (NEW)
                │  Worker  Worker     ↕
                │                 Shipping Service (NEW)
                │                     ↕
                │                [shipping_db]
                │
                └──→ Search Service (NEW)
                         ↕
                     OpenSearch
                         ↑ sync
                     [app_db] (CDC/event)
```

---

### Service 1: Auth Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5006 |
| **Tech** | Python (Flask) + PyJWT |
| **Database** | PostgreSQL — `auth_db` (isolated) |
| **Mục đích** | Authentication + Authorization |

**Tại sao cần:**
- Hiện tại KHÔNG có authentication → tất cả APIs đều public
- Khi deploy AWS: cần hiểu JWT propagation qua nhiều services
- Production-grade: mọi service đều cần verify token

**Chức năng:**
```
POST /auth/register     → Tạo user, hash password (bcrypt)
POST /auth/login        → Return JWT (access + refresh token)
POST /auth/refresh      → Refresh access token
GET  /auth/verify       → Verify JWT (internal, cho các services khác gọi)
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| JWT local verification | API Gateway verify JWT locally bằng public key (không cần gọi HTTP tới Auth Service). Auth down = new login fail, nhưng existing sessions vẫn hoạt động |
| RBAC | User roles: `customer`, `admin`, `service` |
| Token refresh | Access token 15min, refresh token 7d |
| Service-to-service auth | Internal JWT với role `service` cho inter-service calls |
| Key rotation | JWT signing key rotation procedure — publish new public key trước, rotate private key sau |

**Schema bổ sung:**
```sql
CREATE TABLE users (
    id          SERIAL PRIMARY KEY,
    email       VARCHAR(255) UNIQUE NOT NULL,
    password    VARCHAR(255) NOT NULL,  -- bcrypt hash
    role        VARCHAR(50) DEFAULT 'customer',
    is_active   BOOLEAN DEFAULT true,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE refresh_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER REFERENCES users(id),
    token       VARCHAR(512) UNIQUE NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    revoked     BOOLEAN DEFAULT false
);
```

**Impact lên services hiện tại:**
- API Gateway: thêm middleware verify JWT
- Order Service: extract user_id từ JWT, gắn vào order
- Web UI: thêm login/register page, lưu token trong localStorage

---

### Service 2: Shipping Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5007 |
| **Tech** | Python (Flask) |
| **Database** | PostgreSQL — `shipping_db` (isolated) |
| **Mục đích** | Quản lý shipping sau khi payment thành công |

**Tại sao cần:**
- Hiện tại flow dừng ở Payment → không có gì xảy ra sau đó
- Production-grade: order → payment → **shipping** → delivery
- Tạo ra **Saga pattern** — distributed transaction thực tế

**Chức năng:**
```
POST /shipping/create        → Tạo shipment cho order
GET  /shipping/{order_id}    → Tracking status
POST /shipping/{id}/cancel   → Cancel shipment (compensation)
```

**Schema bổ sung:**
```sql
CREATE TABLE shipments (
    id              SERIAL PRIMARY KEY,
    order_id        VARCHAR(50) UNIQUE NOT NULL,
    status          VARCHAR(50) DEFAULT 'pending',
    -- pending → processing → shipped → delivered → cancelled
    carrier         VARCHAR(100),
    tracking_number VARCHAR(100),
    estimated_delivery TIMESTAMP,
    shipped_at      TIMESTAMP,
    delivered_at    TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW()
);
```

---

### Service 3: Shipping Worker (Saga Orchestrator)

| Attribute | Detail |
|-----------|--------|
| **Port** | 5008 |
| **Tech** | Python + Kafka consumer/producer |
| **Mục đích** | Orchestrate Saga: payment → shipping → notification |

**Tại sao cần:**
- Đây là service tạo ra **nhiều learning value nhất**
- Saga pattern = distributed transaction without 2PC
- Compensation logic khi bất kỳ step nào fail

**Flow:**
```
Saga: Order Fulfillment

Happy path:
  1. Order Service → publish order.created
  2. Payment Service → process → publish order.payment_completed
  3. Shipping Worker → consume → call Shipping Service → create shipment
  4. Shipping Worker → publish order.shipped
  5. Notification Worker → consume → notify customer "Your order has shipped"

Compensation (shipping fail):
  3. Shipping Worker → consume → call Shipping Service → FAIL (out of capacity)
  4. Shipping Worker → publish order.shipping_failed
  5. Shipping Worker → call Payment Service → refund
  6. Shipping Worker → publish order.refunded
  7. Notification Worker → consume → notify customer "Refund processed"
```

**Kafka topics bổ sung:**

| Topic | Producer | Consumer |
|-------|----------|----------|
| `order.shipped` | Shipping Worker | Notification Worker |
| `order.shipping_failed` | Shipping Worker | Notification Worker |
| `order.refunded` | Shipping Worker | Notification Worker, Inventory Worker |

### Saga State Machine — Production-Grade Design

Saga Orchestration là pattern khó nhất trong distributed systems. Design dưới đây giải quyết 5 vấn đề kinh điển: **double-refund**, **lost saga**, **zombie saga**, **race condition**, và **crash mid-step**.
#### ⚠️ SRE Caveat: Interaction with `statement_timeout`
Codebase hiện tại áp dụng `statement_timeout=30000` (30s) cho TẤT CẢ queries qua `shared/db_utils.py`. 
Khi implement `SagaOrchestrator`, bạn phải lưu ý:
- **Risk:** Nếu bước gọi HTTP tới Shipping Service mất 25s, và bước ghi `saga_state` mất 6s → Tổng 31s → PostgreSQL sẽ throw `QueryCanceled` và rollback transaction.
- **Mitigation:** 
  1. Timeout của HTTP Client (gọi Shipping/Payment) PHẢI `< 20s` (dành 10s buffer cho DB write).
  2. Trong `SagaOrchestrator`, cần catch ngoại lệ `psycopg2.errors.QueryCanceled` để log và chuyển Saga sang state `COMPENSATING` hoặc `DEAD_LETTER` thay vì để worker crash.
  3. *Alternative:* Override `statement_timeout` ở mức session cho riêng Saga Worker nếu các bước thực sự cần > 30s (Không khuyến khích).
#### State Machine Diagram

```
                ┌──────────────────────────────────────────────┐
                │                                              │
                ▼                                              │
[order.payment_completed]                                   [Retry]
         │                                                      │
         ▼                                                      │
   ┌─────────────┐   success   ┌─────────────────┐             │
   │  INITIATED  │────────────►│ SHIPPING_PENDING │──── fail ──┤
   └─────────────┘             └─────────────────┘             │
         │                            │                         │
         │                            │ success                 │
         │                            ▼                         │
         │                     ┌─────────────┐                  │
         │                     │   SHIPPED   │  (terminal ✓)    │
         │                     └─────────────┘                  │
         │                                                       │
         │ timeout/max_retries                                   │
         ▼                                                       │
   ┌──────────────┐   success   ┌──────────────┐                │
   │ COMPENSATING │────────────►│   REFUNDED   │ (terminal ✓)   │
   └──────────────┘             └──────────────┘                │
         │                                                       │
         │ compensation fail                                     │
         ▼                                                       │
   ┌──────────────────────┐                                      │
   │ COMPENSATION_FAILED  │  (terminal ✗ — manual intervention) │
   └──────────────────────┘                                      │
         │                                                       │
         │ manual review/approval                                │
         ▼                                                       │
   ┌─────────────┐                                               │
   │ DEAD_LETTER │  (Kafka DLQ topic)                            │
   └─────────────┘                                               │
```

**7 Invariants (bất biến) phải đảm bảo:**

| # | Invariant | Cơ chế đảm bảo |
|---|-----------|----------------|
| 1 | Mỗi `order_id` chỉ có 1 saga duy nhất | `UNIQUE(order_id)` constraint trên `saga_state` |
| 2 | Không refund 2 lần | Idempotency check: `if state == COMPENSATED → skip` |
| 3 | Không ship 2 lần | Idempotency check: `if state == SHIPPED → skip` |
| 4 | Saga không bị "lost" khi worker crash | Write-Ahead Log: insert PENDING TRƯỚC KHI gọi HTTP |
| 5 | Saga không bị "zombie" vĩnh viễn | `timeout_at` column + recovery job mỗi 60s |
| 6 | Không race condition giữa nhiều worker instances | `SELECT FOR UPDATE` trên `saga_state` row |
| 7 | Không "half-done" saga | Atomic state transitions trong transaction |

#### Database Schema (`shipping_db`)

```sql
CREATE TABLE saga_state (
    saga_id         VARCHAR(50) PRIMARY KEY,
    order_id        VARCHAR(50) NOT NULL UNIQUE,  -- 1 order = 1 saga (Invariant #1)
    state           VARCHAR(50) NOT NULL,
    step_data       JSONB DEFAULT '{}',           -- Dynamic data: {shipment_id, tracking_no, ...}
    retry_count     INTEGER DEFAULT 0,
    max_retries     INTEGER DEFAULT 3,
    next_retry_at   TIMESTAMP,                    -- Exponential backoff scheduling
    timeout_at      TIMESTAMP NOT NULL,           -- Invariant #5
    last_error      TEXT,
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),

    CONSTRAINT valid_state CHECK (state IN (
        'INITIATED', 'SHIPPING_PENDING', 'SHIPPED',
        'SHIPPING_FAILED', 'COMPENSATING', 'REFUNDED',
        'COMPENSATION_FAILED', 'DEAD_LETTER'
    ))
);

-- Index cho recovery job (Invariant #5)
CREATE INDEX idx_saga_recoverable
    ON saga_state(state, next_retry_at)
    WHERE state IN ('SHIPPING_PENDING', 'COMPENSATING')
      AND next_retry_at IS NOT NULL;

-- Index cho timeout detection
CREATE INDEX idx_saga_timeout
    ON saga_state(timeout_at)
    WHERE state NOT IN ('SHIPPED', 'REFUNDED', 'DEAD_LETTER');

-- Audit log cho debugging
CREATE TABLE saga_history (
    id              SERIAL PRIMARY KEY,
    saga_id         VARCHAR(50) NOT NULL,
    from_state      VARCHAR(50),
    to_state        VARCHAR(50) NOT NULL,
    trigger_reason  VARCHAR(100),  -- 'http_success', 'http_fail', 'timeout', 'recovery'
    error_message   TEXT,
    duration_ms     INTEGER,
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_saga_history_saga ON saga_history(saga_id);
```

**Rationale cho từng column:**

- `step_data JSONB`: Lưu dynamic data (`shipment_id` từ Shipping Service, `refund_txn_id` từ Payment Service) → tránh thêm columns mới khi thêm steps
- `next_retry_at`: Cho phép worker "sleep" saga đến thời điểm retry → giảm polling load
- `timeout_at`: Hard deadline cho toàn bộ saga (15 phút) → prevent zombie sagas
- `saga_history`: Audit trail để debug tại sao saga vào state X → quan trọng cho post-mortem

#### Python Implementation Pattern (`SagaOrchestrator`)

```python
# shipping-worker/saga_orchestrator.py

import time
import uuid
import psycopg2
import psycopg2.extras
import requests
from datetime import datetime, timedelta
from typing import Callable, Optional, Dict, Any

class SagaOrchestrator:
    """
    Production-grade Saga Orchestrator với:
    - Write-Ahead Log pattern (state PENDING trước khi action)
    - Idempotency checks (Invariant #2, #3)
    - SELECT FOR UPDATE (Invariant #6)
    - Exponential backoff retry
    - Crash recovery từ saga_state table
    """

    TOTAL_TIMEOUT_SECONDS = 900  # 15 phút
    BASE_BACKOFF_SECONDS = 1     # 1s, 5s, 25s (5^n)

    def __init__(self, db_pool, shipping_service_url, payment_service_url, tracer):
        self.db = db_pool
        self.shipping_url = shipping_service_url
        self.payment_url = payment_service_url
        self.tracer = tracer

    def start_saga(self, order_id: str, initial_data: Dict[str, Any]) -> str:
        """
        Khởi tạo saga mới. Idempotent: nếu saga đã tồn tại → trả về saga_id cũ.
        """
        saga_id = f"saga-{order_id}-{uuid.uuid4().hex[:8]}"
        timeout_at = datetime.utcnow() + timedelta(seconds=self.TOTAL_TIMEOUT_SECONDS)

        conn = self.db.get_conn()
        try:
            with conn.cursor() as cur:
                # Idempotent insert: ON CONFLICT DO NOTHING
                cur.execute("""
                    INSERT INTO saga_state
                        (saga_id, order_id, state, step_data, timeout_at)
                    VALUES (%s, %s, 'INITIATED', %s, %s)
                    ON CONFLICT (order_id) DO NOTHING
                    RETURNING saga_id
                """, (saga_id, order_id, psycopg2.extras.Json(initial_data), timeout_at))

                result = cur.fetchone()
                if result is None:
                    # Saga đã tồn tại → fetch existing
                    cur.execute(
                        "SELECT saga_id, state FROM saga_state WHERE order_id = %s",
                        (order_id,)
                    )
                    existing = cur.fetchone()
                    saga_id = existing[0]
                    # Nếu saga chưa terminal → resume
                    if existing[1] not in ('SHIPPED', 'REFUNDED', 'DEAD_LETTER'):
                        self._log_history(conn, saga_id, None, existing[1],
                                         'idempotent_resume', None)
                else:
                    self._log_history(conn, saga_id, None, 'INITIATED',
                                     'saga_created', None)

                conn.commit()
                return saga_id
        finally:
            self.db.put_conn(conn)

    def execute_step(self, saga_id: str, step_name: str,
                     action_fn: Callable, compensate_fn: Callable) -> bool:
        """
        Execute 1 step với Write-Ahead Log pattern.

        Flow:
        1. SELECT FOR UPDATE saga row
        2. Check idempotency (đã done chưa?)
        3. Check timeout
        4. Update state = PENDING (Write-Ahead)
        5. Execute action_fn()
        6. Update state = COMPLETED hoặc trigger compensation

        Returns: True nếu step thành công, False nếu cần compensation
        """
        conn = self.db.get_conn()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                # Invariant #6: SELECT FOR UPDATE
                cur.execute("""
                    SELECT saga_id, state, step_data, retry_count, timeout_at
                    FROM saga_state
                    WHERE saga_id = %s
                    FOR UPDATE
                """, (saga_id,))

                saga = cur.fetchone()
                if not saga:
                    raise ValueError(f"Saga {saga_id} not found")

                # Invariant #2, #3: Idempotency check
                if self._is_terminal_state(saga['state']):
                    return saga['state'] in ('SHIPPED', 'REFUNDED')

                # Invariant #5: Timeout check
                if datetime.utcnow() > saga['timeout_at']:
                    self._transition_state(conn, saga_id, saga['state'],
                                          'DEAD_LETTER', 'total_timeout_exceeded')
                    conn.commit()
                    return False

                # Write-Ahead Log: state = PENDING TRƯỚC KHI action
                pending_state = f"{step_name}_PENDING"
                self._transition_state(conn, saga_id, saga['state'],
                                      pending_state, f'{step_name}_started')
                conn.commit()  # Commit WAL trước khi gọi HTTP

            # Execute action OUTSIDE transaction (tránh giữ lock quá lâu)
            start_time = time.time()
            try:
                with self.tracer.start_as_current_span(f"saga.{step_name}") as span:
                    span.set_attribute("saga.id", saga_id)
                    span.set_attribute("saga.step", step_name)

                    result = action_fn(saga['step_data'])

                    duration_ms = int((time.time() - start_time) * 1000)
                    span.set_attribute("saga.duration_ms", duration_ms)

                # Success: transition to next state
                with conn.cursor() as cur:
                    next_state = self._get_next_state(step_name, success=True)
                    new_step_data = {**saga['step_data'], **result}

                    cur.execute("""
                        UPDATE saga_state
                        SET state = %s,
                            step_data = %s,
                            retry_count = 0,
                            next_retry_at = NULL,
                            updated_at = NOW()
                        WHERE saga_id = %s
                    """, (next_state, psycopg2.extras.Json(new_step_data), saga_id))

                    self._log_history(conn, saga_id, pending_state, next_state,
                                     'http_success', None, duration_ms)
                    conn.commit()
                return True

            except (requests.Timeout, requests.ConnectionError) as e:
                # Transient error → retry với exponential backoff
                return self._handle_retry(conn, saga_id, saga, step_name,
                                         pending_state, e, compensate_fn)

            except requests.HTTPError as e:
                if 400 <= e.response.status_code < 500:
                    # Business error (VD: out of capacity) → compensate
                    return self._trigger_compensation(conn, saga_id, saga,
                                                     step_name, e, compensate_fn)
                else:
                    # 5xx server error → retry
                    return self._handle_retry(conn, saga_id, saga, step_name,
                                             pending_state, e, compensate_fn)
        finally:
            self.db.put_conn(conn)

    def recover_stale_sagas(self):
        """
        Background job: chạy mỗi 60s để resume sagas bị crash hoặc quá retry time.
        Đây là cơ chế đảm bảo Invariant #4 (no lost saga) và #5 (no zombie).
        """
        conn = self.db.get_conn()
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("""
                    SELECT saga_id, state, step_data, retry_count, timeout_at
                    FROM saga_state
                    WHERE (
                        (state IN ('SHIPPING_PENDING', 'COMPENSATING')
                         AND next_retry_at < NOW())
                        OR
                        (state LIKE '%_PENDING'
                         AND updated_at < NOW() - INTERVAL '2 minutes')
                        OR
                        (timeout_at < NOW()
                         AND state NOT IN ('SHIPPED', 'REFUNDED', 'DEAD_LETTER'))
                    )
                    ORDER BY timeout_at ASC
                    LIMIT 10          -- Batch processing, tránh overload
                    FOR UPDATE SKIP LOCKED  -- Multiple workers can run concurrently
                """)

                stale_sagas = cur.fetchall()

                for saga in stale_sagas:
                    try:
                        if datetime.utcnow() > saga['timeout_at']:
                            self._transition_state(conn, saga['saga_id'],
                                                  saga['state'], 'DEAD_LETTER',
                                                  'total_timeout_exceeded')
                        elif saga['state'] == 'COMPENSATING':
                            self._resume_compensation(conn, saga)
                        else:
                            self._resume_step(conn, saga)

                        conn.commit()
                    except Exception as e:
                        conn.rollback()
                        logger.error(f"Failed to recover saga {saga['saga_id']}: {e}")
        finally:
            self.db.put_conn(conn)

    # --- Private helpers ---

    def _is_terminal_state(self, state: str) -> bool:
        return state in ('SHIPPED', 'REFUNDED', 'DEAD_LETTER', 'COMPENSATION_FAILED')

    def _transition_state(self, conn, saga_id, from_state, to_state,
                         reason, error=None):
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE saga_state
                SET state = %s, last_error = %s, updated_at = NOW()
                WHERE saga_id = %s
            """, (to_state, str(error) if error else None, saga_id))
            self._log_history(conn, saga_id, from_state, to_state, reason, error)

    def _log_history(self, conn, saga_id, from_state, to_state,
                    reason, error, duration_ms=None):
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO saga_history
                    (saga_id, from_state, to_state, trigger_reason,
                     error_message, duration_ms)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (saga_id, from_state, to_state, reason,
                  str(error) if error else None, duration_ms))

    def _handle_retry(self, conn, saga_id, saga, step_name,
                     pending_state, error, compensate_fn):
        retry_count = saga['retry_count'] + 1

        if retry_count >= saga['max_retries']:
            return self._trigger_compensation(conn, saga_id, saga,
                                             step_name, error, compensate_fn)

        # Exponential backoff: 1s, 5s, 25s, 125s
        backoff = self.BASE_BACKOFF_SECONDS * (5 ** (retry_count - 1))
        next_retry = datetime.utcnow() + timedelta(seconds=backoff)

        with conn.cursor() as cur:
            cur.execute("""
                UPDATE saga_state
                SET state = %s,
                    retry_count = %s,
                    next_retry_at = %s,
                    last_error = %s,
                    updated_at = NOW()
                WHERE saga_id = %s
            """, (f"{step_name}_FAILED", retry_count, next_retry,
                  str(error), saga_id))
            self._log_history(conn, saga_id, pending_state,
                             f"{step_name}_FAILED", 'retry_scheduled', error)
        conn.commit()
        return False

    def _trigger_compensation(self, conn, saga_id, saga,
                             step_name, error, compensate_fn):
        """Trigger compensation phase - will be executed by recover_stale_sagas"""
        self._transition_state(conn, saga_id, saga['state'],
                              'COMPENSATING', f'{step_name}_failed', error)
        conn.commit()
        return False
```

#### 5 Idempotency Scenarios (Phải test trước khi go-live)

| # | Scenario | Expected Behavior | Cơ chế đảm bảo |
|---|---------|-------------------|----------------|
| 1 | Kafka redeliver `order.payment_completed` 2 lần | Lần 2: skip, không tạo saga mới | `UNIQUE(order_id)` + `ON CONFLICT DO NOTHING` |
| 2 | Worker crash sau khi tạo shipment nhưng trước khi update state | Recovery job resume → thấy state `SHIPPING_PENDING` stale 2 phút → gọi lại Shipping Service (idempotent API) | Write-Ahead Log + `SELECT FOR UPDATE` + idempotent external API |
| 3 | Shipping Service trả về timeout nhưng thực tế đã tạo shipment | Retry → Shipping Service trả về existing shipment (idempotent) → saga tiếp tục bình thường | External API PHẢI idempotent (dùng `order_id` làm idempotency key) |
| 4 | Compensation (refund) chạy 2 lần do Kafka redeliver `order.shipping_failed` | Lần 2: skip vì `state = REFUNDED` | `_is_terminal_state()` check |
| 5 | 2 instances của Shipping Worker cùng consume 1 message | Chỉ 1 instance win `SELECT FOR UPDATE`, instance kia block hoặc skip | `SELECT FOR UPDATE` + `FOR UPDATE SKIP LOCKED` trong recovery |

#### Crash Recovery Flow

```
Time 0:00  Saga bắt đầu, state = INITIATED
Time 0:01  state = SHIPPING_PENDING (WAL committed)
Time 0:02  Worker crash 💥 (trước khi gọi Shipping Service)

Time 1:00  Recovery job chạy (mỗi 60s)
           → Query: "saga in PENDING > 2 phút"
           → Tìm thấy saga của chúng ta
           → SELECT FOR UPDATE
           → Resume: gọi Shipping Service

Time 1:02  Shipping Service respond success
           → state = SHIPPED
           → Publish order.shipped event
```

#### Observability Instrumentation

```python
# Metrics PHẢI có cho Saga (dùng OTel Meter)
saga_started_total = meter.create_counter(
    name="saga_started_total",
    description="Total sagas initiated"
)
saga_completed_total = meter.create_counter(
    name="saga_completed_total",
    description="Sagas by terminal state"
    # labels: terminal_state=SHIPPED|REFUNDED|DEAD_LETTER
)
saga_duration_seconds = meter.create_histogram(
    name="saga_duration_seconds",
    description="Time from INITIATED to terminal state"
)
saga_step_duration_seconds = meter.create_histogram(
    name="saga_step_duration_seconds",
    description="Duration per step"
    # labels: step=shipping|compensation
)
saga_recoveries_total = meter.create_counter(
    name="saga_recoveries_total",
    description="Sagas recovered by background job"
)

# Span attributes cho distributed tracing
with tracer.start_as_current_span("saga.execute") as span:
    span.set_attribute("saga.id", saga_id)
    span.set_attribute("saga.order_id", order_id)
    span.set_attribute("saga.state", current_state)
    span.set_attribute("saga.retry_count", retry_count)
```

**Alerts** (thêm vào `kafka_alert_rules.yml`):

```yaml
- alert: SagaHighCompensationRate
  expr: |
    (
      sum(rate(saga_completed_total{terminal_state="REFUNDED"}[5m]))
      /
      sum(rate(saga_started_total[5m]))
    ) > 0.05
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "🔥 Saga compensation rate > 5% — systemic shipping issue"

- alert: SagaDeadLetterQueueGrowing
  expr: |
    sum(saga_state_count{state="DEAD_LETTER"})
    - sum(saga_state_count{state="DEAD_LETTER"} offset 10m) > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "⚠️ Saga DLQ growing — manual intervention needed"

- alert: SagaStuckInPending
  expr: |
    sum(saga_state_count{state=~".*_PENDING"}) > 0
    and
    avg(saga_state_age_seconds{state=~".*_PENDING"}) > 300
  for: 5m
  labels:
    severity: warning
```

#### Testing Strategy (Contract Tests)

```python
# tests/test_saga_orchestrator.py

def test_saga_idempotency_on_kafka_redelivery():
    """Invariant #1: 1 order = 1 saga"""
    saga_id_1 = orchestrator.start_saga("ORD-001", {...})
    saga_id_2 = orchestrator.start_saga("ORD-001", {...})
    assert saga_id_1 == saga_id_2

def test_crash_recovery_resumes_pending_saga():
    """Invariant #4: No lost saga"""
    # Simulate: saga stuck in SHIPPING_PENDING for 3 minutes
    db.execute("""
        INSERT INTO saga_state (saga_id, order_id, state, updated_at)
        VALUES ('saga-1', 'ORD-002', 'SHIPPING_PENDING', NOW() - INTERVAL '3 minutes')
    """)

    orchestrator.recover_stale_sagas()

    # Verify: saga moved to SHIPPED
    state = db.execute("SELECT state FROM saga_state WHERE saga_id = 'saga-1'")
    assert state == 'SHIPPED'

def test_no_double_refund():
    """Invariant #2: Compensation idempotent"""
    # Setup: saga đã REFUNDED
    db.execute("""
        INSERT INTO saga_state (saga_id, order_id, state)
        VALUES ('saga-1', 'ORD-003', 'REFUNDED')
    """)

    # Simulate Kafka redeliver shipping_failed event
    orchestrator.handle_shipping_failed("saga-1", {...})

    # Verify: refund API chỉ được gọi 1 lần (dùng mock)
    assert payment_service.refund.call_count == 0
```

---

### 🔧 Files codebase sẽ bị ảnh hưởng (Checklist cho Phase 2)

**1. `applications-vm/applications/shipping-worker/saga_orchestrator.py`** (MỚI)

- Copy class `SagaOrchestrator` ở trên
- Inject dependencies: `db_pool`, `shipping_service_url`, `payment_service_url`, `tracer`

**2. `applications-vm/applications/shipping-worker/app.py`** (MỚI)

```python
from saga_orchestrator import SagaOrchestrator

# Kafka consumer loop
def handle_payment_completed(msg):
    order_id = msg['order_id']
    saga_id = orchestrator.start_saga(order_id, msg['data'])

    # Step 1: Create shipment
    success = orchestrator.execute_step(
        saga_id=saga_id,
        step_name="SHIPPING",
        action_fn=lambda data: create_shipment(data),
        compensate_fn=lambda data: refund_payment(data)
    )

    if success:
        publish_event("order.shipped", order_id, {...})
    # Compensation will be handled by recovery job
```

**3. `applications-vm/applications/shipping-worker/init-shipping.sql`** (MỚI)

- Copy schema `saga_state` và `saga_history` ở trên

**4. `observability-vm/phase1-metrics/prometheus/kafka_alert_rules.yml`**

- Thêm 3 alerts: `SagaHighCompensationRate`, `SagaDeadLetterQueueGrowing`, `SagaStuckInPending`

**5. `observability-vm/phase1-metrics/grafana/dashboards/Application/saga-monitor.json`** (MỚI)

- Panels: Saga State Machine Flow (Node Graph plugin), Saga Duration Distribution (Histogram), Compensation Rate (Time series), Active Sagas by State (Stacked bar), DLQ Size (Stat)

**6. `INCIDENT_RUNBOOK.md`** — Thêm runbook mới:

- `RB-SAGA-01`: Saga Stuck in PENDING → Check recovery job logs, manually resume
- `RB-SAGA-02`: High Compensation Rate → Investigate Shipping Service health
- `RB-SAGA-03`: DLQ Growing → Manual review & replay

---

### 💡 Staff SRE Note: Tại sao KHÔNG dùng Temporal/Cadence?

| Yếu tố | Self-implemented | Temporal/Cadence |
|--------|-----------------|-----------------|
| Learning value | ✅ Hiểu sâu state machine, WAL, idempotency | ❌ Black box |
| Operational complexity | ✅ Chỉ PostgreSQL | ❌ Thêm 1 distributed system (Temporal server + Cassandra) |
| Cost | ✅ Free | ❌ Temporal Cloud $$ hoặc self-host tốn RAM |
| Use case fit | ✅ 1 saga type (order fulfillment) | ✅ Hàng chục saga types |
| Production-ready | ⚠️ Cần test kỹ | ✅ Battle-tested |

**Recommendation:**

- **Lab này** (1 saga type): Self-implement → maximize learning
- **Production thực tế** (>5 saga types): Dùng Temporal → giảm operational burden

Đây chính là trade-off thinking mà Senior/Staff Engineer cần có: biết **KHI NÀO** dùng tool, **KHI NÀO** tự viết.

**Schema bổ sung (shipping_db):**
```sql
CREATE TABLE saga_state (
    saga_id     VARCHAR(50) PRIMARY KEY,
    order_id    VARCHAR(50) NOT NULL,
    state       VARCHAR(50) NOT NULL,
    retries     INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    timeout_at  TIMESTAMP,
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **Saga Orchestration** | Coordinator quản lý multi-step transaction với persistent state |
| **Compensation** | Rollback khi downstream service fail |
| **Dead Letter Queue** | Messages xử lý fail → DLQ topic để review |
| **Retry with backoff** | Exponential backoff cho transient failures |
| **Crash recovery** | Resume incomplete sagas on restart từ saga_state table |

---

### Service 4: Search Service

| Attribute | Detail |
|-----------|--------|
| **Port** | 5009 |
| **Tech** | Python (Flask) + OpenSearch client |
| **Database** | OpenSearch (search index) |
| **Mục đích** | Full-text search cho products + orders |

**Tại sao cần:**
- Học data sync giữa PostgreSQL → OpenSearch (eventual consistency)
- Tạo CQRS pattern: write vào PostgreSQL, read từ OpenSearch
- Trên AWS: sử dụng Amazon OpenSearch Service

**Chức năng:**
```
GET  /search/products?q=laptop       → Full-text search products
GET  /search/orders?q=ORD-123        → Search orders by ID/status
POST /search/reindex                 → Manual reindex trigger
```

**Data sync approach (Event-driven):**
```
Sync strategy:
  1. Event-driven: listen order.created, order.updated → index to OpenSearch
  2. Backfill: POST /search/reindex → full scan app_db → bulk index
  3. Idempotency: use order_id as OpenSearch document _id (upsert, not insert)
  4. Failure handling: if OpenSearch write fails → publish to search.sync.dlq
  5. Index versioning: use aliases (orders_v1, orders_v2) for zero-downtime reindex
  6. Lag metric: track time giữa Kafka event timestamp và OpenSearch indexed_at
```

**Patterns mới học được:**

| Pattern | Mô tả |
|---------|-------|
| **CQRS** | Separate read model (OpenSearch) vs write model (PostgreSQL) |
| **Eventual consistency** | Search index có thể lag 1-5s sau khi write, đo bằng metric |
| **Bulk indexing** | Batch sync cho reindex operations |
| **Index aliasing** | Zero-downtime reindex bằng alias switching |
| **Search relevance** | Scoring, boosting, fuzzy matching |

---

## Kiến Trúc Tổng Thể Sau Mở Rộng

### System Architecture (10 Services)

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                              Applications VM                                             │
│                                                                                          │
│  ┌─────────────────────────────────────── API Layer ──────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌──────────┐   rate    ┌──────────────┐    JWT     ┌─────────────────┐            │   │
│  │  │  Web UI  │──limit──►│ API Gateway  │──verify──►│  Auth Service   │            │   │
│  │  │  (nginx) │          │  Flask :5000  │◄──token───│  Flask :5006    │            │   │
│  │  │  :8580   │          │  + Circuit   │           │  [auth_db]      │            │   │
│  │  └──────────┘          │    Breaker    │           └─────────────────┘            │   │
│  │                        └──────┬───────┘                                           │   │
│  │                               │ HTTP                                              │   │
│  └───────────────────────────────┼───────────────────────────────────────────────────┘   │
│                                  ▼                                                       │
│  ┌─────────────────────────────── Core Services ─────────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌─────────────────┐  HTTP+CB  ┌──────────────┐        ┌──────────────────┐       │   │
│  │  │  Order Service  │─────────►│Payment Service│        │  Search Service  │       │   │
│  │  │  Flask :5001    │          │  Flask :5002   │        │  Flask :5009     │       │   │
│  │  │                 │          └──────────────┘        │  [OpenSearch]    │       │   │
│  │  │  [app_db]       │                                   └──────────────────┘       │   │
│  │  │  [Redis cache]  │                                          ▲                   │   │
│  │  └────────┬────────┘                                          │ event sync        │   │
│  │           │ Kafka produce                                     │                   │   │
│  └───────────┼───────────────────────────────────────────────────┼───────────────────┘   │
│              ▼                                                   │                       │
│  ┌─────────────────────────────── Event Bus ─────────────────────┼───────────────────┐   │
│  │                                                               │                   │   │
│  │  ┌─────────────────────────────────────┐                      │                   │   │
│  │  │           Kafka (KRaft :9092)        │                      │                   │   │
│  │  │                                     │                      │                   │   │
│  │  │  Topics:                            │                      │                   │   │
│  │  │   order.created ──────────────────────────────────────────►│                   │   │
│  │  │   order.payment_completed           │                                          │   │
│  │  │   order.payment_failed              │                                          │   │
│  │  │   order.shipped          (new)      │                                          │   │
│  │  │   order.shipping_failed  (new)      │                                          │   │
│  │  │   order.refunded         (new)      │                                          │   │
│  │  │   order.shipping.dlq     (new)      │                                          │   │
│  │  └──────────┬──────────────────────────┘                                          │   │
│  │             │ consume                                                             │   │
│  │     ┌───────┼───────────┬──────────────┐                                          │   │
│  │     ▼       ▼           ▼              │                                          │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐                           │   │
│  │  │  Notification │ │  Inventory   │ │ Shipping Worker  │ (NEW)                    │   │
│  │  │  Worker :5004 │ │  Worker :5005│ │  :5008           │                          │   │
│  │  │  [app_db]     │ │  [app_db]    │ │  Saga Orchestrator│                         │   │
│  │  └──────────────┘ └──────────────┘ │  + DLQ handler    │                          │   │
│  │                                     │  + Circuit Breaker│                          │   │
│  │                                     └────────┬─────────┘                          │   │
│  │                                              │ HTTP+CB                            │   │
│  │                                              ▼                                    │   │
│  │                                     ┌──────────────────┐                          │   │
│  │                                     │ Shipping Service │ (NEW)                    │   │
│  │                                     │  Flask :5007     │                          │   │
│  │                                     │  [shipping_db]   │                          │   │
│  │                                     └──────────────────┘                          │   │
│  └───────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│  ┌─────────────────────────────── Data Layer ────────────────────────────────────────┐   │
│  │                                                                                    │   │
│  │  ┌──────────────────────────┐  ┌──────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │      PostgreSQL :5432    │  │ Redis    │  │  OpenSearch  │  │  Kafka       │   │   │
│  │  │  ┌────────┬──────────┐  │  │  :6379   │  │   :9200      │  │  :9092       │   │   │
│  │  │  │ app_db │ auth_db  │  │  │  Cache   │  │  Search      │  │  KRaft mode  │   │   │
│  │  │  │        │          │  │  │  TTL 60s │  │  Index       │  │  8 topics    │   │   │
│  │  │  │        │shipping_ │  │  └──────────┘  └──────────────┘  │  + 1 DLQ     │   │   │
│  │  │  │        │db        │  │                                   └──────────────┘   │   │
│  │  │  └────────┴──────────┘  │                                                      │   │
│  │  └──────────────────────────┘                                                     │   │
│  │                                                                                    │   │
│  │  ┌──────────────┐  ┌──────────────┐                                               │   │
│  │  │ Kafka UI     │  │Kafka Exporter│                                               │   │
│  │  │  :8585       │  │  :9308       │                                               │   │
│  │  └──────────────┘  └──────────────┘                                               │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│  Resilience: Circuit Breaker (pybreaker) │ Rate Limit (Redis) │ Health Checks (/health)  │
│  Error Format: RFC 7807 + trace_id       │ Auth: JWT + RBAC   │ DLQ: order.shipping.dlq  │
└────────────────────────────────┬─────────────────────────────────────────────────────────┘
                                 │ OTLP (gRPC :4317)
┌────────────────────────────────▼─────────────────────────────────────────────────────────┐
│                          Observability VM                                                 │
│                                                                                          │
│  ┌────────────────┐  ┌────────────┐  ┌───────────────┐  ┌──────────────────────────┐    │
│  │ OTel Collector │─►│ Prometheus │─►│  Grafana      │  │  Dashboards:             │    │
│  │  :4317/:4318   │  │   :9090    │  │   :3000       │  │  • Application Health    │    │
│  │                │  └────────────┘  │               │  │  • Kafka Overview        │    │
│  │                │─►┌────────────┐  │               │  │  • Auth Overview    (NEW)│    │
│  │                │  │   Tempo    │  │               │  │  • Saga Monitor     (NEW)│    │
│  │                │  │   :3200    │  │               │  │  • Search Health    (NEW)│    │
│  │                │  └────────────┘  │               │  │  • Cross-Service    (NEW)│    │
│  │                │─►┌────────────┐  │               │  │  • SLI/SLO Burn Rate    │    │
│  │                │  │   Loki     │  └───────────────┘  └──────────────────────────┘    │
│  └────────────────┘  │   :3100    │  ┌───────────────┐                                  │
│                      └────────────┘  │ Alertmanager  │                                  │
│                                      │  → Telegram   │                                  │
│                                      │  Alerts:      │                                  │
│                                      │  • SLO burn   │                                  │
│                                      │  • Saga fail  │                                  │
│                                      │  • CB open    │                                  │
│                                      │  • Auth brute │                                  │
│                                      └───────────────┘                                  │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Ports Summary (Sau mở rộng)

| Port | Service | Type | Database |
|------|---------|------|----------|
| 5000 | API Gateway | HTTP + Rate Limit | - |
| 5001 | Order Service | HTTP | app_db + Redis |
| 5002 | Payment Service | HTTP | app_db |
| 5003 | Traffic Generator | HTTP | - |
| 5004 | Notification Worker | Kafka Consumer | app_db |
| 5005 | Inventory Worker | Kafka Consumer | app_db |
| **5006** | **Auth Service** (NEW) | HTTP | **auth_db** |
| **5007** | **Shipping Service** (NEW) | HTTP | **shipping_db** |
| **5008** | **Shipping Worker** (NEW) | Kafka Consumer + HTTP | **shipping_db** |
| **5009** | **Search Service** (NEW) | HTTP + Kafka Consumer | **OpenSearch** |
| 5432 | PostgreSQL | TCP | app_db, auth_db, shipping_db |
| 6379 | Redis | TCP | - |
| **9200** | **OpenSearch** (NEW) | HTTP | - |
| 8580 | Web UI | HTTP | - |
| 8585 | Kafka UI | HTTP | - |
| 9092 | Kafka | TCP | - |
| 9308 | Kafka Exporter | HTTP | - |

### Data Flow (Sau mở rộng)

```
Synchronous (HTTP + JWT + Circuit Breaker):
  Web UI → API Gateway ──JWT──► Auth Service (verify)
                       ──HTTP──► Order Service ──HTTP+CB──► Payment Service
                       ──HTTP──► Search Service ──query──► OpenSearch
                                 Shipping Worker ──HTTP+CB──► Shipping Service

Asynchronous (Kafka Event-Driven):
  Order Service ──publish──► Kafka
                                ├── order.created ──────► Notif Worker
                                │                  ──────► Inventory Worker
                                │                  ──────► Shipping Worker ──► Search Service
                                ├── order.payment_completed ► Notif + Shipping Worker
                                ├── order.payment_failed    ► Notif + Inventory
                                ├── order.shipped           ► Notif
                                ├── order.shipping_failed   ► Notif
                                ├── order.refunded          ► Notif + Inventory
                                └── order.shipping.dlq      ► Manual review
```

### Communication Matrix

```
                  API-GW  Order  Payment  Notif  Inv  Auth  Shipping  Ship-W  Search
API Gateway         -      HTTP    -        -     -    HTTP     -       -      HTTP
Order Service       -       -     HTTP      -     -    JWT      -       -       -
Payment Service     -       -      -        -     -    JWT      -       -       -
Notif Worker        -       -      -        -     -     -       -       -       -
Inventory Worker    -       -      -        -     -     -       -       -       -
Auth Service        -       -      -        -     -     -       -       -       -
Shipping Service    -       -      -        -     -    JWT       -       -       -
Shipping Worker     -       -     HTTP      -     -     -      HTTP     -       -
Search Service      -       -      -        -     -     -       -       -       -
```

### Kafka Topic Map

```
order.events (existing)
  ├── order.created           → Notif, Inventory, Shipping Worker
  ├── order.payment_completed → Notif, Shipping Worker
  └── order.payment_failed    → Notif, Inventory

order.shipping (new)
  ├── order.shipped           → Notif
  ├── order.shipping_failed   → Notif
  └── order.refunded          → Notif, Inventory

search.sync (new)
  ├── product.updated         → Search Service
  └── order.indexed           → Search Service
```

---

## Phân Tích Failure Scenarios Mới

Với 10 services, các failure scenarios phức tạp hơn đáng kể:

### Cascading Failures

| Scenario | Chain | Impact | Recovery |
|----------|-------|--------|----------|
| Auth Service down | Tất cả services từ chối request → toàn bộ hệ thống down | **Critical** — single point of failure | Circuit breaker: cache JWT verification 5 min |
| Shipping Service down | Payment thành công nhưng không ship được | Orders stuck ở `paid` status | Saga compensation → refund hoặc retry queue |
| OpenSearch down | Search không hoạt động, writes vẫn OK | **Degraded** — core flow không ảnh hưởng | Graceful degradation: fallback query PostgreSQL |
| Kafka down | Tất cả async flows dừng | **Critical** — orders create nhưng không process | Kafka cluster HA, consumer replay từ offset |

### New Chaos Exercises

| Exercise | Break | Observe | Recover |
|----------|-------|---------|---------|
| Kill Auth mid-request | Stop Auth container | Existing sessions còn hoạt động? New logins fail? | Restart + verify JWT cache |
| Kill Shipping during Saga | Stop Shipping Worker giữa chừng | Order stuck? Payment đã charge nhưng chưa ship? | Saga timeout → compensation → refund |
| OpenSearch index corrupt | Delete index | Search trả về 0 results | Reindex từ PostgreSQL |
| Kafka consumer lag | Slow down Shipping Worker (add 10s delay) | Queue backlog? Other consumers bị ảnh hưởng? | Scale consumer group hoặc fix bottleneck |

---

## Design Patterns Comparison

### Trước mở rộng (6 services)

```
Patterns:
  ✅ Sync HTTP (request-response)
  ✅ Async Pub/Sub (Kafka)
  ✅ Cache-Aside (Redis)
  ✅ BFF (API Gateway)
  ✅ Idempotent Processing
  ✅ Pessimistic Locking
  ✅ Trace Propagation (W3C)
```

### Sau mở rộng (10 services)

```
Tất cả patterns cũ +
  🆕 Saga Orchestration (distributed transactions + crash recovery)
  🆕 Compensation (rollback when downstream fails)
  🆕 Circuit Breaker (failure isolation + observability)
  🆕 CQRS (read/write model separation)
  🆕 Eventual Consistency (sync lag + measurement)
  🆕 Dead Letter Queue (failed message handling)
  🆕 JWT Local Verification (resilient auth)
  🆕 RBAC (role-based access control)
  🆕 Graceful Degradation (fallback khi dependency down)
  🆕 Retry with Exponential Backoff
  🆕 TLS Termination (HTTPS)
  🆕 Secrets Management (Docker secrets + .env)
  🆕 Network Segmentation (Docker networks per tier)
  🆕 Resource Limits (CPU/memory per container)
  🆕 Graceful Shutdown (SIGTERM handling)
  🆕 Backup/Restore (per-database + DR drill)
  🆕 Index Aliasing (zero-downtime reindex)
  🆕 CI Pipeline (lint + test + build)
```

---

## Resilience Patterns (Bổ sung cho tất cả services)

Ngoài 4 services mới, cần bổ sung các production-grade patterns cho **toàn bộ** services (cũ + mới):

### Health Check Endpoints

Mỗi service cần expose 2 endpoints chuẩn Kubernetes/ECS:

```
GET /health/live      → 200 nếu process đang chạy (liveness)
GET /health/ready     → 200 nếu service sẵn sàng nhận traffic (readiness)
```

| Service | Liveness | Readiness |
|---------|----------|----------|
| Order Service | Process alive | PostgreSQL connected + Redis connected + Kafka producer ready |
| Auth Service | Process alive | PostgreSQL connected (auth_db) |
| Shipping Worker | Process alive | Kafka consumer subscribed + PostgreSQL connected (shipping_db) |
| Search Service | Process alive | OpenSearch cluster health green/yellow |

**Tại sao quan trọng:**
- Docker Compose: `healthcheck` trong docker-compose.yml — container restart khi unhealthy
- AWS ECS: ALB target group health check → unhealthy task bị thay thế tự động
- Kubernetes: liveness/readiness probes → Pod restart hoặc tạm ngưng traffic

### Circuit Breaker

Áp dụng cho các HTTP calls giữa services:

```
API Gateway → Order Service:     circuit breaker (5 failures → open 30s)
Order Service → Payment Service: circuit breaker (3 failures → open 60s)
Shipping Worker → Shipping Svc:  circuit breaker (3 failures → open 60s)
```

**Implementation:** Dùng library `pybreaker` (Python) thay vì tự viết.

**Trạng thái:**
```
Closed    → requests đi bình thường, đếm failures
Open      → requests bị reject ngay, trả fallback response
Half-Open → cho 1 request thử, nếu OK → Close, nếu fail → Open lại
```

**Observability (bắt buộc):**
- Metric: `circuit_breaker_state{service="payment", state="open|closed|half_open"}` (Gauge)
- Metric: `circuit_breaker_failures_total{service="payment"}` (Counter)
- Alert: `CircuitBreakerOpen` — fires khi CB ở state "open" > 30s
- Log: structured log mỗi state transition với `trace_id`

### Rate Limiting

Áp dụng ở API Gateway (điểm vào duy nhất):

```
Global:     100 requests/second
Per-user:   20 requests/second (dựa trên JWT user_id)
Per-IP:     50 requests/second (cho unauthenticated endpoints)
```

**Implementation:** Redis-based sliding window counter.

**Observability:**
- Metric: `rate_limit_hits_total{tier="global|user|ip"}` (Counter)
- Internal bypass: requests với `X-Internal-Service` header + service JWT skip rate limit
- Response: 429 + RFC 7807 body + `Retry-After` header
- Alert: `RateLimitSpikeDetected` — rate_limit_hits > 100/min sustained 5min

### Structured Error Response (RFC 7807)

Tất cả services trả error theo chuẩn:

```json
{
  "type": "https://api.example.com/errors/insufficient-stock",
  "title": "Insufficient Stock",
  "status": 409,
  "detail": "Product 'Laptop' only has 2 in stock, requested 5",
  "instance": "/orders/ORD-20250512-001",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```

**Tại sao:** Khi có 10 services, error format không thống nhất → debug rất khó. `trace_id` trong error response giúp correlate với distributed traces.

### Graceful Shutdown (Kafka Consumers)

Tất cả Kafka consumers phải xử lý SIGTERM đúng:

```python
import signal, sys

def shutdown_handler(signum, frame):
    consumer.close()    # commits final offsets
    db_connection.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown_handler)
```

```yaml
# docker-compose.yml
services:
  notification-worker:
    stop_grace_period: 30s   # thời gian chờ trước SIGKILL
```

**Tại sao:** Kill consumer mid-processing có thể gây duplicate processing hoặc saga state inconsistency.

### TLS Termination

HTTPS cho tất cả external traffic:

```
Client ──HTTPS──► nginx (TLS termination) ──HTTP──► API Gateway ──► services
```

- Self-signed certificates cho lab (openssl)
- nginx reverse proxy handle TLS
- Internal traffic giữa services vẫn HTTP (within Docker network)
- Certificate renewal procedure (scripted)

**DevOps learning:** TLS setup, certificate management, nginx SSL config, redirect HTTP→HTTPS.

### Secrets Management

Không hardcode secrets trong docker-compose.yml:

```yaml
# docker-compose.yml
services:
  order-service:
    env_file: .env.order   # file-based secrets, NOT inline
    secrets:
      - db_password
      - jwt_public_key

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_public_key:
    file: ./secrets/jwt_public.pem
```

- `.env.*` files trong `.gitignore`
- `secrets/` directory với restricted permissions (chmod 600)
- JWT key pair: private key chỉ Auth Service có, public key distribute cho các services
- Rotation procedure: generate new key → deploy public key → rotate private key

### Network Segmentation

Tách Docker networks theo tier:

```yaml
networks:
  frontend:    # Web UI, nginx
  backend:     # API Gateway, services
  data:        # PostgreSQL, Redis, Kafka, OpenSearch
  observability:  # OTel, Prometheus, Grafana (external)

services:
  web-ui:
    networks: [frontend]
  api-gateway:
    networks: [frontend, backend]   # bridge frontend → backend
  order-service:
    networks: [backend, data]       # access DB/cache
  postgres:
    networks: [data]                # chỉ data tier access được
```

**Tại sao:** Web UI không nên connect trực tiếp tới PostgreSQL. Network segmentation enforce tại infrastructure level.

### Resource Limits

```yaml
services:
  order-service:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
  opensearch:
    deploy:
      resources:
        limits:
          memory: 3G    # JVM heap + OS overhead
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
```

**Tại sao:** Without limits, 1 service có thể eat toàn bộ RAM của VM → OOM killer random containers.

### Backup & Restore

```bash
# Backup per-database
pg_dump -h localhost -U app_user app_db > backup/app_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U auth_user auth_db > backup/auth_db_$(date +%Y%m%d).sql
pg_dump -h localhost -U shipping_user shipping_db > backup/shipping_db_$(date +%Y%m%d).sql

# Restore
pg_restore -h localhost -U app_user -d app_db < backup/app_db_20250519.sql

# Verify backup integrity
pg_restore --list backup/app_db_20250519.sql  # dry-run, no actual restore
```

- Backup schedule: daily (cron or Docker healthcheck trick)
- Retention: 7 days local, rotate oldest
- Verify: monthly restore drill to verify backups are usable
- **RTO/RPO definitions:** RTO = 30 min (restore from backup), RPO = 24h (daily backup)

### Log Rotation

```yaml
# docker-compose.yml — apply cho tất cả services
services:
  order-service:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

**Tại sao:** Without log rotation, Docker logs grow unbounded → disk full → entire VM down.

### CI Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  lint-test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint (flake8)
        run: flake8 applications-vm/applications/
      - name: Unit tests
        run: pytest applications-vm/applications/ --tb=short
      - name: Build images
        run: docker compose -f applications-vm/applications/docker-compose.yml build
      - name: Health check smoke test
        run: |
          docker compose up -d
          sleep 30
          curl -f http://localhost:5000/health/live
          docker compose down
```

- Deploy vẫn manual (`docker compose pull && up -d` trên VM)
- CI chỉ validate: code quality + build success + basic health
- Production deployment automation thuộc AWS plan (Terraform + ECS)

### Observability Mở Rộng

#### 1. Per-Service Metrics (mỗi service mới phải có)
| Metric type | Ví dụ | Instrument |
|-------------|-------|------------|
| Request rate | `http_requests_total{service="auth", method="POST", path="/login"}` | Counter |
| Latency | `http_request_duration_seconds{service="shipping"}` | Histogram |
| Error rate | `http_requests_total{status="5xx", service="search"}` | Counter |
| Business metric | `saga_compensations_total{reason="shipping_failed"}` | Counter |
| Queue lag | `kafka_consumer_lag{group="shipping-worker"}` | Gauge |
| Circuit breaker state | `circuit_breaker_state{target="payment", state="open"}` | Gauge |
| DB connections | `db_pool_active_connections{database="auth_db"}` | Gauge |

#### 2. SLI/SLO Definitions
| Service | SLI | SLO Target | Error Budget (30d) |
|---------|-----|------------|--------------------|
| API Gateway | Availability (non-5xx) | 99.5% | 216 phút |
| API Gateway | Latency P95 < 500ms | 95% | 2160 phút |
| Payment Service | Success rate | 99.0% | 432 phút |
| Auth Service | Login latency P99 | < 200ms (99.5%) | 216 phút |
| Auth Service | Token verify latency P99 | < 50ms (99.9%) | 43 phút |
| Shipping Service | Creation success rate | 99.5% | 216 phút |
| Shipping Service | Creation latency P95 | < 500ms (95%) | 2160 phút |
| Shipping Worker | Saga completion rate | 99% | 432 phút |
| Search Service | Query latency P95 | < 300ms (95%) | 2160 phút |
| Search Service | Index lag | < 10s (95% compliant) | 2160 phút |

**MWMBR Alert Thresholds (Multi-Window Multi-Burn-Rate):**
| Severity | Burn Rate | Short Window | Long Window | Budget consumed | Action |
|----------|-----------|--------------|-------------|-----------------|--------|
| Critical (page) | 14.4x | 5m | 1h | 2% trong 1h | Page on-call |
| Warning (ticket) | 3x | 30m | 6h | 5% trong 6h | Tạo ticket |

**Traffic Guards (chống phantom alerts):**
- Tất cả SLO alerts PHẢI có điều kiện `rate(total_requests[5m]) > 0.1`
- Ngăn alert firing khi không có traffic (stale metrics từ lần chạy trước)
- Đặc biệt quan trọng cho low-traffic services (Auth login lúc 3AM, webhook endpoints)

#### 3. Grafana Dashboards Mới
| Dashboard | Loại | Panels chính |
|-----------|------|--------------|
| Auth Overview | Service | Login rate, token refresh rate, failed logins, active sessions, brute force detection |
| Saga Monitor | Business flow | Saga duration histogram, state machine flow (Node Graph), compensation rate, DLQ size |
| Search Health | Service | Index lag, query latency P95, OpenSearch cluster health, reindex progress |
| Cross-Service | Architecture | Service dependency map, error propagation paths, trace duration distribution |
| Synthetic Journeys | Proactive | Journey success rate (by location), P95 duration, failure breakdown by step |
| Business KPIs | Business | Revenue/hour, payment success by provider, cart abandonment rate, search conversion funnel |
| User Activity | Debug | User journey timeline, error rate per user, session duration (filter by user_id) |
| Order Details | Debug | Order lifecycle timeline, processing time per step, related logs (filter by order_id) |

**Dashboard Correlation Features:**
- Derived Fields trong Loki datasource: click `trace_id` → jump to Tempo
- Derived Fields: click `saga_id` → jump to Saga Monitor với filter
- Derived Fields: click `user_id` → jump to User Activity dashboard
- Derived Fields: click `order_id` → jump to Order Details dashboard

#### 4. Saga Distributed Tracing
**Problem:** Saga pattern liên quan 5+ services. Khi Saga fail ở step 3, cần trace toàn bộ lifecycle để debug.

**Solution (chi tiết implementation xem Phase 4):**
1. Inject `saga_id` vào mọi span trong Saga Worker (span attribute)
2. Propagate `saga_id` qua Kafka headers (bên cạnh W3C `traceparent` chuẩn)
3. Enrich structured logs với `saga_id` (đồng bộ qua 3 pillars)
4. OTel Collector: whitelist `saga.id` trong spanmetrics + tail-sampling
5. Tail-sampling policy: giữ 100% traces có `saga.state=COMPENSATING`

**Tempo TraceQL Queries (lưu mẫu):**
- `{ span.saga.state = "COMPENSATING" }` — tìm tất cả sagas bị compensation
- `{ span.saga.id != "" && duration > 30s }` — tìm sagas chậm

**Recording Rules:** `saga:duration_p95:5m`, `saga:failure_rate:5m`, `saga:dlq_size`

#### 5. Multi-ID Log Correlation
**Problem:** Hiện tại chỉ có `trace_id` trong logs. Thiếu context để debug business-level issues (cần `user_id`, `order_id`, `session_id`).

**Solution:**
1. Enrich logs với multiple correlation IDs.
2. Loki pipeline: extract IDs từ JSON logs (KHÔNG đưa vào Loki labels để tránh cardinality explosion).
3. Grafana Derived Fields: biến IDs thành hyperlinks trong Log panel.

**LogQL Queries (lưu mẫu):**
- `{container_name=~".+"} | json | user_id="user-123"` — tất cả logs của 1 user
- Cross-correlation: `{user_id="user-123"} | saga_id!=""` — tìm sagas của 1 user

#### 6. Synthetic Monitoring (User-Centric SLIs)
**Problem:** Blackbox Exporter chỉ probe `/health/live` → passive monitoring. Cần test full user journeys từ outside-in.

**Solution:**
1. Playwright E2E tests đóng gói thành Docker container headless Chrome.
2. Chạy định kỳ mỗi 5 phút, push metrics về Prometheus.
3. SLO mới: "95% purchase journeys complete < 5s từ tất cả locations".
4. Alert: `SyntheticJourneyFailing` — phát hiện issues TRƯỚC KHI real users report.

#### 7. Business Metrics (Bridge Tech ↔ Business)
| Metric | Service | Type | Ý nghĩa business |
|--------|---------|------|------------------|
| `revenue_dollars` | Order Service | Histogram | Revenue per hour (real-time) |
| `payment_success_total{provider}` | Payment Service | Counter | Payment success by provider |
| `search_to_purchase_total` | Search Service | Counter | Search queries dẫn đến purchase |
| `cart_additions_total` vs `cart_checkouts_total` | API Gateway | Counter | Cart abandonment rate |

**Recording Rules:** `business:revenue_per_hour:1h`, `business:cart_abandonment_rate:1h`

#### 8. Alerts cho Services Mới
| Alert | Severity | Condition | Service |
|-------|----------|-----------|---------|
| AuthLoginLatencyFastBurn | critical | P99 > 200ms, burn rate 14.4x (5m + 1h) | Auth |
| AuthBruteForceDetected | warning | Failed logins > 10/min từ 1 IP | Auth |
| ShippingSuccessRateFastBurn | critical | Success rate burn rate 14.4x (5m + 1h) | Shipping |
| SagaHighFailureRate | critical | Compensation rate > 5% trong 5 phút | Shipping Worker |
| SagaDLQGrowing | warning | DLQ messages > 10 trong 10 phút | Shipping Worker |
| SearchIndexLagFastBurn | critical | Index lag burn rate 14.4x (5m + 1h) | Search |
| CircuitBreakerOpen | warning | CB ở state "open" > 30s | Tất cả services dùng CB |

**Lưu ý:** Tất cả SLO alerts PHẢI có traffic guard để tránh phantom alerts.

---

## Phân Phase Triển Khai

### Phase 0: Production Readiness (trước khi thêm services)

### Phase 0: Infrastructure & CI Hardening (App-level ĐÃ HOÀN THÀNH)
**Effort:** ~2-3 ngày
**Dependencies:** Không có
**Impact:** Toàn bộ 6 services hiện tại

#### 🟢 Application Level (ĐÃ HOÀN THÀNH - VƯỢT MONG ĐỢI)
*(Codebase đã tự động implement các guardrails này trong lần refactor Phase 5)*
- [✅] Health checks: `/health/live` + `/health/ready` (chuẩn K8s/ECS)
- [✅] RFC 7807 Error Format (`shared/errors.py`)
- [✅] Graceful Shutdown Manager (`shared/shutdown_handler.py` - Callback registry, flush Kafka, close DB pool)
- [✅] HTTP Semantic Mapping (Chống bẫy HTTP 200 Trap)
- [✅] Idempotency State Machine (Redis Lua Script)

#### 🟡 Infrastructure Level (CẦN TRIỂN KHAI)
1. **Network segmentation:** Tách Docker networks (`frontend`, `backend`, `data`, `observability`). Hiện tại đang dùng single bridge `observability` (Rủi ro bảo mật: Web UI có thể ping thẳng PostgreSQL).
2. **Resource limits:** Thêm `deploy.resources.limits` (CPU/RAM) cho TẤT CẢ containers trong `docker-compose.yml` để chống OOM Killer.
3. **Log rotation:** Thêm `logging: { driver: json-file, options: { max-size: "10m", max-file: "3" } }` cho tất cả services.
4. **stop_grace_period:** Set `stop_grace_period: 30s` cho Kafka Workers trong `docker-compose.yml` để khớp với `GracefulShutdown` timeout.

#### 🔵 CI/CD Level
5. **Setup GitHub Actions:** Pipeline `lint (flake8)` → `pytest` → `docker build` → `smoke test`.

### Phase 1: Auth Service + TLS + Secrets

```
Effort: ~4-5 ngày
Dependencies: Phase 0 (health checks, network segmentation)
Impact: Tất cả services cần update middleware

Application:
  1. Tạo auth_db + init-auth.sql (users, refresh_tokens tables)
  2. Tạo Auth Service (register, login, verify, refresh)
  3. Update API Gateway — thêm JWT middleware (local public key verification) + rate limiting
  4. Update Order Service — extract user_id từ token
  5. Update Web UI — thêm login/register page

Infrastructure:
  6. TLS termination: self-signed cert + nginx SSL config
  7. Secrets management: JWT key pair, DB passwords trong .env files + Docker secrets
  8. HTTP → HTTPS redirect

Observability:
  9. Thêm Grafana dashboard: Auth Overview
  10. Alert: AuthBruteForceDetected (failed logins > 10/min)

Runbook deliverables:
  - RB-AUTH-01: Auth Service Down (new logins fail, existing sessions OK)
  - RB-AUTH-02: Brute Force Detected (rate limit spike on /auth/login)
  - RB-AUTH-03: JWT Key Rotation procedure
  - RB-TLS-01: Certificate Expired / Renewal

Verify:
  - Unauthenticated request → 401
  - Authenticated request → flow bình thường
  - Expired token → 401, refresh → new token
  - Rate limit exceeded → 429 Too Many Requests
  - Auth Service down → existing JWT vẫn valid (local verification)
  - HTTPS works, HTTP redirects to HTTPS
  - Secrets không hiện trong docker-compose.yml hoặc git
```

### Phase 2: Shipping Service + Shipping Worker + Backup

```
Effort: ~5-7 ngày
Dependencies: Phase 1 (Auth) nếu muốn auth, hoặc độc lập
Impact: Mở rộng order lifecycle, thêm Kafka topics

Application:
  1. Tạo shipping_db + init-shipping.sql (shipments + saga_state tables)
  2. Tạo Shipping Service (CRUD shipments) + circuit breaker
  3. Tạo Shipping Worker (Saga orchestrator) + DLQ handling + crash recovery
  4. Thêm Kafka topics: order.shipped, order.shipping_failed, order.refunded
  5. Thêm DLQ topic: order.shipping.dlq
  6. Update Notification Worker — handle shipping events
  7. Update Inventory Worker — handle refund events
  8. Update Web UI — hiển thị shipping status + tracking

Infrastructure:
  9. Backup/Restore: setup pg_dump scripts cho app_db, auth_db, shipping_db
  10. Horizontal scaling test: chạy 2 instances Shipping Worker (consumer group rebalancing)
  11. Backup verification: restore backup to temp DB, verify data integrity

Observability:
  12. Thêm Grafana dashboard: Saga Monitor
  13. Alert: SagaStuckInPending, DLQGrowing, CircuitBreakerOpen

Runbook deliverables:
  - RB-SAGA-01: Saga Stuck in PENDING (timeout not triggered)
  - RB-SAGA-02: DLQ Growing (compensation failures accumulating)
  - RB-SAGA-03: Shipping Service Down (CB open, sagas queuing)
  - RB-BACKUP-01: Database Restore Procedure (per-database)

Verify:
  - Order → Payment OK → Shipping OK → status: shipped
  - Order → Payment OK → Shipping FAIL → refund → status: refunded
  - Kill Shipping Worker mid-saga → resume after restart (saga_state)
  - Saga timeout → DLQ → manual review
  - Circuit breaker open → Shipping Worker stops calling Shipping Service
  - 2 Shipping Workers → Kafka rebalance, no duplicate processing
  - Backup restore drill: dump → drop → restore → verify data
```

### Phase 3: Search Service + Index Management

```
Effort: ~3-4 ngày
Dependencies: Không có — standalone service
Impact: Thêm OpenSearch container, data sync

Application:
  1. Thêm OpenSearch container vào docker-compose (+ healthcheck + resource limits 3GB)
  2. Tạo Search Service (search API + event-driven indexing)
  3. Implement idempotent sync (order_id as document _id, upsert)
  4. Implement backfill: POST /search/reindex → full scan app_db
  5. Implement index aliasing (orders_v1, orders_v2) for zero-downtime reindex
  6. Update API Gateway — route /search/* (circuit breaker)
  7. Update Web UI — thêm search bar

Infrastructure:
  8. OpenSearch snapshot/backup configuration
  9. Index lifecycle policy (delete old indices after 30 days)
  10. Failure handling: search.sync.dlq cho failed indexing

Observability:
  11. Thêm Grafana dashboard: Search Health (index lag, query latency)
  12. Metric: search_index_lag_seconds (event timestamp vs indexed_at)
  13. Alert: SearchIndexLagHigh (lag > 30s)

Runbook deliverables:
  - RB-SEARCH-01: OpenSearch Cluster Red (all replicas lost)
  - RB-SEARCH-02: Index Corruption → Reindex from PostgreSQL
  - RB-SEARCH-03: Search Index Lag High (sync falling behind)

Verify:
  - Search trả kết quả đúng
  - Tạo order mới → search thấy sau ≤ 5s (measure actual lag)
  - OpenSearch down → graceful error, core flow không ảnh hưởng
  - Reindex command → full sync hoàn tất
  - Zero-downtime reindex: alias switch với no search disruption
```

### Phase 4: Advanced Observability & Reliability Engineering
**Effort:** ~5-7 ngày  
**Dependencies:** Phase 1-3 hoàn tất (Toàn bộ 10 services đã chạy ổn định)  
**Impact:** Toàn bộ pipeline Observability, thay đổi cách định nghĩa reliability và debug  

**Mục tiêu:**
Chuyển dịch observability từ "reactive monitoring" (đợi alert mới biết lỗi) sang "proactive reliability engineering" (đo lường business impact, proactive synthetic testing, và debug distributed transactions end-to-end).

**5 Trụ cột triển khai:**  
A. Saga Distributed Tracing  
B. SLO & MWMBR Alerting cho services mới  
C. Synthetic Monitoring (User-Centric SLIs)  
D. Multi-ID Log Correlation  
E. Business Metrics Instrumentation  

#### A. Saga Distributed Tracing (Gắn với Phase 2)
**Application:**
1. Instrument Saga Worker để inject `saga_id` và `saga_state` vào OTel span attributes.
2. Cấu hình Kafka Producer/Consumer inject và extract `saga_id` qua Kafka message headers (bên cạnh W3C `traceparent` chuẩn).
3. Enrich structured logs của tất cả workers với `saga_id` để đồng bộ qua 3 pillars.

**Infrastructure:**  

4. Update OTel Collector config: Thêm `saga.id` vào whitelist của spanmetrics connector và tail-sampling policies (luôn giữ lại 100% traces có `saga.state=COMPENSATING`).

**Observability:**  

5. Grafana Dashboard "Saga Monitor":
   - Panel: Saga Duration Distribution (Histogram).
   - Panel: Saga State Machine Flow (Node Graph plugin).
   - Panel: DLQ Size & Compensation Failure Rate.  
6. Tempo TraceQL Queries: Lưu các query mẫu để tìm traces theo `saga.id` hoặc filter các sagas bị timeout.
7. Recording Rules & Alerts:
   - Alert: `SagaHighFailureRate` (Tỷ lệ compensation > 5% trong 5 phút).
   - Alert: `SagaDLQGrowing` (Messages trong DLQ topic > 10).

#### B. SLO & MWMBR Alerting cho Services Mới
**Application:**
1. Định nghĩa SLIs cho các services mới:
   - Auth Service: Login latency P99 < 200ms (Target 99.5%).
   - Shipping Service: Shipment creation success rate (Target 99.5%).
   - Search Service: Query latency P95 < 300ms & Index lag < 10s (Target 95%).

**Infrastructure:**  

2. Prometheus Recording Rules: Tạo các SLI recording rules theo chuẩn naming convention `sli:<service>_<signal>:<window>` (5m, 30m, 1h, 6h).

**Observability:**  

3. Grafana SLO Dashboard: Mở rộng dashboard hiện tại, thêm các gauges và burn-rate charts cho Auth, Shipping, Search.
4. MWMBR Alerts (Multi-Window Multi-Burn-Rate):
   - Cấu hình Fast-burn (14.4x) và Slow-burn (3x) alerts cho các SLOs mới.
   - Áp dụng Traffic Guards (dựa trên span metrics) để tránh phantom alerts khi không có traffic.
#### Traffic Guards (Leveraging Existing Codebase)
Codebase (`api-gateway/app.py`) đã tự động gắn label `traffic_source` (`browser`, `synthetic_probe`, `synthetic_loadtest`) vào mọi metrics.
Khi cấu hình Prometheus Alerting Rules cho Phase 4, **BẮT BUỘC** phải filter label này để tránh Phantom Alerts:

```yaml
# ✅ ĐÚNG: Chỉ alert khi có lỗi từ người dùng thật (browser)
expr: |
  sum(rate(api_gateway_requests_total{status="error", traffic_source="browser"}[5m]))
  /
  sum(rate(api_gateway_requests_total{traffic_source="browser"}[5m])) > 0.01

# ❌ SAI: Sẽ alert giả khi Traffic Generator chạy load test bị lỗi
expr: |
  sum(rate(api_gateway_requests_total{status="error"}[5m]))
  /
  sum(rate(api_gateway_requests_total[5m])) > 0.01
```
#### C. Synthetic Monitoring (User-Centric SLIs)
**Infrastructure:**
1. Đóng gói Playwright E2E tests thành một Docker container headless Chrome.
2. Triển khai container này trong Docker Compose, cấu hình chạy định kỳ (Cron / Systemd timer) mỗi 5 phút.
3. Deploy một lightweight metrics exporter (Python/Node) để parse JSON results từ Playwright và push metrics (journey duration, success rate) về Prometheus Pushgateway.

**Observability:**  

4. Grafana Dashboard "Synthetic Journeys": Hiển thị Success Rate và P95 Duration của các luồng "Critical Purchase" và "Search" từ góc độ người dùng thực tế (outside-in).
5. Alert: `SyntheticJourneyFailing` (Báo động khi luồng E2E lõi fail 2 lần liên tiếp, bất kể server-side metrics có đang xanh hay không).

#### D. Multi-ID Log Correlation
**Application:**
1. Chuẩn hóa logging context: Đảm bảo mọi services đều enrich logs với `user_id`, `session_id`, `order_id` (bên cạnh `trace_id`, `span_id` mặc định của OTel).

**Infrastructure:**  

2. Grafana Alloy / Loki Pipeline: Cấu hình pipeline extract các correlation IDs này từ JSON logs (nhưng KHÔNG đưa vào Loki labels để tránh cardinality explosion, chỉ dùng cho LogQL line filters).
3. Grafana Datasource Config (Derived Fields):
   - Cấu hình regex để biến `saga_id`, `user_id`, `order_id` trong Log panel thành các hyperlink.
   - Click vào `trace_id` -> Jump to Tempo.
   - Click vào `order_id` -> Jump to Business KPI dashboard với filter sẵn.

#### E. Business Metrics Instrumentation
**Application:**
1. Instrument OTel Custom Metrics gắn liền với business KPIs:
   - Order Service: `revenue_dollars` (Histogram).
   - Payment Service: `payment_success_total` (Counter, group by provider).
   - Search Service: `search_to_purchase_total` (Counter, track qua session_id).
   - API Gateway: `cart_additions_total` vs `cart_checkouts_total`.

**Observability:**  

2. Grafana Dashboard "Business KPIs":
   - Panel: Real-time Revenue per Hour.
   - Panel: Payment Success Rate by Provider (Stripe vs PayPal).
   - Panel: Cart Abandonment Rate.
   - Panel: Search Conversion Funnel.
3. Business Alerts (Optional): `RevenueDropped`, `HighCartAbandonment`, `PaymentProviderDegraded`.

**Runbook Deliverables:**
- RB-SAGA-04: Saga High Failure Rate & DLQ Overflow.
- RB-SLO-NEW: SLO Violation cho Auth, Shipping, Search.
- RB-SYNTHETIC-01: Synthetic Journey Failing (Outside-in troubleshooting).
- RB-CORRELATION-01: Debug User-Specific & Saga Issues (Multi-ID tracing).
- RB-BUSINESS-01: Payment Provider Degraded & Revenue Drop.

**Verify:**
- Trace một Saga từ Order -> Payment -> Shipping trên Tempo, thấy full chain `saga_id` và state transitions.
- Inject latency vào Auth Service -> AuthLoginLatencyFastBurn alert fires trong < 2 phút.
- Stop Payment Service -> Synthetic Journey alert fires (dù server-side health checks vẫn có thể pass).
- Query Loki bằng `{user_id="user-123"} | saga_id!=""` để cross-correlate user actions với backend sagas.
- Dashboard Business KPIs cập nhật real-time revenue và cart abandonment rate khi chạy Traffic Generator.

### Phase 5: Integration + Chaos Testing + SLO + DR Drill

```
Effort: ~5-7 ngày
Dependencies: Phase 0-3 hoàn tất

Integration:
  1. End-to-end test toàn bộ 10 services
  2. Thiết lập SLI/SLO dashboards trong Grafana
  3. Thêm alerting rules:
     - Saga failure rate > 5% → alert
     - Auth error rate > 1% → alert (brute force?)
     - Search index lag > 30s → alert
     - Circuit breaker open → alert

Chaos Exercises:
  4. Kill Auth → observe existing sessions still work (local JWT) → new logins fail
  5. Kill Shipping mid-saga → verify crash recovery from saga_state
  6. Corrupt OpenSearch index → verify graceful degradation + reindex
  7. Kafka consumer lag → verify backpressure + scaling
  8. PostgreSQL stop + restart → verify reconnection + health check transition
  9. Fill disk to 95% → verify predict_linear alert fires

Disaster Recovery Drill:
  10. Full DR: dump all DBs → docker compose down → remove volumes → restore → verify
  11. Document RTO (target: 30 min) và RPO (target: 24h) thực tế
  12. On-call simulation: trigger random alert, triage theo runbook, đo MTTR

Documentation:
  13. Update INCIDENT_RUNBOOK.md với runbooks từ Phase 1-3
  14. Document SLO burn rate qua 1 tuần vận hành
  15. Write post-mortem template cho mỗi chaos exercise

Verify:
  - Tất cả traces span đúng 10 services
  - SLO dashboards hiển thị burn rate
  - Mỗi chaos exercise có documented recovery < 5 phút
  - Alert → Telegram notification trong < 1 phút
  - DR drill: full restore hoàn tất < 30 phút
  - CI pipeline pass với 10 services
```

### Phase 6: Reliability & Automated Testing Strategy

**Effort:** ~5-7 ngày  
**Dependencies:** Phase 4 (Integration & Chaos) hoàn tất  
**Impact:** Toàn bộ CI/CD pipeline, thay đổi cách merge code và deploy

**Mục tiêu:**  
Chuyển dịch từ "Manual Testing & Chaos" (Phase 4) sang "Automated Reliability Gates".  
Đảm bảo mọi thay đổi code đều được validate tự động về: Performance (SLO), API Contracts (Anti-breakage), và User Journeys (E2E) trước khi merge.

#### Testing Pillars & Tooling Strategy

| Pillar | Tool | Mục đích (SRE/Platform Lens) | Integration Point |
|--------|------|------------------------------|-------------------|
| Performance & SLO | k6 | Validate P99 latency & throughput không vi phạm SLO khi có code mới | CI Pipeline, export metrics to Prometheus |
| API Contract | Pact | Ngăn chặn breaking changes giữa 10 services (Consumer-Driven Contracts) | Pact Broker container, CI pre-merge gate |
| Synthetic / E2E | Playwright | Đo lường SLI từ góc độ người dùng (User Journey) thay vì chỉ server-side metrics | Scheduled container (Cron), push metrics to Pushgateway |

#### Architecture & Integration
**1. k6 Load Testing (Performance Baseline):**
- Chạy script `baseline.js` trong CI sau khi build Docker image thành công
- k6 output trực tiếp vào Prometheus (qua remote_write hoặc OTel Collector)
- CI Gate: Auto-fail PR nếu `p99 latency > SLO threshold` hoặc `error rate > 0.5%`

**2. Pact Contract Testing (API Governance):**
- Deploy `pact-broker` (Ruby/PostgreSQL) làm service phụ trợ trong Docker Compose (hoặc CI container)
- Các service đóng vai trò Consumer (VD: Shipping Worker) publish expectations
- Các service đóng vai trò Provider (VD: Order Service) verify contracts trước khi cho phép merge
- Ngăn chặn lỗi: Order Service đổi tên field `order_id` -> `orderId` làm Shipping Worker crash

**3. Playwright Synthetic Monitoring (User-Centric SLI):**
- Đóng gói Playwright tests thành một Docker container headless Chrome
- Chạy định kỳ (mỗi 5 phút) trên Observability VM hoặc CI nightly
- Đo thời gian hoàn thành luồng "Login -> Create Order -> View Events"
- Push duration metrics về Prometheus để hiển thị trên Grafana SLO Dashboard

#### Deliverables (Cấu trúc thư mục mới)
```plaintext
on-premises/
└── tests/
    ├── load/                  # k6 scripts & thresholds
    │   ├── baseline.js
    │   └── stress.js
    ├── contracts/             # Pact consumer/provider tests
    │   ├── broker/            # Docker compose cho Pact Broker
    │   ├── consumers/
    │   └── providers/
    └── e2e/                   # Playwright synthetic journeys
        ├── journeys/
        └── Dockerfile         # Headless chrome container
```
#### Observability (Mở rộng Grafana)

- **Dashboard:** "CI/CD Reliability Gates" (Hiển thị lịch sử P99 latency qua các lần chạy k6)
- **Dashboard:** "Synthetic User Journeys" (Success rate & duration của Playwright tests)
- **Alert:** `SyntheticJourneyFailing` (Báo động khi luồng E2E lõi bị lỗi, bất kể server metrics có đang xanh hay không)

#### Verify

- Tạo một PR cố tình làm thay đổi HTTP Status Code của Order Service → CI block merge do Pact Contract fail
- Tạo một PR cố tình thêm `time.sleep(2)` vào Payment Service → CI block merge do k6 P99 vượt SLO
- Dashboard Synthetic hiển thị được thời gian thực của luồng "Create Order" từ góc độ browser
- Toàn bộ tests chạy headless và tự động cleanup sau khi CI chạy xong

---

## Chi Phí Ảnh Hưởng

### Docker Compose (On-Premises)

| Resource | Hiện tại (6 svc) | Sau mở rộng (10 svc) | Delta |
|----------|-----------------|---------------------|-------|
| RAM | ~2.5 GB | ~7 GB (+OpenSearch ~3 GB) | +4.5 GB |
| CPU | 2-4 cores đủ | 6-8 cores khuyến nghị | +4 cores |
| Disk | ~1 GB | ~5 GB (OpenSearch indices + backups) | +4 GB |

### AWS (ước tính khi deploy)

| Resource | Hiện tại | Sau mở rộng | Delta |
|----------|---------|-------------|-------|
| ECS Tasks | 6 tasks | 10 tasks | +~$20/mo |
| OpenSearch | - | t3.small.search | +~$25/mo |
| Kafka topics | 3 | 8 | +~$5/mo |
| **Total delta** | | | **+~$50/mo** |

---

## Tổng Kết

| Metric | Trước | Sau |
|--------|-------|-----|
| Services | 6 | 10 |
| Kafka topics | 3 | 8 + 1 DLQ |
| Design patterns | 7 | 25+ |
| Failure scenarios | ~5 | ~15 |
| Resilience patterns | 0 | 5 (CB, rate limit, health checks, graceful shutdown, graceful degradation) |
| Security | 0 | 3 (TLS, secrets management, JWT/RBAC) |
| Communication patterns | 2 (HTTP, Kafka) | 3 (+JWT propagation) |
| Database systems | 2 (PostgreSQL, Redis) | 3 (+OpenSearch) |
| Databases | 1 (shared) | 3 (app_db, auth_db, shipping_db) + OpenSearch |
| DB strategy | Shared DB | Hybrid (1 instance, multiple DBs) |
| Infrastructure ops | Basic | Network segmentation, resource limits, log rotation, backup/restore |
| CI/CD | None | GitHub Actions (lint → test → build) |
| Observability | Metrics + Logs + Traces | + SLI/SLO dashboards + per-service metrics + CB/rate limit metrics |
| Grafana dashboards | Existing | +4 (Auth, Saga, Search, Cross-Service) |
| Runbooks | 0 per new service | 10+ (per-phase deliverables) |
| Effort | - | ~20-27 ngày (5 phases) |

> **Kết luận:** Mở rộng 4 services + production-grade operational patterns sẽ tăng learning surface gấp ~4x so với hiện tại. Docker Compose được sử dụng như **production orchestrator** (không phải toy/demo) — tất cả concepts (TLS, secrets, network segmentation, backup, CI, graceful shutdown) đều production-grade, chỉ khác K8s ở deployment tooling. AWS deployment với Terraform/EKS/ECS là plan riêng.
