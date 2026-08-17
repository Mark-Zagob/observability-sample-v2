# 🔧 Break / Test / Recovery Guide (Production-Grade)

## Mục tiêu
Hiểu sâu internals của từng infrastructure component bằng cách **phá → kiểm tra bên trong → khôi phục**. Khác với Incident Simulation (luyện đọc dashboard + triage), B/T/R tập trung vào **CLI/query inspection** — bạn sẽ biết component hoạt động thế nào dưới "nắp ca-pô".

**Prerequisite:** Đã hoàn thành ít nhất Experiment 1-4 trong `INCIDENT_SIMULATION_GUIDE.md`.
---

## Khi nào dùng BTR vs Incident Simulation?

| Scenario | Dùng guide nào |
|----------|----------------|
| Alert firing lúc 3 AM | **IS** — Đọc dashboard, triage nhanh |
| Muốn hiểu tại sao connection pool exhaustion | **BTR PG-1** — Inspect pg_stat_activity |
| Kafka consumer lag tăng | **IS** Exp 3 — Dashboard path |
| Muốn hiểu tại sao lag tăng (offsets? rebalance?) | **BTR KF-1, KF-4** — CLI inspection |
| Production incident cần fix nhanh | **IS** + **RUNBOOK** |
| Learning session, muốn hiểu sâu | **BTR** |

**Workflow kết hợp:**
1. Chạy IS experiment → thấy symptom trên dashboard
2. Dùng BTR để hiểu **tại sao** symptom đó xảy ra
3. Viết post-mortem với cả 2 perspectives

**Ví dụ thực tế:**
- IS Exp 2 (DB Saturation) cho thấy P95 tăng 8x
- BTR PG-1 giải thích **tại sao** pool exhaustion xảy ra (gthread workers vs pool max)
- BTR PG-5 chỉ cách **detect** lock trước khi nó gây saturation
- BTR PG-2 giải thích **hậu quả lâu dài** (dead tuples, bloat)

---

