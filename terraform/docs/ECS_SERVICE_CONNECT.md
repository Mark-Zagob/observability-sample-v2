# 🔗 Service Discovery & Inter-Service Communication — Concept Guide

*Tài liệu kỹ thuật so sánh các phương pháp service-to-service communication trên ECS. Phục vụ việc ra quyết định khi scale hệ thống.*

---

## 📍 Hiện trạng (As-Is): Cloud Map DNS

```
Order Service ──DNS resolve──▶ payment-service.ecommerce.local ──HTTP──▶ Payment Service
                (Route 53)        A record, TTL=10s                       (port 5002)
                                  MULTIVALUE routing
```

**Terraform resources:**
- [`ecs-cluster/main.tf`](../modules/compute/ecs-cluster/main.tf): `aws_service_discovery_private_dns_namespace` → `ecommerce.local`
- [`ecs-service/service_discovery.tf`](../modules/compute/ecs-service/service_discovery.tf): `aws_service_discovery_service` → A record per service
- [`ecs-service/service.tf`](../modules/compute/ecs-service/service.tf): `service_registries` block → ECS auto-register task IP vào Cloud Map

**Cách hoạt động:**
1. ECS deploy task mới → tự động gọi `RegisterInstance` vào Cloud Map
2. Cloud Map tạo DNS A record trong Route 53 private hosted zone
3. Service khác resolve DNS `payment-service.ecommerce.local` → nhận task IP
4. ECS stop task → tự động `DeregisterInstance` → DNS record bị xóa (sau TTL)

**Ưu điểm:**
- Đơn giản, không sidecar, không resource overhead
- App code chỉ cần DNS name, không phụ thuộc AWS SDK
- Transparent — dễ debug (nslookup/dig)

**Hạn chế (đã phát hiện qua Chaos Experiments):**

| Hạn chế | Phát hiện từ | Impact |
|---|---|---|
| **DNS TTL cache** (10-60s) | Exp 6 (Cloud Map DNS Failure) | Stale IP → request tới task đã chết |
| **Không health check** | Exp 2 (Network Partition) | Zombie Task — task RUNNING nhưng unreachable, DNS vẫn trỏ tới nó |
| **DNS-level load balancing** | Architecture review | Round-robin qua DNS, không biết backend nào busy/slow |
| **Không retry/timeout** | Exp 5 (Cascading Failure) | App phải tự implement retry, dễ sai (retry storm) |
| **Không connection metrics** | Exp 4 (Task Role Blackhole) | Silent failure — monitoring mù trước app-level errors |

---

## 🔮 ECS Service Connect (To-Be)

### Bản chất

ECS Service Connect = **managed Envoy proxy** inject vào mỗi ECS Task như sidecar container.

```
                              ┌─ Envoy sidecar ─┐
Order Service ──localhost──▶  │  (interceptor)   │ ──▶ Payment Service Envoy ──▶ Payment App
  (app code)                  │  - health check  │     (target resolver)
  http://payment:5002         │  - retry logic   │
                              │  - circuit break │
                              │  - metrics export│
                              └──────────────────┘
```

### Cách hoạt động (chi tiết)

1. **Khai báo trong ECS Service** — thêm `service_connect_configuration` block
2. ECS inject **Envoy sidecar container** vào Task Definition (tự động, không cần config thêm)
3. App code vẫn gọi `http://payment-service:5002` — **KHÔNG thay đổi code**
4. Envoy intercept outbound request → resolve target IP **real-time** (không qua DNS TTL)
5. Envoy thực hiện:
   - **Active health check** → loại target unhealthy
   - **Request-level load balancing** (round-robin / least connections)
   - **Retry** với configurable policy
   - **Connection draining** khi task shutting down
6. Envoy export metrics vào **CloudWatch** (request count, error rate, latency P50/P95/P99)

### Terraform Configuration (Reference)

```hcl
# Trong ecs-cluster/main.tf — thêm Service Connect namespace
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.this.arn
  }
}

# Service Connect dùng HTTP namespace (không phải DNS namespace)
resource "aws_service_discovery_http_namespace" "this" {
  name        = var.namespace_name
  description = "Service Connect namespace for ${var.project_name}"
}
```

```hcl
# Trong ecs-service/service.tf — thêm service_connect_configuration
resource "aws_ecs_service" "this" {
  # ... existing config ...

  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    # Server-side: expose port để services khác gọi tới
    service {
      port_name      = var.service_name
      discovery_name = var.service_name

      client_alias {
        port     = var.container_port
        dns_name = var.service_name
      }

      timeout {
        per_request_timeout_seconds = 15
        idle_timeout_seconds        = 60
      }
    }

    # Log config cho Envoy sidecar
    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}/${var.service_name}/envoy"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "envoy"
      }
    }
  }
}
```

```hcl
# Trong task_definition.tf — Envoy sidecar resource budget
# ECS TỰ ĐỘNG inject sidecar, nhưng cần allocate thêm resource:
#   CPU:    256 units (0.25 vCPU)
#   Memory: 64 MB (minimum)
# → Task definition cần tăng total resource tương ứng
```

### Resource overhead

| Resource | Cloud Map DNS | Service Connect |
|---|---|---|
| CPU per task | +0 | +256 units (0.25 vCPU) |
| Memory per task | +0 | +64-128 MB |
| Container count | 1 (app) + 1 (otel sidecar) | 1 (app) + 1 (otel) + 1 (envoy) |
| Monthly cost estimate (2 services × 1 task) | $0 | ~$5-10 (Fargate pricing cho extra resource) |

---

## 📊 So sánh chi tiết

### Feature Matrix

| Feature | Cloud Map DNS | ECS Service Connect |
|---|---|---|
| **Setup complexity** | Thấp — DNS + service_registries | Trung bình — service_connect_configuration |
| **App code change** | Không | Không (same DNS name) |
| **Resolution** | DNS A record (TTL-based) | Real-time (Envoy service mesh) |
| **Load balancing** | DNS round-robin (client-side) | Request-level (round-robin / least connections) |
| **Health check** | Passive — `health_check_custom_config` | Active — Envoy probes target periodically |
| **Retry** | App tự implement | Envoy auto-retry (configurable) |
| **Timeout** | App tự set | Envoy enforced (`per_request_timeout_seconds`) |
| **Circuit breaker** | App tự implement (ví dụ: pybreaker) | Envoy built-in outlier detection |
| **Connection draining** | Không — abrupt disconnect khi task stop | Có — Envoy drain connections gracefully |
| **Metrics** | Không có sẵn | CloudWatch: RequestCount, ErrorCount, Latency P50/P95/P99 |
| **Zombie Task** | ⚠️ Blind spot (Exp 2, 6) | ✅ Active health check loại unhealthy |
| **DNS TTL stale** | ⚠️ 10-60s stale window | ✅ Real-time target update |
| **Cascading failure** | ⚠️ App-level only (Exp 5) | ✅ Envoy retry + timeout + outlier detection |
| **Debug complexity** | Thấp — nslookup/dig | Cao — cần hiểu Envoy config + logs |

### Decision Matrix — Khi nào nên migrate?

| Signal | Threshold | Action |
|---|---|---|
| Số lượng services | ≤ 4 | **Giữ Cloud Map DNS** |
| Số lượng services | > 4 | **Consider Service Connect** |
| Cascading failure xảy ra thường xuyên | Exp 5 reproduce in prod | **Migrate** — Envoy retry + outlier detection |
| Zombie Task gây outage | Exp 2/6 confirm blind spot | **Migrate** — active health check |
| Cần HTTP error rate metrics | Monitoring gap từ Exp 4 | **Migrate** — built-in CloudWatch metrics |
| Team chưa hiểu Service Mesh concept | N/A | **Chưa migrate** — learn Cloud Map limitations first |

---

## 🗺️ Migration Path (Khi sẵn sàng)

### Phase 1: Parallel Run (1 service)

```
payment-service → Cloud Map DNS (hiện tại) — production traffic
payment-service → Service Connect (mới)    — test traffic
```

1. Tạo `aws_service_discovery_http_namespace` song song (không xóa DNS namespace)
2. Deploy payment-service với `service_connect_configuration` trên cluster test
3. Verify: Envoy metrics xuất hiện trong CloudWatch
4. Re-run Exp 5 (Cascading Failure) → compare TTD với/không Service Connect

### Phase 2: Full Migration

1. Migrate tất cả services sang Service Connect
2. Xóa `aws_service_discovery_service` (DNS records) — không cần nữa
3. Giữ `aws_service_discovery_private_dns_namespace` cho backward compatibility (nếu cần)
4. Update Chaos Playbook: thêm Envoy-specific experiments

### Phase 3: Advanced Features

- **Traffic shifting**: Canary deployment 10% → 50% → 100%
- **Outlier detection**: Tự động loại target có error rate > threshold
- **mTLS**: Encrypt service-to-service traffic (cần ACM Private CA)

---

## 📎 Tham khảo

- [AWS Docs: ECS Service Connect](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html)
- [AWS Docs: Service Connect concepts](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect-concepts.html)
- [AWS Docs: Cloud Map DNS-based discovery](https://docs.aws.amazon.com/cloud-map/latest/dg/working-with-services.html)
- [Envoy Proxy docs](https://www.envoyproxy.io/docs/envoy/latest/)
- **So sánh chính thức:** [Service Connect vs Service Discovery](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/networking-connecting-services.html)
- **Lab references:**
  - Exp 2 (Zombie Task): [`AWS_CHAOS_PLAYBOOK.md` Exp 2](./AWS_CHAOS_PLAYBOOK.md#-experiment-2-the-network-partition-security-group-isolation)
  - Exp 5 (Cascading Failure): [`AWS_CHAOS_PLAYBOOK.md` Exp 5](./AWS_CHAOS_PLAYBOOK.md#-experiment-5-cascading-failure-payment-slow--order-timeout)
  - Exp 6 (DNS Failure): [`AWS_CHAOS_PLAYBOOK.md` Exp 6](./AWS_CHAOS_PLAYBOOK.md#-experiment-6-cloud-map-dns-failure-service-discovery-disruption)