## Mục lục
- [Part 1: PostgreSQL Deep Dive (PG-1 → PG-6)](#part-1-postgresql-deep-dive) — applications-vm
- [Part 2: Kafka Deep Dive (KF-1 → KF-5)](#part-2-kafka-deep-dive) — applications-vm
- [Part 3: Redis Deep Dive (RD-1 → RD-4)](#part-3-redis-deep-dive) — applications-vm
- [Part 4: Prometheus Deep Dive (PM-1 → PM-4)](#part-4-prometheus-deep-dive) — observability-vm
- [Part 5: Loki Deep Dive (LK-1 → LK-3)](#part-5-loki-deep-dive) — observability-vm
- [Part 6: Alertmanager Deep Dive (AM-1 → AM-3)](#part-6-alertmanager-deep-dive) — observability-vm
- [Part 7: OTel + Tempo Pipeline (OT-1 → OT-3)](#part-7-otel--tempo-pipeline) — observability-vm
- [Recommended Order](#recommended-order)

---

## Quy ước format

Mỗi exercise theo 3 pha:

| Pha | Mục tiêu | Output |
|-----|----------|--------|
| **Break** | Tạo trạng thái bất thường | Component ở trạng thái broken/degraded |
| **Test** | Inspect internals — chuyện gì đang xảy ra bên trong? | Hiểu output của CLI/query diagnostic |
| **Recovery** | Khôi phục + verify | Component trở lại trạng thái bình thường |

> 💡 **Khác IS:** IS hỏi "dashboard nào cho thấy vấn đề?". B/T/R hỏi "CLI nào cho thấy **bên trong** component?"

---

# Part 1: PostgreSQL Deep Dive

> **VM:** applications-vm
> **Access:** `docker exec -it postgres psql -U app -d orders`
> **Tables:** `orders`, `products`
> **Pool:** `SimpleConnectionPool(minconn=1, maxconn=10)` trong order-service

## 🔧 PG-1: Connection Pool Internals

**Kiến thức:** Hiểu connection lifecycle, connection states, và cách pool hoạt động.
**Độ khó:** ⭐

### Break
```bash
# Xem connections hiện tại
docker exec postgres psql -U app -d orders -c "
  SELECT pid, state, query, client_addr, backend_start, state_change
  FROM pg_stat_activity
  WHERE datname = 'orders' AND usename = 'app';
"

# Kill tất cả connections (giả lập network blip)
docker exec postgres psql -U app -d orders -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE datname = 'orders' AND usename = 'app' AND pid <> pg_backend_pid();
"
```

### Test (inspect internals)

Ngay sau khi kill, chạy traffic nhẹ rồi quan sát:
```bash
# Chạy traffic để force reconnect
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 30}'

# Xem connections tái tạo
docker exec postgres psql -U app -d orders -c "
  SELECT pid, state, query_start, state_change,
         age(clock_timestamp(), backend_start) AS connection_age
  FROM pg_stat_activity
  WHERE datname = 'orders' AND usename = 'app';
"
```

**Đọc output:**
| Column | Ý nghĩa |
|--------|---------|
| `state` | `active` = đang query, `idle` = chờ trong pool, `idle in transaction` = transaction chưa commit |
| `connection_age` | Connection mới tạo sẽ có age rất nhỏ (vài giây) |
| `query_start` | Thời điểm query cuối bắt đầu |

```bash
# Đếm connections theo state
docker exec postgres psql -U app -d orders -c "
  SELECT state, count(*)
  FROM pg_stat_activity
  WHERE datname = 'orders' AND usename = 'app'
  GROUP BY state;
"
```

### Recovery
Order-service sử dụng `SimpleConnectionPool` — pool tự tạo connection mới khi cần. Verify:
```bash
# Chờ 10-20s sau khi traffic chạy, connections sẽ được recreate
docker exec postgres psql -U app -d orders -c "
  SELECT count(*) AS total_connections
  FROM pg_stat_activity
  WHERE datname = 'orders' AND usename = 'app';
"
# Kỳ vọng: 1-3 connections (idle in pool)
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Connection states:** `idle` vs `active` vs `idle in transaction` khác nhau thế nào? State nào nguy hiểm nếu kéo dài? (idle in transaction → giữ lock)
- [ ] **Pool behavior:** Sau khi kill tất cả connections, order-service có crash không? Nó recover thế nào? (pool tạo connection mới khi `getconn()` được gọi)
- [ ] **Production:** `max_connections` mặc định của PostgreSQL là bao nhiêu? Nếu có 5 services mỗi service pool max=10, tổng cần bao nhiêu connections? Có vượt default không?

---

## 🔧 PG-2: Dead Tuples & VACUUM

**Kiến thức:** Hiểu MVCC, dead tuples, table bloat, và tại sao VACUUM quan trọng.
**Độ khó:** ⭐⭐

### Break
```bash
# Tạo 5000 rows rồi delete hết → tạo dead tuples
docker exec postgres psql -U app -d orders -c "
  INSERT INTO orders (order_id, product_id, product_name, quantity, total_amount, status)
  SELECT
    'BT' || lpad(i::text, 6, '0'),
    (i % 5) + 1,
    'BTR Product ' || i,
    1,
    99.99,
    'test'
  FROM generate_series(1, 5000) AS i;
"

docker exec postgres psql -U app -d orders -c "
  DELETE FROM orders WHERE status = 'test';
"
```

### Test (inspect internals)
```bash
# Kiểm tra dead tuples
docker exec postgres psql -U app -d orders -c "
  SELECT relname, n_live_tup, n_dead_tup,
         CASE WHEN n_live_tup > 0
              THEN round(n_dead_tup::numeric / n_live_tup * 100, 1)
              ELSE 0 END AS dead_pct,
         last_vacuum, last_autovacuum,
         pg_size_pretty(pg_total_relation_size(relid)) AS total_size
  FROM pg_stat_user_tables
  WHERE relname IN ('orders', 'products');
"
```

**Đọc output:**
| Column | Ý nghĩa |
|--------|---------|
| `n_dead_tup` | Rows đã delete nhưng chưa được dọn → vẫn chiếm disk |
| `dead_pct` | % dead tuples so với live → > 20% là cần VACUUM |
| `last_autovacuum` | Lần cuối autovacuum chạy → NULL nếu chưa bao giờ |
| `total_size` | Size bao gồm cả dead tuples (bloat) |

```bash
# Xem table size chi tiết (trước vacuum)
docker exec postgres psql -U app -d orders -c "
  SELECT pg_size_pretty(pg_relation_size('orders')) AS table_size,
         pg_size_pretty(pg_indexes_size('orders')) AS index_size,
         pg_size_pretty(pg_total_relation_size('orders')) AS total_size;
"
```

### Recovery
```bash
# Chạy VACUUM VERBOSE để dọn dead tuples
docker exec postgres psql -U app -d orders -c "VACUUM VERBOSE orders;"

# Verify dead tuples đã giảm
docker exec postgres psql -U app -d orders -c "
  SELECT relname, n_live_tup, n_dead_tup, last_vacuum
  FROM pg_stat_user_tables WHERE relname = 'orders';
"
# Kỳ vọng: n_dead_tup ≈ 0, last_vacuum = vừa chạy

# VACUUM FULL để reclaim disk space (cần exclusive lock!)
# Chỉ chạy khi bloat lớn và có maintenance window
docker exec postgres psql -U app -d orders -c "VACUUM FULL orders;"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **MVCC:** Tại sao DELETE không xóa row ngay? (vì transactions khác có thể đang đọc row đó — MVCC giữ old version)
- [ ] **VACUUM vs VACUUM FULL:** VACUUM chỉ mark dead tuples as reusable. VACUUM FULL thực sự reclaim disk nhưng cần exclusive lock. Khi nào dùng cái nào?
- [ ] **Autovacuum:** Autovacuum trigger khi nào? (`autovacuum_vacuum_threshold` + `autovacuum_vacuum_scale_factor` × `n_live_tup`). Với bảng 1M rows, dead tuples cần bao nhiêu mới trigger?
- [ ] **Production:** Bảng `orders` tăng 100K rows/ngày, delete sau 90 ngày. Ước tính dead tuples nếu autovacuum bị disable?

---

## 🔧 PG-3: WAL & Checkpoint

**Kiến thức:** Hiểu Write-Ahead Log, checkpoint cycle, và tại sao WAL quan trọng cho durability.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Tạo write load để generate WAL
docker exec postgres psql -U app -d orders -c "
  INSERT INTO orders (order_id, product_id, product_name, quantity, total_amount, status)
  SELECT
    'WL' || lpad(i::text, 6, '0'),
    (i % 5) + 1,
    'WAL Test ' || i,
    1,
    49.99,
    'wal_test'
  FROM generate_series(1, 10000) AS i;
"
```

### Test (inspect internals)
```bash
# Xem WAL statistics
docker exec postgres psql -U app -d orders -c "SELECT * FROM pg_stat_wal;"

# Xem WAL directory size
docker exec postgres bash -c "du -sh /var/lib/postgresql/data/pg_wal/"

# List WAL files
docker exec postgres bash -c "ls -la /var/lib/postgresql/data/pg_wal/ | head -20"

# Xem checkpoint statistics
docker exec postgres psql -U app -d orders -c "SELECT * FROM pg_stat_bgwriter;"
```

**Đọc output:**
| Metric | Ý nghĩa |
|--------|---------|
| `wal_records` | Tổng WAL records đã ghi |
| `wal_bytes` | Tổng bytes WAL |
| `checkpoints_timed` | Checkpoints theo schedule (bình thường) |
| `checkpoints_req` | Checkpoints do WAL đầy (không tốt nếu nhiều) |

```bash
# Xem current WAL position
docker exec postgres psql -U app -d orders -c "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"

# Force một checkpoint
docker exec postgres psql -U app -d orders -c "CHECKPOINT;"

# So sánh checkpoints_timed vs checkpoints_req sau checkpoint
docker exec postgres psql -U app -d orders -c "
  SELECT checkpoints_timed, checkpoints_req,
         pg_size_pretty(buffers_checkpoint * 8192::bigint) AS checkpoint_data
  FROM pg_stat_bgwriter;
"
```

### Recovery
```bash
# Cleanup test data
docker exec postgres psql -U app -d orders -c "DELETE FROM orders WHERE status = 'wal_test';"
docker exec postgres psql -U app -d orders -c "VACUUM orders;"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **WAL purpose:** Tại sao cần ghi WAL trước khi ghi data file? (crash recovery — replay WAL để recover uncommitted changes)
- [ ] **Checkpoint:** Checkpoint làm gì? (flush dirty pages từ shared buffers ra disk, advance WAL recycle point). Tại sao checkpoint quá thường xuyên ảnh hưởng performance?
- [ ] **Production:** `max_wal_size` = 1GB (default). Nếu write load quá cao → WAL đầy trước checkpoint → forced checkpoint. Dấu hiệu trên `pg_stat_bgwriter`?

---

## 🔧 PG-4: Backup & Point-in-Time Recovery

**Kiến thức:** Backup strategies, restore flow, và tại sao backup không đủ — cần test restore.
**Độ khó:** ⭐⭐⭐

> ⚠️ **DESTRUCTIVE OPERATION:** Exercise này DROP TABLE. 
> **Chỉ chạy trên lab, KHÔNG chạy trên production.**
> Luôn tạo backup TRƯỚC KHI break (xem bước 1).

### Break
```bash
# Bước 1: Tạo backup TRƯỚC KHI phá
docker exec postgres pg_dump -U app -d orders > /tmp/orders_backup.sql
# Verify backup
wc -l /tmp/orders_backup.sql
grep "CREATE TABLE" /tmp/orders_backup.sql

# Bước 2: Ghi nhận state hiện tại
docker exec postgres psql -U app -d orders -c "SELECT count(*) AS order_count FROM orders;"
docker exec postgres psql -U app -d orders -c "SELECT count(*) AS product_count FROM products;"

# Bước 3: DROP TABLE (giả lập disaster)
docker exec postgres psql -U app -d orders -c "DROP TABLE orders CASCADE;"
```

### Test (inspect internals)
```bash
# Verify table đã mất
docker exec postgres psql -U app -d orders -c "\dt"
# orders sẽ không còn trong danh sách

# App sẽ báo lỗi nếu có traffic
docker logs order-service --tail 10 2>&1 | grep -i "error\|relation"
```

### Recovery
```bash
# Restore từ backup
docker exec -i postgres psql -U app -d orders < /tmp/orders_backup.sql

# Verify
docker exec postgres psql -U app -d orders -c "\dt"
docker exec postgres psql -U app -d orders -c "SELECT count(*) FROM orders;"
docker exec postgres psql -U app -d orders -c "SELECT count(*) FROM products;"

# Test app vẫn hoạt động
curl -s http://localhost:5001/health/live | head -5
```

### 🎯 Câu hỏi kiểm tra
- [ ] **pg_dump types:** `pg_dump` (logical, text SQL) vs `pg_basebackup` (physical, binary). Khi nào dùng cái nào?
- [ ] **Backup testing:** "Backup chưa test restore = không có backup". Bạn sẽ schedule restore test bao lâu một lần?
- [ ] **RPO/RTO:** Với `pg_dump` chạy mỗi đêm, RPO (Recovery Point Objective) tối đa là bao lâu? (24h — mất tối đa 1 ngày data). Cách giảm RPO?
- [ ] **Production:** WAL archiving + `pg_basebackup` cho phép PITR (Point-in-Time Recovery). Khi nào cần PITR thay vì restore full backup?

---

## 🔧 PG-5: Lock Monitoring

**Kiến thức:** Lock types, lock conflicts, deadlock detection.
**Độ khó:** ⭐⭐⭐

> ⚠️ **LONG-RUNNING LOCK:** Transaction A giữ lock 60 giây.
> Nếu có traffic đang chạy, requests sẽ timeout hoặc fail.
> **Production rule:** Luôn set `statement_timeout` để tránh lock vô hạn.
> ```sql
> SET statement_timeout = '30s';  -- Auto-kill query sau 30s
> ```

### Break
```bash
# Terminal 1: Transaction A — lock row
docker exec postgres psql -U app -d orders -c "
  BEGIN;
  UPDATE products SET stock = stock - 1 WHERE id = 1;
  SELECT pg_sleep(60);
  COMMIT;
" &

# Chờ 2s để transaction A bắt đầu
sleep 2

# Terminal 2: Transaction B — cố update cùng row → bị block
docker exec postgres psql -U app -d orders -c "
  UPDATE products SET stock = stock + 1 WHERE id = 1;
"
# Command này sẽ bị HANG cho đến khi Transaction A commit/rollback
```

### Test (inspect internals)
Mở terminal mới trong khi 2 transactions đang chạy:
```bash
# Xem locks hiện tại
docker exec postgres psql -U app -d orders -c "
  SELECT pid, locktype, relation::regclass, mode, granted, waitstart
  FROM pg_locks
  WHERE relation = 'products'::regclass;
"

# Xem ai đang block ai
docker exec postgres psql -U app -d orders -c "
  SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query
  FROM pg_stat_activity blocked
  JOIN pg_locks bl ON blocked.pid = bl.pid AND NOT bl.granted
  JOIN pg_locks gl ON bl.relation = gl.relation AND bl.locktype = gl.locktype AND gl.granted
  JOIN pg_stat_activity blocking ON gl.pid = blocking.pid
  WHERE blocked.pid <> blocking.pid;
"

# Hoặc dùng built-in function
docker exec postgres psql -U app -d orders -c "
  SELECT pid, pg_blocking_pids(pid) AS blocked_by, query
  FROM pg_stat_activity
  WHERE cardinality(pg_blocking_pids(pid)) > 0;
"
```

**Đọc output:**
| Column | Ý nghĩa |
|--------|---------|
| `granted = false` | Lock đang chờ (bị block) |
| `mode` | `RowExclusiveLock` (UPDATE), `AccessExclusiveLock` (ALTER TABLE, LOCK TABLE) |
| `pg_blocking_pids()` | PIDs đang block process này |

### Recovery
```bash
# Kill blocking transaction (Transaction A)
docker exec postgres psql -U app -d orders -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'active' AND query LIKE '%pg_sleep%';
"
# Transaction B sẽ tự unblock và complete

# Verify stock đúng
docker exec postgres psql -U app -d orders -c "SELECT id, name, stock FROM products WHERE id = 1;"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Lock types:** `RowExclusiveLock` vs `AccessExclusiveLock` — cái nào block reads? (AccessExclusive block tất cả, RowExclusive chỉ block concurrent writes trên cùng row)
- [ ] **Deadlock:** Nếu Transaction A lock row 1 rồi cố lock row 2, Transaction B lock row 2 rồi cố lock row 1 → gì xảy ra? (PostgreSQL detect deadlock sau `deadlock_timeout`, kill 1 transaction)
- [ ] **Production:** Query chạy 30 phút giữ lock → bạn kill nó hay chờ? Cách tìm long-running queries? (`SELECT pid, age(clock_timestamp(), query_start), query FROM pg_stat_activity WHERE state = 'active'`)

---

## 🔧 PG-6: Query Analysis (EXPLAIN ANALYZE)

**Kiến thức:** Query planner, seq scan vs index scan, cost model.
**Độ khó:** ⭐⭐

### Break
```bash
# Query không có index — sẽ seq scan
docker exec postgres psql -U app -d orders -c "
  EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
  SELECT * FROM orders WHERE status = 'completed';
"
```

### Test (inspect internals)
```bash
# Đọc output EXPLAIN ANALYZE
# Tìm: Seq Scan → đọc toàn bộ bảng
# actual time, rows, loops

# Kiểm tra indexes hiện có
docker exec postgres psql -U app -d orders -c "\di+ orders"

# Xem table statistics
docker exec postgres psql -U app -d orders -c "
  SELECT attname, n_distinct, most_common_vals
  FROM pg_stats
  WHERE tablename = 'orders' AND attname = 'status';
"
```

**Đọc EXPLAIN output:**
| Phần | Ý nghĩa |
|------|---------|
| `Seq Scan` | Đọc toàn bộ bảng — chậm khi bảng lớn |
| `Index Scan` | Dùng index — nhanh hơn nhiều |
| `actual time=X..Y` | X = thời gian first row, Y = thời gian all rows (ms) |
| `rows=N` | Số rows thực tế trả về |
| `Buffers: shared hit=N` | Pages đọc từ cache |
| `Buffers: shared read=N` | Pages đọc từ disk |

### Recovery
```bash
# Tạo index trên column status
docker exec postgres psql -U app -d orders -c "
  CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);
"

# Chạy lại query → verify dùng Index Scan
docker exec postgres psql -U app -d orders -c "
  EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
  SELECT * FROM orders WHERE status = 'completed';
"

# So sánh actual time trước/sau
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Cost model:** `cost=0.00..35.50` nghĩa là gì? Đơn vị là gì? (arbitrary units — dùng để so sánh plans, không phải ms)
- [ ] **CREATE INDEX CONCURRENTLY:** Tại sao dùng `CONCURRENTLY`? (không lock table khi tạo index — production safe). Khi nào KHÔNG dùng `CONCURRENTLY`?
- [ ] **Production:** Bảng `orders` có 10M rows. Query `SELECT * FROM orders WHERE created_at > '2026-01-01'` trả về 1M rows. Index có giúp không? (không — trả về 10% bảng, planner chọn seq scan vì nhanh hơn random I/O)

---

# Part 2: Kafka Deep Dive

> **VM:** applications-vm
> **Access:** `docker exec -it kafka bash` → dùng Kafka CLI tools
> **Topic:** `order.events` (1 partition)
> **Consumer groups:** `notification-workers`, `inventory-workers`

## 🔧 KF-1: Offset Management

**Kiến thức:** Consumer offsets, committed offset vs log-end offset, offset reset.
**Độ khó:** ⭐⭐

### Break
```bash
# Xem current offsets
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers
```

**Đọc output:**
| Column | Ý nghĩa |
|--------|---------|
| `CURRENT-OFFSET` | Offset cuối cùng consumer đã commit |
| `LOG-END-OFFSET` | Offset mới nhất trong partition |
| `LAG` | LOG-END - CURRENT = messages chưa xử lý |

```bash
# Reset offset to earliest (consumer phải stop trước)
docker stop notification-worker

docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group notification-workers \
  --topic order.events \
  --reset-offsets --to-earliest --execute
```

### Test (inspect internals)

> ⚠️ **RESET OFFSET TO EARLIEST** sẽ khiến consumer reprocess TẤT CẢ messages.
> Nếu notification-worker gửi email cho mỗi order → users nhận duplicate email.
> **Production rule:** Chỉ reset offset khi bạn đã implement idempotent consumer 
> (check processed_events table trước khi process).

```bash
# Verify offset đã reset
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers

# Start lại consumer → nó sẽ reprocess TẤT CẢ messages
docker start notification-worker

# Quan sát logs — sẽ thấy reprocess old messages
docker logs notification-worker --tail 20
```

### Recovery
```bash
# Consumer sẽ tự catch up. Verify lag về 0:
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Idempotency:** Sau reset offset, consumer reprocess tất cả messages. Nếu notification-worker gửi email cho mỗi order → users nhận duplicate email. Cách xử lý? (idempotent consumer — check processed ID trước khi send)
- [ ] **Offset storage:** Offsets lưu ở đâu? (`__consumer_offsets` topic trong Kafka). Nếu Kafka restart, offsets có mất không?
- [ ] **Production:** Consumer bị bug xử lý sai 1000 messages. Bạn cần reprocess từ offset 5000 → 6000. Lệnh gì? (`--reset-offsets --to-offset 5000`)

---

## 🔧 KF-2: Log Segments on Disk

**Kiến thức:** Kafka lưu data thế nào trên disk — segments, indexes, retention.
**Độ khó:** ⭐⭐

### Break
```bash
# Tạo thêm messages để có data
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 5, "duration": 30}'
```

### Test (inspect internals)
```bash
# Xem data directory
docker exec kafka ls -la /var/lib/kafka/data/

# Xem partition directory
docker exec kafka ls -la /var/lib/kafka/data/order.events-0/

# Xem file types
docker exec kafka bash -c "ls -lh /var/lib/kafka/data/order.events-0/*.log"
docker exec kafka bash -c "ls -lh /var/lib/kafka/data/order.events-0/*.index"
docker exec kafka bash -c "ls -lh /var/lib/kafka/data/order.events-0/*.timeindex"
```

**Đọc output:**
| File | Ý nghĩa |
|------|---------|
| `00000000000000000000.log` | Data file — chứa messages thực tế |
| `*.index` | Offset index — map offset → position trong .log |
| `*.timeindex` | Timestamp index — map timestamp → offset |

```bash
# Xem topic config (retention, cleanup policy)
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events --describe

# Xem tổng size
docker exec kafka du -sh /var/lib/kafka/data/order.events-0/
```

### Recovery
Không cần recovery — exercise này chỉ inspect.

### 🎯 Câu hỏi kiểm tra
- [ ] **Segment rolling:** Segment mới tạo khi nào? (`segment.bytes` = 1GB hoặc `segment.ms` = 7 days, cái nào đến trước)
- [ ] **Retention:** `retention.ms` = 168h (7 days default). Messages cũ hơn 7 ngày sẽ bị xóa. Có recover được không?
- [ ] **Production:** Topic `order.events` chứa 10GB/ngày. Retention 30 ngày. Cần bao nhiêu disk? (300GB + overhead)

---

## 🔧 KF-3: Producer Delivery Semantics

**Kiến thức:** acks config, retries, delivery guarantees.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Chạy traffic
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 60}'

# Giữa chừng, restart Kafka
sleep 10
docker restart kafka
```

### Test (inspect internals)
```bash
# Xem order-service logs — có delivery failure không?
docker logs order-service --tail 30 2>&1 | grep -i "kafka\|produce\|deliver"

# Xem producer config trong code
grep -n "acks\|retries\|delivery" /root/workspace/observability-sample-v2/on-premises/applications-vm/applications/order-service/app.py
```

### Recovery
```bash
# Kafka sẽ tự start. Verify:
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list

# Verify producer reconnected
docker logs order-service --tail 10 2>&1 | grep -i "kafka"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **acks config:** `acks=0` (fire-and-forget), `acks=1` (leader ack), `acks=all` (all replicas ack). Trade-off giữa performance và durability?
- [ ] **Retries:** Producer có retry khi Kafka restart không? Nếu có, có risk duplicate messages không?
- [ ] **Production:** Order service produce message nhưng Kafka down 30 giây. Message mất hay retry thành công? Phụ thuộc config gì?

---

## 🔧 KF-4: Consumer Rebalance

**Kiến thức:** Partition assignment, rebalance protocol, consumer group coordination.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Xem current assignment
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers

# Stop consumer → trigger rebalance (nếu có 2+ consumers)
docker stop notification-worker
```

### Test (inspect internals)
```bash
# Xem consumer group state
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers --state

# List all consumer groups
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list

# Xem members
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers --members
```

**Group states:**
| State | Ý nghĩa |
|-------|---------|
| `Stable` | All members assigned, đang consume bình thường |
| `PreparingRebalance` | Đang chờ members join trước khi assign |
| `CompletingRebalance` | Đang assign partitions |
| `Empty` | Không có member nào (consumer down) |
| `Dead` | Group bị xóa |

### Recovery
```bash
docker start notification-worker

# Verify group trở về Stable
sleep 10
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-workers --state
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Rebalance cost:** Trong khi rebalance, consumer KHÔNG đọc messages. Rebalance mất bao lâu? (seconds to minutes tùy config)
- [ ] **Single partition:** Topic `order.events` chỉ có 1 partition. Nếu add 2nd consumer vào group → nó có nhận partition không? (KHÔNG — 1 partition chỉ assign cho 1 consumer)
- [ ] **Production:** Rebalance storm — consumer liên tục join/leave gây rebalance liên tục. Nguyên nhân phổ biến? (OOM, GC pauses, network flap)

---

## 🔧 KF-5: Topic Configuration

**Kiến thức:** Dynamic topic configs, retention, cleanup policies.
**Độ khó:** ⭐⭐

### Break
```bash
# Xem config hiện tại
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events --describe

# Thay đổi retention thành 1 phút (ngắn bất thường)
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events \
  --alter --add-config retention.ms=60000
```

### Test (inspect internals)
```bash
# Verify config đã thay đổi
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events --describe

# Chờ 1-2 phút → log cleaner sẽ xóa old segments
docker exec kafka ls -la /var/lib/kafka/data/order.events-0/
```

### Recovery
```bash
# Restore retention về 7 ngày
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events \
  --alter --delete-config retention.ms

# Verify config removed (sẽ dùng broker default)
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name order.events --describe
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Dynamic vs static:** Config nào thay đổi được runtime (topic-level)? Config nào cần restart broker (broker-level)?
- [ ] **Cleanup policies:** `delete` (xóa old segments) vs `compact` (giữ latest value per key). Khi nào dùng compaction? (changelog topics, state stores)
- [ ] **Production:** Ai có quyền thay đổi topic config? Cần audit log không? (YES — retention thay đổi sai = data loss)

---

# Part 3: Redis Deep Dive

> **VM:** applications-vm
> **Access:** `docker exec -it redis redis-cli`
> **Usage:** Cache-aside cho product catalog, TTL=60s, key: `product:catalog`

## 🔧 RD-1: Memory & Eviction

**Kiến thức:** maxmemory policy, eviction algorithms, memory management.
**Độ khó:** ⭐⭐

### Break
```bash
# Xem memory hiện tại
docker exec redis redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human|maxmemory_policy"

# Set maxmemory rất thấp
docker exec redis redis-cli CONFIG SET maxmemory 1mb

# Fill memory với dummy keys
for i in $(seq 1 5000); do
  docker exec redis redis-cli SET "dummy:$i" "$(head -c 200 /dev/urandom | base64)" EX 300 > /dev/null
done
```

### Test (inspect internals)
```bash
# Xem memory sau khi fill
docker exec redis redis-cli INFO memory | grep -E "used_memory_human|maxmemory|evicted_keys"

# Xem eviction policy
docker exec redis redis-cli CONFIG GET maxmemory-policy

# Kiểm tra key count
docker exec redis redis-cli DBSIZE

# Xem product catalog cache bị evict chưa
docker exec redis redis-cli EXISTS "product:catalog"
```

**Eviction policies:**
| Policy | Ý nghĩa |
|--------|---------|
| `noeviction` | Trả error khi memory đầy (default) |
| `allkeys-lru` | Evict least recently used key (phổ biến nhất) |
| `volatile-lru` | Evict LRU key có TTL |
| `allkeys-random` | Random evict |

> ⚠️ **FLUSHALL xóa TẤT CẢ data trong Redis**, bao gồm cả `product:catalog` cache.
> Sau khi chạy FLUSHALL, app sẽ có cache-miss storm → P95 tăng tạm thời.
> Đây là expected behavior — cache sẽ tự warm lại khi có traffic.

### Recovery
```bash
# Xóa dummy keys
docker exec redis redis-cli KEYS "dummy:*" | head -100
docker exec redis redis-cli --scan --pattern "dummy:*" | xargs docker exec -i redis redis-cli DEL

# Hoặc FLUSHALL (xóa tất cả)
docker exec redis redis-cli FLUSHALL

# Restore maxmemory
docker exec redis redis-cli CONFIG SET maxmemory 0
# 0 = unlimited (dùng hết RAM available)

# Verify
docker exec redis redis-cli INFO memory | grep -E "used_memory_human|evicted_keys"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Eviction impact:** Nếu `product:catalog` bị evict → next request phải query DB → P95 tăng. Đây là cache-miss storm giống Experiment 11 trong IS guide.
- [ ] **Policy choice:** Production cache server nên dùng policy nào? (`allkeys-lru` — auto evict least used, tránh OOM)
- [ ] **Production:** Redis 4GB maxmemory, key trung bình 1KB. Tối đa bao nhiêu keys? (~4M, nhưng thực tế ít hơn do Redis overhead per key ~100 bytes)

---

## 🔧 RD-2: Persistence (RDB/AOF)

**Kiến thức:** RDB snapshots vs AOF, data durability, startup recovery.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Kiểm tra persistence config hiện tại
docker exec redis redis-cli CONFIG GET save
docker exec redis redis-cli CONFIG GET appendonly

# Set một key quan trọng
docker exec redis redis-cli SET "important:data" "critical-value-123"
docker exec redis redis-cli SET "important:counter" "42"

# Verify
docker exec redis redis-cli GET "important:data"

# Kill Redis -9 (không graceful shutdown → không save RDB)
docker kill redis
```

### Test (inspect internals)
```bash
# Start lại Redis
docker start redis

# Kiểm tra data còn không
docker exec redis redis-cli GET "important:data"
docker exec redis redis-cli GET "important:counter"

# Xem persistence info
docker exec redis redis-cli INFO persistence | grep -E "rdb_|aof_|loading"
```

**Đọc output:**
| Metric | Ý nghĩa |
|--------|---------|
| `rdb_last_save_time` | Timestamp RDB snapshot cuối |
| `rdb_changes_since_last_save` | Changes chưa persist |
| `aof_enabled` | AOF có bật không |

### Recovery
```bash
# Nếu data mất → cần recreate (app sẽ cache-miss rồi tự populate)
# Chạy traffic để warm cache
curl -X POST http://localhost:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 10}'

# Verify cache populated
docker exec redis redis-cli EXISTS "product:catalog"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **RDB vs AOF:** RDB = periodic snapshots (fast recovery, potential data loss). AOF = append every write (durable, slower recovery). Trade-off?
- [ ] **Data loss window:** `save 900 1` → RDB snapshot mỗi 15 phút nếu có ≥1 change. Worst case data loss = 15 phút. Có acceptable cho cache không? (YES — cache có thể rebuild từ DB)
- [ ] **Production:** Session store dùng Redis (user login sessions). Cần RDB, AOF, hay cả hai? (AOF — session loss = user bị logout = bad UX)

---

## 🔧 RD-3: Key Analysis

**Kiến thức:** Key patterns, memory per key, encoding types, TTL management.
**Độ khó:** ⭐

### Break
Không cần break — exercise này inspect state hiện tại.

### Test (inspect internals)
```bash
# Scan tất cả keys (KHÔNG dùng KEYS * trong production!)
docker exec redis redis-cli --scan --pattern "*"

# Xem type và encoding
docker exec redis redis-cli TYPE "product:catalog"
docker exec redis redis-cli OBJECT ENCODING "product:catalog"
docker exec redis redis-cli OBJECT IDLETIME "product:catalog"

# Memory usage per key
docker exec redis redis-cli MEMORY USAGE "product:catalog"

# TTL
docker exec redis redis-cli TTL "product:catalog"
docker exec redis redis-cli PTTL "product:catalog"

# Debug object (chi tiết hơn)
docker exec redis redis-cli DEBUG OBJECT "product:catalog" 2>/dev/null || echo "DEBUG OBJECT disabled"
```

**Encoding types:**
| Encoding | Ý nghĩa | Memory efficiency |
|----------|---------|-------------------|
| `embstr` | Short string (≤44 bytes) | Tốt nhất |
| `raw` | Long string | Bình thường |
| `ziplist` | Small hash/list | Compact |
| `hashtable` | Large hash | Nhiều memory hơn |
| `listpack` | Redis 7+ small collections | Compact |

### Recovery
Không cần — exercise này chỉ inspect.

### 🎯 Câu hỏi kiểm tra
- [ ] **SCAN vs KEYS:** Tại sao KHÔNG bao giờ dùng `KEYS *` trong production? (block Redis — single threaded, O(N))
- [ ] **Memory optimization:** Key `product:catalog` dùng bao nhiêu bytes? Nếu cache 10K products thay vì catalog → memory thay đổi thế nào?
- [ ] **Production:** Redis memory tăng bất thường. Cách tìm big keys? (`redis-cli --bigkeys` hoặc `SCAN` + `MEMORY USAGE`)

---

## 🔧 RD-4: Slowlog

**Kiến thức:** Redis single-threaded model, O(N) commands, pipeline optimization.
**Độ khó:** ⭐⭐

### Break
```bash
# Tạo nhiều keys
for i in $(seq 1 3000); do
  docker exec redis redis-cli SET "slow:$i" "value$i" > /dev/null
done

# Chạy O(N) command — KEYS * sẽ scan tất cả keys
docker exec redis redis-cli KEYS "*"

# Set slowlog threshold thấp để bắt được
docker exec redis redis-cli CONFIG SET slowlog-log-slower-than 1000
# 1000 microseconds = 1ms
```

### Test (inspect internals)
```bash
# Xem slowlog
docker exec redis redis-cli SLOWLOG GET 10

# Đọc: ID, timestamp, duration (microseconds), command
docker exec redis redis-cli SLOWLOG LEN
```

**Đọc output:**
```
1) 1) (integer) 0          # ID
   2) (integer) 1716123456 # Timestamp
   3) (integer) 15234      # Duration: 15ms — SLOW!
   4) 1) "KEYS"            # Command
      2) "*"
```

### Recovery
```bash
# Cleanup
docker exec redis redis-cli --scan --pattern "slow:*" | xargs docker exec -i redis redis-cli DEL

# Reset slowlog threshold
docker exec redis redis-cli CONFIG SET slowlog-log-slower-than 10000

# Clear slowlog
docker exec redis redis-cli SLOWLOG RESET
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Single threaded:** Redis single-threaded. `KEYS *` mất 15ms = TẤT CẢ clients bị block 15ms. Với 1000 req/s, bao nhiêu requests bị ảnh hưởng?
- [ ] **Alternatives:** Thay `KEYS *` bằng gì? (`SCAN` — iterative, non-blocking). Thay `SORT` bằng gì? (sort ở application layer)
- [ ] **Production:** Slowlog thấy command `HGETALL` mất 50ms trên hash có 100K fields. Giải pháp? (chia nhỏ hash, hoặc dùng `HSCAN`)

---

# Part 4: Prometheus Deep Dive

> **VM:** observability-vm
> **Access:** `docker exec -it prometheus sh` hoặc HTTP API `http://localhost:9090`
> **Config:** [prometheus.yml](observability-vm/phase1-metrics/prometheus/prometheus.yml)
> **Dashboard:** `prometheus-self`

## 🔧 PM-1: TSDB & WAL

**Kiến thức:** Prometheus storage model — WAL, head block, compacted blocks.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Xem storage directory structure
docker exec prometheus ls -la /prometheus/

# Kill Prometheus (giả lập crash)
docker kill prometheus
```

### Test (inspect internals)
```bash
# Xem WAL directory TRƯỚC khi start lại
docker exec prometheus ls -la /prometheus/wal/ 2>/dev/null || echo "Container stopped"

# Start lại → Prometheus replay WAL
docker start prometheus

# Xem logs — tìm WAL replay time
docker logs prometheus --tail 30 2>&1 | grep -i "wal\|replay\|ready"

# Xem TSDB stats qua API
curl -s http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool | head -40
```

**Storage structure:**
```
/prometheus/
├── wal/           ← Write-Ahead Log (uncommitted data)
├── chunks_head/   ← Current head block (in-memory + mmap)
├── 01HXYZ.../     ← Compacted block (2h of data)
│   ├── chunks/    ← Compressed time series data
│   ├── index      ← Inverted index (label → series)
│   └── meta.json  ← Block metadata
└── lock           ← Process lock file
```

### Recovery
```bash
# Verify Prometheus healthy
curl -s http://localhost:9090/-/healthy
# Kỳ vọng: Prometheus Server is Healthy.

# Verify metrics không bị gap lớn (có thể mất 1-2 scrape intervals)
# Mở Grafana → prometheus-self dashboard → check uptime
```

### 🎯 Câu hỏi kiểm tra
- [ ] **WAL replay:** Prometheus crash → restart → replay WAL. Mất data trong bao lâu? (tối đa 2 phút — dữ liệu trong head block chưa persist)
- [ ] **Block lifecycle:** Head block → compacted block sau bao lâu? (2 giờ default `--storage.tsdb.min-block-duration`)
- [ ] **Production:** Prometheus OOM killed → restart → WAL replay mất 10 phút (WAL quá lớn). Cách giảm WAL size? (giảm scrape interval, giảm cardinality)

---

## 🔧 PM-2: Cardinality Analysis

**Kiến thức:** Series cardinality, label design, OOM risk từ high cardinality.
**Độ khó:** ⭐⭐⭐

### Break
Không inject — inspect hiện trạng cardinality của hệ thống.

### Test (inspect internals)
```bash
# Tổng số series
curl -s http://localhost:9090/api/v1/status/tsdb | python3 -c "
import sys,json
data = json.load(sys.stdin)
stats = data['data']
print(f\"Total series: {stats.get('numSeries', 'N/A')}\")
print(f\"Total label pairs: {stats.get('numLabelPairs', 'N/A')}\")
"

# Top metrics by series count
curl -s http://localhost:9090/api/v1/status/tsdb | python3 -c "
import sys,json
data = json.load(sys.stdin)
for item in data['data'].get('seriesCountByMetricName', [])[:15]:
    print(f\"{item['value']:>8}  {item['name']}\")
"

# Top labels by value count
curl -s http://localhost:9090/api/v1/status/tsdb | python3 -c "
import sys,json
data = json.load(sys.stdin)
for item in data['data'].get('labelValueCountByLabelName', [])[:10]:
    print(f\"{item['value']:>8}  {item['name']}\")
"
```

### Recovery
Không cần — exercise này chỉ analyze.

### 🎯 Câu hỏi kiểm tra
- [ ] **Cardinality formula:** Metric `http_requests_total{method, status, path}`. Nếu method=5, status=10, path=100 → cardinality = 5×10×100 = 5000 series. Nếu thêm `user_id` (10K users) → 50M series → OOM.
- [ ] **Label design:** Tại sao `user_id` KHÔNG nên là label? (high cardinality). Dùng gì thay thế? (log/trace, không phải metric)
- [ ] **Production:** Prometheus memory tăng 2x sau deploy mới. Cách debug? (check TSDB status → top metrics → tìm metric mới có high cardinality)

---

## 🔧 PM-3: Retention & Storage

**Kiến thức:** Block storage, retention config, disk capacity planning.
**Độ khó:** ⭐⭐

### Break
Không inject — inspect storage.

### Test (inspect internals)
```bash
# Disk usage
docker exec prometheus du -sh /prometheus/
docker exec prometheus du -sh /prometheus/wal/

# List blocks with timestamps
docker exec prometheus ls -la /prometheus/ | grep -E "^d"

# Xem retention config
docker inspect prometheus --format='{{.Args}}' | tr ',' '\n' | grep retention

# Xem block metadata
docker exec prometheus sh -c "cat /prometheus/*/meta.json 2>/dev/null | head -60"
```

### Recovery
Không cần.

### 🎯 Câu hỏi kiểm tra
- [ ] **Retention:** Default `--storage.tsdb.retention.time=15d`. Sau 15 ngày, data bị xóa tự động. Có recover được không? (KHÔNG — cần remote storage cho long-term)
- [ ] **Capacity planning:** 10K series × 15s interval × 15 days. Ước tính disk? (~1-2 bytes/sample × 10K × 4/min × 60 × 24 × 15 ≈ 1.3GB)
- [ ] **Production:** Disk 80% → Prometheus sẽ gì? (continue until disk full → crash → data loss). Cách phòng tránh? (alert `DiskWillFillIn4Hours`, giảm retention hoặc tăng disk)

---

## 🔧 PM-4: Scrape & Target Health

**Kiến thức:** Scrape lifecycle, up metric, target states, staleness.
**Độ khó:** ⭐⭐

### Break
```bash
# Stop 1 scrape target (node-exporter trên observability VM)
docker stop node-exporter
```

### Test (inspect internals)
```bash
# Xem target status qua API
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys,json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{t['health']:>6}  {t['labels'].get('job','?'):>20}  {t['lastError'][:60] if t['lastError'] else 'OK'}\")
"

# Query up metric
curl -s "http://localhost:9090/api/v1/query?query=up" | python3 -c "
import sys,json
data = json.load(sys.stdin)
for r in data['data']['result']:
    print(f\"up={r['value'][1]}  job={r['metric'].get('job','?')}  instance={r['metric'].get('instance','?')}\")
"
```

**Target states:**
| State | Ý nghĩa |
|-------|---------|
| `up` | Scrape thành công, `up=1` |
| `down` | Scrape failed, `up=0` |
| `unknown` | Chưa scrape lần nào |

### Recovery
```bash
docker start node-exporter

# Verify target healthy
sleep 20
curl -s "http://localhost:9090/api/v1/query?query=up{job='node-exporter'}" | python3 -c "
import sys,json
data = json.load(sys.stdin)
for r in data['data']['result']:
    print(f\"up={r['value'][1]}\")
"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Staleness:** Target down → Prometheus giữ last value bao lâu trước khi coi là stale? (5 phút default — `lookback_delta`)
- [ ] **up metric:** `up == 0` chỉ có nghĩa Prometheus không scrape được. Target có thể healthy nhưng firewall block. Cách verify? (curl trực tiếp từ Prometheus container)
- [ ] **Production:** 1 trong 50 targets intermittent down (flapping). Alert `TargetDown` cứ fire rồi resolve. Cách xử lý? (`for: 5m` trong alert rule, hoặc investigate network)

---

# Part 5: Loki Deep Dive

> **VM:** observability-vm
> **Access:** HTTP API `http://localhost:3100`
> **Config:** [loki-config.yml](observability-vm/phase2-logging/loki/loki-config.yml)
> **Storage:** MinIO (S3-compatible), bucket `loki`

## 🔧 LK-1: Label Cardinality

**Kiến thức:** Loki label design, index size, query performance impact.
**Độ khó:** ⭐⭐⭐

### Break
Không inject — analyze label cardinality hiện tại.

### Test (inspect internals)
```bash
# List all labels
curl -s http://localhost:3100/loki/api/v1/labels | python3 -m json.tool

# Xem values cho từng label
curl -s http://localhost:3100/loki/api/v1/label/container/values | python3 -m json.tool
curl -s http://localhost:3100/loki/api/v1/label/job/values | python3 -m json.tool

# Đếm series (unique label combinations)
curl -s "http://localhost:3100/loki/api/v1/series" --data-urlencode 'match={job=~".+"}' | python3 -c "
import sys,json
data = json.load(sys.stdin)
print(f\"Total streams: {len(data['data'])}\")
for s in data['data'][:10]:
    print(f\"  {s}\")
"
```

### Recovery
Không cần.

### 🎯 Câu hỏi kiểm tra
- [ ] **Labels vs line content:** Loki index by labels, KHÔNG index log content. Tại sao `{container="order-service"} |= "error"` nhanh hơn `{job=~".+"} |= "error"`? (filter label trước → ít streams cần scan)
- [ ] **Cardinality rule:** KHÔNG dùng high-cardinality labels (request_id, user_id, trace_id). Dùng `|=` line filter thay thế. Tại sao?
- [ ] **Production:** Loki query mất 30 giây. Cách optimize? (thêm label filter, dùng line filter `|=` trước `| json`, giảm time range)

---

## 🔧 LK-2: LogQL Performance

**Kiến thức:** LogQL execution order, filter optimization, bloom filters.
**Độ khó:** ⭐⭐

### Break
So sánh slow query vs fast query:

### Test (inspect internals)
```bash
# FAST: label filter first, then line filter
time curl -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={container="order-service"} |= "error"' \
  --data-urlencode 'start=1716300000000000000' \
  --data-urlencode 'end=1716400000000000000' \
  --data-urlencode 'limit=10' > /dev/null

# SLOW: regex parse on all streams
time curl -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job=~".+"} | json | level="error"' \
  --data-urlencode 'start=1716300000000000000' \
  --data-urlencode 'end=1716400000000000000' \
  --data-urlencode 'limit=10' > /dev/null
```

**LogQL execution order:**
```
{label filter} → line filter (|=) → parser (| json) → label filter (| level="error")
                 ↑ cheapest                                        ↑ most expensive
```

### Recovery
Không cần.

### 🎯 Câu hỏi kiểm tra
- [ ] **Execution order:** Tại sao `|= "error" | json` nhanh hơn `| json | level="error"`? (line filter `|=` là string match đơn giản, loại bỏ 90% lines TRƯỚC khi parse JSON)
- [ ] **Production:** Grafana Explore panel cho phép chọn labels trước khi query. Tại sao Loki team khuyến khích flow này thay vì free-text search?

---

## 🔧 LK-3: Storage & Retention

**Kiến thức:** Loki chunk storage, MinIO backend, retention configuration.
**Độ khó:** ⭐⭐

### Break
Không inject — inspect storage.

### Test (inspect internals)
```bash
# Xem MinIO bucket (nếu mc CLI available)
docker exec minio mc ls local/loki/ 2>/dev/null || \
  curl -s "http://localhost:9000/minio/health/live" && echo "MinIO healthy"

# Xem Loki metrics
curl -s http://localhost:3100/metrics | grep -E "loki_ingester_chunks|loki_store"  | head -20

# Xem Loki build info và config
curl -s http://localhost:3100/config | head -50
```

### Recovery
Không cần.

### 🎯 Câu hỏi kiểm tra
- [ ] **Chunk lifecycle:** Log line → ingester (in-memory) → chunk (compressed) → MinIO (S3). Chunk flush khi nào? (`chunk_idle_period`, `max_chunk_age`)
- [ ] **Retention:** Loki retention config nằm ở đâu? (compactor section trong loki-config.yml). Khác gì MinIO lifecycle policy?
- [ ] **Production:** 50 containers × 100 lines/s × 200 bytes/line = 1MB/s = 86GB/day. Retention 30 ngày = 2.6TB. MinIO disk planning?

---

# Part 6: Alertmanager Deep Dive

> **VM:** observability-vm
> **Access:** HTTP API `http://localhost:9093` hoặc `amtool` CLI
> **Config:** [alertmanager.yml](observability-vm/phase1-metrics/alertmanager/alertmanager.yml)

## 🔧 AM-1: Routing Tree

**Kiến thức:** Route matching, group_by, continue flag, receiver selection.
**Độ khó:** ⭐⭐

### Break
```bash
# Gửi test alert với severity=critical
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestCritical", "severity": "critical", "instance": "test:1234"},
    "annotations": {"summary": "BTR test alert - critical"},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)'"
  }]'

# Gửi test alert với severity=warning
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestWarning", "severity": "warning", "instance": "test:5678"},
    "annotations": {"summary": "BTR test alert - warning"},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)'"
  }]'
```

### Test (inspect internals)
```bash
# Xem active alerts
curl -s http://localhost:9093/api/v2/alerts | python3 -c "
import sys,json
data = json.load(sys.stdin)
for a in data:
    labels = a['labels']
    print(f\"{labels.get('severity','?'):>10}  {labels.get('alertname','?'):>20}  receivers={[r['name'] for r in a.get('receivers', [])]}\")
"

# Xem routing tree status
curl -s http://localhost:9093/api/v2/status | python3 -c "
import sys,json
data = json.load(sys.stdin)
print('Config:')
print(json.dumps(data.get('config', {}), indent=2)[:500])
"
```

**Routing logic trong config hiện tại:**
```
route (default → telegram-alerts)
├── alertname=Watchdog → webhook-alerts (continue: false) ← stop here
├── severity=critical → telegram-alerts (continue: true) ← send + continue
├── severity=warning → telegram-alerts (continue: true) ← send + continue
└── severity=.+ → webhook-alerts (continue: false) ← catch-all
```

### Recovery
```bash
# Alerts tự expire sau endsAt (5 phút). Hoặc resolve ngay:
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestCritical", "severity": "critical", "instance": "test:1234"},
    "endsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }]'
```

### 🎯 Câu hỏi kiểm tra
- [ ] **continue flag:** `continue: true` nghĩa là gì? (match route này VÀ tiếp tục check routes sau). Nếu `continue: false`? (stop, không check tiếp)
- [ ] **group_by:** `group_by: ["alertname", "severity"]` — alerts cùng alertname+severity được gộp thành 1 notification. Tại sao? (tránh spam khi 10 instances cùng fire)
- [ ] **Production:** Alert critical gửi Telegram nhưng team không thấy (channel quá nhiều messages). Giải pháp? (tạo channel riêng cho critical, hoặc dùng PagerDuty phone call)

---

## 🔧 AM-2: Silence & Inhibition

**Kiến thức:** Silence alerts tạm thời, inhibition rules tự động suppress.
**Độ khó:** ⭐⭐

### Break
```bash
# Tạo silence cho TestWarning (silence 30 phút)
SILENCE_ID=$(curl -s -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "TestWarning", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "btr-exercise",
    "comment": "BTR exercise - testing silence"
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['silenceID'])")
echo "Silence ID: $SILENCE_ID"
```

### Test (inspect internals)
```bash
# List active silences
curl -s http://localhost:9093/api/v2/silences | python3 -c "
import sys,json
data = json.load(sys.stdin)
for s in data:
    if s['status']['state'] == 'active':
        print(f\"ID: {s['id'][:8]}  Comment: {s['comment']}  Matchers: {s['matchers']}\")
"

# Gửi alert TestWarning → sẽ bị silence (không gửi notification)
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestWarning", "severity": "warning"},
    "annotations": {"summary": "This should be silenced"},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)'"
  }]'

# Verify alert bị silenced
curl -s http://localhost:9093/api/v2/alerts | python3 -c "
import sys,json
for a in json.load(sys.stdin):
    if a['labels']['alertname'] == 'TestWarning':
        print(f\"Status: {a['status']}\")
"
```

### Recovery
```bash
# Expire silence
curl -X DELETE "http://localhost:9093/api/v2/silence/$SILENCE_ID"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Silence vs Inhibition:** Silence = manual, temporary mute. Inhibition = automatic rule (critical suppresses warning trên cùng instance). Khi nào dùng cái nào?
- [ ] **Danger of silence:** Silence quên expire → alert thật bị nuốt. Best practice? (always set short duration, add comment with reason)
- [ ] **Production:** Đang maintenance Kafka cluster, biết sẽ có alerts. Silence alertname=~"Kafka.*" trong 2 giờ. Nếu maintenance kéo dài 3 giờ → gì xảy ra? (silence hết hạn → alerts flood inbox)

---

## 🔧 AM-3: Grouping Behavior

**Kiến thức:** group_wait, group_interval, repeat_interval — timing controls.
**Độ khó:** ⭐⭐⭐

### Break
```bash
# Gửi 3 alerts cùng group (cùng alertname + severity) nhưng khác instance
for i in 1 2 3; do
  curl -s -X POST http://localhost:9093/api/v2/alerts \
    -H "Content-Type: application/json" \
    -d '[{
      "labels": {"alertname": "TestGrouping", "severity": "warning", "instance": "server-'$i':9090"},
      "annotations": {"summary": "Test grouping instance '$i'"},
      "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "endsAt": "'$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)'"
    }]'
  sleep 2
done
```

### Test (inspect internals)
```bash
# Xem alerts grouped
curl -s http://localhost:9093/api/v2/alerts | python3 -c "
import sys,json
data = json.load(sys.stdin)
groups = {}
for a in data:
    key = f\"{a['labels'].get('alertname','')}:{a['labels'].get('severity','')}\""
    groups.setdefault(key, []).append(a['labels'].get('instance',''))
for k,v in groups.items():
    print(f\"{k} → {len(v)} instances: {v}\")
"

# Check Alertmanager logs cho grouping timing
docker logs alertmanager --tail 20 2>&1 | grep -i "group\|notify\|dispatch"
```

**Timing parameters (từ config hiện tại):**
| Parameter | Critical | Warning | Ý nghĩa |
|-----------|----------|---------|---------|
| `group_wait` | 10s | 1m | Chờ bao lâu trước khi gửi notification đầu tiên (gom alerts) |
| `group_interval` | 5m | 5m | Nếu có alert mới trong group → gửi update sau bao lâu |
| `repeat_interval` | 1h | 4h | Gửi lại notification nếu alert vẫn firing |

### Recovery
```bash
# Resolve all test alerts
for i in 1 2 3; do
  curl -s -X POST http://localhost:9093/api/v2/alerts \
    -H "Content-Type: application/json" \
    -d '[{
      "labels": {"alertname": "TestGrouping", "severity": "warning", "instance": "server-'$i':9090"},
      "endsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }]'
done
```

### 🎯 Câu hỏi kiểm tra
- [ ] **group_wait trade-off:** group_wait=10s (critical) vs 1m (warning). Tại sao critical ngắn hơn? (cần nhận alert nhanh — 10s delay acceptable. Warning có thể chờ gom 1 phút)
- [ ] **Notification flood:** 50 targets down cùng lúc → 50 alerts fire. Nhờ grouping, on-call nhận bao nhiêu notifications? (1 notification chứa 50 alerts, thay vì 50 notifications riêng)
- [ ] **Production:** repeat_interval=4h cho warning. Nếu warning alert fire lúc 9:00 AM → next notification lúc 1:00 PM. Có quá lâu không? Team size nào cần repeat ngắn hơn?

---

# Part 7: OTel + Tempo Pipeline

> **VM:** observability-vm
> **OTel Config:** [otel-config.yml](observability-vm/phase3-tracing/otel-collector/otel-config.yml)
> **Tempo Config:** [tempo-config.yml](observability-vm/phase3-tracing/tempo/tempo-config.yml)
> **Pipeline:** apps → OTel (OTLP) → filter → tail_sampling → Tempo + spanmetrics → Prometheus

## 🔧 OT-1: Collector Restart

**Kiến thức:** OTel Collector buffering, SDK retry behavior, data loss during restart.
**Độ khó:** ⭐⭐

### Break
```bash
# Chạy traffic trên applications-vm
curl -X POST http://192.168.100.57:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 5, "duration": 60}'

# Kill OTel Collector giữa chừng
sleep 10
docker restart otel-collector
```

### Test (inspect internals)
```bash
# Xem OTel Collector logs — có data loss không?
docker logs otel-collector --tail 30 2>&1 | grep -i "error\|drop\|retry\|export"

# Xem app logs — SDK retry?
ssh 192.168.100.57 "docker logs order-service --tail 20 2>&1 | grep -i 'otel\|export\|retry'"

# Query Tempo — có trace gap không?
curl -s "http://localhost:3200/api/search?q={}" | python3 -c "
import sys,json
data = json.load(sys.stdin)
print(f\"Traces found: {len(data.get('traces', []))}\")
"
```

### Recovery
```bash
# OTel Collector đã restart. Verify healthy:
curl -s http://localhost:13133/  # health check endpoint
docker logs otel-collector --tail 5
```

### 🎯 Câu hỏi kiểm tra
- [ ] **SDK retry:** OTel SDK trong app có buffer và retry khi collector down. Buffer mất khi app restart. Duration of collector downtime app có thể tolerate?
- [ ] **Data loss:** Restart mất ~5 giây. Traces trong 5 giây đó → SDK buffer → retry sau khi collector up. Liệu có mất? (phụ thuộc buffer size và retry policy)
- [ ] **Production:** OTel Collector OOM (processing quá nhiều spans). Cách giảm load? (sampling, filter health check spans, tăng batch size)

---

## 🔧 OT-2: Tail Sampling

**Kiến thức:** Tail-based sampling, decision_wait, policy evaluation.
**Độ khó:** ⭐⭐⭐

### Break
Không cần thay đổi config — inspect sampling behavior hiện tại.

### Test (inspect internals)
```bash
# Xem sampling policies trong config
grep -A 30 "tail_sampling" /root/workspace/observability-sample-v2/on-premises/observability-vm/phase3-tracing/otel-collector/otel-config.yml

# Chạy traffic có errors
ssh 192.168.100.57 "docker stop payment-service"
curl -X POST http://192.168.100.57:5003/start \
  -H "Content-Type: application/json" \
  -d '{"scenario": "normal", "rate": 2, "duration": 30}'

# Xem OTel Collector metrics (sampling stats)
curl -s http://localhost:8888/metrics | grep -E "processor_tail_sampling|otelcol_processor"

# Query Tempo — error traces should be 100% kept
curl -s "http://localhost:3200/api/search?q={status=error}&limit=5" | python3 -m json.tool | head -20

# Start payment lại
ssh 192.168.100.57 "docker start payment-service"
```

**Current sampling policies:**
| Policy | Rule | Effect |
|--------|------|--------|
| `keep-errors` | status_code = ERROR | 100% error traces kept |
| `keep-slow-requests` | latency > 500ms | 100% slow traces kept |
| `random-sample` | 10% probabilistic | 10% normal traces kept |

### Recovery
```bash
ssh 192.168.100.57 "docker start payment-service"
```

### 🎯 Câu hỏi kiểm tra
- [ ] **Head vs Tail sampling:** Head sampling (quyết định lúc bắt đầu trace — nhanh, có thể miss errors). Tail sampling (chờ trace complete — chính xác hơn, tốn RAM). Trade-off?
- [ ] **decision_wait=10s:** Collector buffer trace 10 giây trước khi quyết định keep/drop. Nếu trace có span chậm 15 giây → quyết định sai? (có thể — force decision trước khi trace complete)
- [ ] **Production:** Traffic 10K spans/s × 10s decision_wait = 100K spans in buffer. Với `num_traces=50000`, gì xảy ra khi vượt? (oldest traces force-decided, có thể drop)

---

## 🔧 OT-3: Tempo Storage

**Kiến thức:** Tempo block storage, compaction, retention, MinIO backend.
**Độ khó:** ⭐⭐

### Break
Không inject — inspect storage.

### Test (inspect internals)
```bash
# Xem Tempo status
curl -s http://localhost:3200/status | head -20

# Xem storage qua MinIO (nếu mc available)
docker exec minio sh -c "ls -la /data/tempo/" 2>/dev/null

# Xem Tempo metrics
curl -s http://localhost:3200/metrics | grep -E "tempo_ingester|tempo_compactor" | head -20

# Xem Tempo config (retention)
grep -A 5 "compactor" /root/workspace/observability-sample-v2/on-premises/observability-vm/phase3-tracing/tempo/tempo-config.yml
```

**Tempo storage model:**
```
MinIO (tempo bucket)
├── single-tenant/
│   ├── wal/          ← Write-ahead log (recent traces)
│   ├── blocks/       ← Compacted trace blocks
│   └── compacted/    ← Further compacted blocks
```

### Recovery
Không cần.

### 🎯 Câu hỏi kiểm tra
- [ ] **Retention:** `block_retention: 168h` (7 days). Traces cũ hơn 7 ngày bị xóa. Có cần giữ lâu hơn? (thường không — traces dùng cho debug ngắn hạn)
- [ ] **Compaction:** Tempo compactor gộp small blocks thành large blocks. Tại sao? (giảm số files, tăng query performance)
- [ ] **Production:** Trace storage 500MB/day × 7 days = 3.5GB. Nếu tăng sampling 100% → 5GB/day × 7 = 35GB. 10x storage increase. Cần planning trước khi thay đổi sampling!

---

# Recommended Order

| Thứ tự | Exercise | Độ khó | Time | Component | Kiến thức chính |
|--------|----------|--------|------|-----------|-----------------|
| 1 | PG-1 Connection Pool | ⭐ | 15m | PostgreSQL | pg_stat_activity, connection states |
| 2 | PG-6 Query Analysis | ⭐⭐ | 20m | PostgreSQL | EXPLAIN ANALYZE, index |
| 3 | RD-3 Key Analysis | ⭐ | 10m | Redis | SCAN, MEMORY USAGE |
| 4 | KF-1 Offset Management | ⭐⭐ | 20m | Kafka | Consumer groups, offsets |
| 5 | PM-4 Scrape & Targets | ⭐⭐ | 15m | Prometheus | up metric, target states |
| 6 | PG-2 Dead Tuples | ⭐⭐ | 25m | PostgreSQL | MVCC, VACUUM |
| 7 | RD-1 Memory & Eviction | ⭐⭐ | 20m | Redis | maxmemory, eviction |
| 8 | KF-2 Log Segments | ⭐⭐ | 15m | Kafka | Disk storage, retention |
| 9 | AM-1 Routing Tree | ⭐⭐ | 20m | Alertmanager | Route matching |
| 10 | AM-2 Silence | ⭐⭐ | 20m | Alertmanager | Silence, inhibition |
| 11 | LK-1 Label Cardinality | ⭐⭐⭐ | 25m | Loki | Label design |
| 12 | LK-2 LogQL Performance | ⭐⭐ | 15m | Loki | Query optimization |
| 13 | PG-5 Lock Monitoring | ⭐⭐⭐ | 30m | PostgreSQL | pg_locks, deadlock |
| 14 | PG-3 WAL & Checkpoint | ⭐⭐⭐ | 30m | PostgreSQL | WAL, durability |
| 15 | RD-2 Persistence | ⭐⭐⭐ | 25m | Redis | RDB vs AOF |
| 16 | KF-3 Producer Delivery | ⭐⭐⭐ | 25m | Kafka | acks, retries |
| 17 | PM-1 TSDB & WAL | ⭐⭐⭐ | 30m | Prometheus | WAL replay, blocks |
| 18 | PM-2 Cardinality | ⭐⭐⭐ | 25m | Prometheus | Series explosion |
| 19 | OT-1 Collector Restart | ⭐⭐ | 20m | OTel | Buffering, retry |
| 20 | OT-2 Tail Sampling | ⭐⭐⭐ | 30m | OTel | Sampling policies |
| 21 | PG-4 Backup & PITR | ⭐⭐⭐ | 35m | PostgreSQL | pg_dump, restore |
| 22 | RD-4 Slowlog | ⭐⭐ | 15m | Redis | O(N) commands |
| 23 | KF-4 Consumer Rebalance | ⭐⭐⭐ | 25m | Kafka | Partition assignment |
| 24 | KF-5 Topic Configuration | ⭐⭐ | 20m | Kafka | Dynamic configs |
| 25 | AM-3 Grouping | ⭐⭐⭐ | 25m | Alertmanager | group_wait timing |
| 26 | PM-3 Retention & Storage | ⭐⭐ | 20m | Prometheus | Capacity planning |
| 27 | LK-3 Storage | ⭐⭐ | 15m | Loki | MinIO, retention |
| 28 | OT-3 Tempo Storage | ⭐⭐ | 15m | Tempo | Block storage |

**Tổng thời gian:** ~12-15 giờ để hoàn thành tất cả 28 exercises.

**Estimated times theo độ khó:**
- ⭐ = 10-15 phút
- ⭐⭐ = 15-25 phút  
- ⭐⭐⭐ = 25-35 phút

**Learning schedule gợi ý:**
- **Week 1:** Exercises 1-10 (basics, ~3 giờ)
- **Week 2:** Exercises 11-20 (intermediate, ~4 giờ)
- **Week 3:** Exercises 21-28 (advanced, ~3 giờ)
- **Week 4:** Review + combine với IS experiments