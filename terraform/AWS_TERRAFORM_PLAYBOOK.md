 📖 AWS Terraform Playbook

> **Action-oriented playbook** để deploy, vận hành, và học hỏi AWS infrastructure. Mỗi module là một "chapter" với Learning Outcomes, Hands-on Drills, và Troubleshooting Guide.

🔗 **Related:** [README_AWS.md](README_AWS.md) | [ARCHITECTURE_AWS.md](ARCHITECTURE_AWS.md) | [FINOPS.md](FINOPS.md)

---

## 🎯 Mục tiêu

Deploy hệ thống observability lab lên AWS bằng Terraform theo production-grade standards:
- **Shared infrastructure** deploy 1 lần
- **Swap giữa 4 compute phases** (ECS/EKS) để học và so sánh
- **Mỗi module = 1 learning unit** với drills & troubleshooting

---

## 📊 Tiến độ tổng quan

| # | Module | Trạng thái | Learning Focus |
|---|--------|------------|----------------|
| 1 | network | ✅ Done | VPC, Subnets, NAT |
| 2 | vpc-endpoints | ✅ Done | S3/DDB Gateway, Interface Endpoints |
| 3 | security | ✅ Done | SGs, IAM Roles |
| 4 | database | ✅ Done | RDS, KMS, Secrets Manager |
| 5 | cache | 🔲 TODO | ElastiCache Redis |
| 6 | streaming | 🔲 TODO | MSK Kafka |
| 7 | opensearch | 🆕 NEW | Amazon OpenSearch Service |
| 8 | rds-proxy | 🆕 NEW | Connection pooling |
| 9 | ecr | 🔲 TODO | Container Registry |
| 10 | efs | 🔲 TODO | Elastic File System |
| 11 | loadbalancer | 🔲 TODO | ALB + ACM + Route53 |
| 12 | bastion | 🔲 TODO | EC2 + SSM |
| 13 | cicd | 🔲 TODO | OIDC + GitHub Actions |
| 14 | backup | ✅ Done | AWS Backup + cross-region |
| 15 | budgets | 🔲 TODO | AWS Budgets + Cost Anomaly |
| 16 | fis | 🆕 NEW | AWS Fault Injection Simulator |
| 17 | dr | 🔲 TODO | Pilot Light DR |

---

## 🔧 Module Format

Mỗi module dưới đây tuân theo format chuẩn:

- `Module X: [Name]`
- 📋 Specification
- 🎯 Learning Outcomes
- 🧪 Hands-on Drills
- 🔧 Troubleshooting
- 💰 Cost & Optimization

---

## Module 1: `network` ✅

### 📋 Specification

| Resource | Config |
|----------|--------|
| VPC | 10.0.0.0/16 |
| Public Subnets × 3 | 10.0.1-3.0/24 — ALB, NAT, Bastion |
| Private Subnets × 3 | 10.0.11-13.0/24 — Compute workloads |
| Data Subnets × 3 | 10.0.21-23.0/24 — RDS, Redis, MSK, EFS |
| Mgmt Subnets × 3 | 10.0.31-33.0/24 — Bastion, admin tools |
| NAT Gateway | Configurable: 1 (save cost) or 3 (HA) |
| NACLs | Stateless deny rules per tier |
| VPC Flow Logs | CloudWatch (30-day retention) |

### 🎯 Learning Outcomes

Sau khi hoàn thành module này, bạn sẽ:
- [ ] Giải thích được tại sao cần tách 4 tiers (Public/Private/Data/Mgmt)
- [ ] Tính được CIDR blocks cho VPC với 3 AZs
- [ ] Hiểu sự khác biệt giữa Security Groups (stateful) và NACLs (stateless)
- [ ] Cấu hình VPC Flow Logs và query bằng Athena

### 🧪 Hands-on Drills

1. **Drill 1.1:** Deploy VPC, verify subnet CIDR allocation
2. **Drill 1.2:** Tạo EC2 instance trong private subnet, verify không có public IP
3. **Drill 1.3:** Test NAT Gateway — curl external URL từ private subnet
4. **Drill 1.4:** Query VPC Flow Logs bằng Athena — tìm rejected traffic

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| EC2 trong private subnet không curl được internet | NAT Gateway chưa tạo hoặc route table sai | Kiểm tra route table của private subnet có route 0.0.0.0/0 → NAT |
| ALB không nhận traffic | Security Group của ALB chưa mở 80/443 | Thêm inbound rule 80/443 từ 0.0.0.0/0 |
| VPC Flow Logs không hiện | IAM role cho Flow Logs chưa đủ quyền | Attach `CloudWatchLogsFullAccess` policy |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| NAT Gateway (×1) | $0.045/hr + $0.045/GB | Dùng single NAT cho lab, 3 NAT cho production |
| VPC Flow Logs | $0.50/GB ingested | Filter logs, retention 30 ngày |

---

## Module 2: `vpc-endpoints` ✅

### 📋 Specification

| Type | Endpoints | Cost |
|------|-----------|------|
| Gateway (FREE) | S3, DynamoDB | $0 |
| Interface | ECR (api + dkr), SSM, Secrets Manager, Logs, STS | ~$7.2/month/endpoint/AZ |

### 🎯 Learning Outcomes

- [ ] Phân biệt được Gateway vs Interface endpoints
- [ ] Giải thích tại sao VPC Endpoints giảm chi phí Data Transfer
- [ ] Cấu hình endpoint policy để restrict access

### 🧪 Hands-on Drills

1. **Drill 2.1:** Tạo S3 Gateway endpoint, verify traffic không qua NAT
2. **Drill 2.2:** Tạo ECR Interface endpoint, verify ECR pull không dùng NAT
3. **Drill 2.3:** So sánh cost trước/sau khi tạo endpoints

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| EC2 không pull được image từ ECR dù đã tạo endpoint | DNS resolution chưa bật | Enable `enableDnsHostnames` và `enableDnsSupport` trong VPC |
| Endpoint policy block access | Policy quá restrictive | Review policy, thêm `s3:GetObject` permission |

### 💰 Cost & Optimization

- **Hidden cost:** Interface endpoint = $0.01/hr/AZ + $0.01/GB
- **Optimization:** Chỉ tạo endpoints cho services có traffic lớn (S3, ECR, Logs)

---

## Module 3: `security` ✅

### 📋 Specification

**Security Groups (Defense-in-Depth):**

| SG | Inbound | Outbound |
|----|---------|----------|
| ALB | 80/443 from Internet | app_port to App SG |
| Application | app_port from ALB, SSM from Bastion | Data ports, EFS, HTTPS, OTLP |
| Data | DB ports from App + Bastion | Ephemeral responses only |
| EFS | NFS (2049) from App | Ephemeral responses |
| Observability | OTLP 4317/4318 from App | HTTPS, scrape ports |
| Bastion | SSM from trusted CIDRs | SSH/DB ports/HTTPS/DNS |

**IAM Roles:**

| Role | Permissions |
|------|-------------|
| ECS Task Execution | ECR pull, CloudWatch Logs, SSM/Secrets read, KMS decrypt |
| ECS Task | CloudWatch metrics, X-Ray traces, ECS Exec (SSM) |
| Bastion | SSM managed instance |

### 🎯 Learning Outcomes

- [ ] Thiết kế Security Groups theo principle of least privilege
- [ ] Phân biệt ECS Task Role vs Task Execution Role
- [ ] Sử dụng IAM conditions để restrict access (ví dụ: chỉ cho phép từ VPC cụ thể)

### 🧪 Hands-on Drills

1. **Drill 3.1:** Tạo SG cho RDS, verify chỉ App SG mới connect được
2. **Drill 3.2:** Attach IAM role vào ECS task, verify task đọc được secret từ Secrets Manager
3. **Drill 3.3:** Test SSM Session Manager — connect vào Bastion không cần SSH key

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| ECS task không pull được image từ ECR | Task Execution Role thiếu `ecr:GetAuthorizationToken` | Thêm ECR read policy |
| SSM Session Manager không connect | IAM role thiếu `ssm:StartSession` | Attach `AmazonSSMManagedInstanceCore` |
| RDS không connect được từ App SG | SG của RDS chưa mở port 5432 cho App SG | Thêm inbound rule |

### 💰 Cost & Optimization

- Security Groups: **FREE**
- IAM: **FREE**
- SSM Session Manager: **FREE** (cho < 1000 sessions/tháng)

---

## Module 4: `database` ✅

### 📋 Specification

| Resource | Config |
|----------|--------|
| RDS PostgreSQL 16 | db.t3.micro, gp3, encrypted (CMK) |
| Multi-AZ | Configurable (true for production) |
| Secrets Manager | RDS-managed auto-rotation (7 days) |
| SSM Parameters | endpoint, host, port, db_name, username, secret_arn |
| CloudWatch Alarms | CPU, storage, connections, secret rotation failure |
| Performance Insights | Enabled (7d free, 731d prod) |
| Read Replicas | Configurable count (0 for lab) |
| KMS | Dedicated CMK for RDS + Secrets |
| Enhanced Monitoring | Configurable interval |

### 🎯 Learning Outcomes

- [ ] Giải thích được RDS Multi-AZ failover mechanism (~60s)
- [ ] Thực hiện manual failover và đo actual RTO
- [ ] Cấu hình Performance Insights và đọc được top queries
- [ ] Restore point-in-time backup vào instance mới
- [ ] So sánh RDS Proxy vs self-hosted PgBouncer

### 🧪 Hands-on Drills

1. **Drill 4.1:** Trigger manual failover, measure app reconnect time
2. **Drill 4.2:** Fill up storage to 95%, observe CloudWatch alarm
3. **Drill 4.3:** Restore PITR to new instance, verify data consistency
4. **Drill 4.4:** Simulate connection pool exhaustion với k6
5. **Drill 4.5:** Enable Performance Insights, analyze slow queries

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| App không connect được sau failover | DNS cache chưa update | Restart app hoặc dùng RDS Proxy |
| Secret rotation fail | Lambda rotation function thiếu quyền | Attach `SecretsManagerRotation` policy |
| Storage full | Auto-scaling chưa enable | Enable storage auto-scaling |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| RDS (db.t3.micro, Multi-AZ) | ~$0.036/hr | Dùng Single-AZ cho lab |
| Performance Insights | Free 7 ngày, $0.01/hr sau đó | Disable khi không dùng |
| Secrets Manager | $0.40/secret/month + $0.05/10K API calls | Reduce rotation frequency |

---

## Module 5: `cache` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| ElastiCache Replication Group | Redis 7.x, cache.t3.micro |
| Multi-AZ | Auto failover enabled |
| Subnet Group | Data subnets |
| Parameter Group | Custom Redis tuning (maxmemory-policy, timeout) |
| KMS Key | Encryption at-rest (CMK) |
| Auth Token | Secrets Manager + auto-rotation |
| CloudWatch Alarms | CPU, memory, connections, replication lag |

### 🎯 Learning Outcomes

- [ ] Phân biệt Cluster Mode vs Replication Group
- [ ] Handle endpoint DNS changes khi master node bị replace
- [ ] Cấu hình Redis parameter group (maxmemory-policy, timeout)
- [ ] Monitor replication lag và evictions

### 🧪 Hands-on Drills

1. **Drill 5.1:** Trigger failover, measure downtime
2. **Drill 5.2:** Fill cache to 90%, observe eviction policy
3. **Drill 5.3:** Simulate connection exhaustion
4. **Drill 5.4:** Monitor slow log trong CloudWatch

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Cache miss rate cao | TTL quá ngắn hoặc key pattern không tối ưu | Review TTL, dùng cache warming |
| Replication lag cao | Write-heavy workload | Scale up instance hoặc add read replicas |
| Connection timeout | Max clients reached | Scale up hoặc dùng connection pooling |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| ElastiCache (cache.t3.micro) | ~$0.017/hr | Dùng smaller instance cho lab |
| Data transfer | $0.01/GB cross-AZ | Keep traffic within AZ |

---

## Module 6: `streaming` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| MSK Cluster | kafka.t3.small, 2 brokers (lab) / 3 (prod) |
| MSK Configuration | Custom broker config (auto.create.topics, retention) |
| KMS Key | Encryption at-rest (CMK) |
| CloudWatch Log Group | Broker logs |
| CloudWatch Alarms | Under-replicated partitions, offline partitions, disk usage |

### 🎯 Learning Outcomes

- [ ] Hiểu MSK broker configuration (JVM tuning, partition limits)
- [ ] Monitor Kafka metrics qua CloudWatch
- [ ] Handle broker failures và partition re-election
- [ ] So sánh MSK vs self-hosted Kafka (KRaft)

### 🧪 Hands-on Drills

1. **Drill 6.1:** Kill 1 broker, observe partition leader election
2. **Drill 6.2:** Monitor consumer lag, simulate lag spike
3. **Drill 6.3:** Test TLS encryption giữa producer và broker
4. **Drill 6.4:** Scale brokers từ 2 → 3, observe partition rebalance

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Under-replicated partitions | Broker down hoặc network issue | Check broker health, network connectivity |
| Consumer lag cao | Consumer slow hoặc partition imbalance | Scale consumer group, rebalance partitions |
| Producer timeout | Broker overloaded | Scale up broker instance |

### 💰 Cost & Optimization

⚠️ **MSK là resource tốn chi phí nhất (~$5/ngày với 2 brokers t3.small). Nên destroy khi không dùng.**

| Resource | Cost | Optimization |
|----------|------|--------------|
| MSK (2 brokers t3.small) | ~$0.21/hr | Destroy khi không dùng |
| Data transfer | $0.01/GB cross-AZ | Keep traffic within AZ |

---

## Module 7: `opensearch` 🆕 NEW

### 📋 Specification

| Resource | Config |
|----------|--------|
| Amazon OpenSearch Domain | t3.small.search × 2 data nodes |
| Multi-AZ | 2 AZs for HA |
| VPC Access | Data subnets only |
| Encryption | KMS CMK at-rest, TLS in-transit |
| Fine-Grained Access | IAM + internal user database |
| Index Lifecycle | ISM policies for orders-v1, orders-v2 |
| Snapshot | Automated daily → S3 |
| CloudWatch Alarms | Cluster status red/yellow, JVM pressure |

### 🎯 Learning Outcomes

- [ ] Thiết kế OpenSearch domain với VPC access
- [ ] Cấu hình ISM (Index State Management) policies
- [ ] Implement zero-downtime reindex với index aliases
- [ ] Monitor cluster health và JVM pressure

### 🧪 Hands-on Drills

1. **Drill 7.1:** Tạo index, verify data ingestion
2. **Drill 7.2:** Simulate node failure, observe cluster recovery
3. **Drill 7.3:** Reindex từ orders_v1 → orders_v2 với alias switch
4. **Drill 7.4:** Monitor JVM pressure, tune heap size

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Cluster status red | All replicas lost | Restore từ snapshot |
| JVM pressure cao | Heap size quá nhỏ hoặc query phức tạp | Scale up instance hoặc optimize queries |
| Index lag cao | Sync process chậm | Review sync strategy, scale sync workers |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| OpenSearch (t3.small × 2) | ~$30/tháng | Destroy khi không dùng |
| Data transfer | $0.01/GB cross-AZ | Keep traffic within AZ |

---

## Module 8: `rds-proxy` 🆕 NEW

### 📋 Specification

| Resource | Config |
|----------|--------|
| RDS Proxy | PostgreSQL compatible |
| Connection Pooling | Transaction mode |
| IAM Auth | Enabled |
| CloudWatch Alarms | Connection count, latency, failover time |

### 🎯 Learning Outcomes

- [ ] So sánh RDS Proxy vs self-hosted PgBouncer
- [ ] Hiểu connection multiplexing mechanism
- [ ] Handle failover transparency
- [ ] Monitor connection pool metrics

### 🧪 Hands-on Drills

1. **Drill 8.1:** Deploy RDS Proxy, update app connection strings
2. **Drill 8.2:** Simulate connection exhaustion, observe proxy behavior
3. **Drill 8.3:** Trigger RDS failover, measure proxy reconnect time
4. **Drill 8.4:** Monitor connection pool metrics

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| App không connect được | IAM auth chưa setup đúng | Review IAM policy cho RDS Proxy |
| Connection timeout | Max connections reached | Scale up proxy hoặc tune pool size |
| Failover chậm | Proxy chưa detect RDS failover | Check CloudWatch metrics |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| RDS Proxy | $0.015/conn-hour | Disable khi không dùng |

---

## Module 9: `ecr` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| ECR Repositories × 10 | api-gateway, order-service, payment-service, notification-worker, inventory-worker, traffic-gen, web-ui, auth-service, shipping-service, search-service |
| Lifecycle Policy | Keep last 10 tagged images, expire untagged after 7 days |
| Image Scanning | Scan on push (basic) |
| Encryption | KMS (CMK) hoặc AES-256 default |
| Repository Policy | Allow pull from ECS/EKS task roles |

### 🎯 Learning Outcomes

- [ ] Thiết kế ECR repository structure cho 10 services
- [ ] Cấu hình lifecycle policy để giảm storage cost
- [ ] Setup image scanning on push
- [ ] Grant cross-account pull permissions

### 🧪 Hands-on Drills

1. **Drill 9.1:** Push image lên ECR, verify scan results
2. **Drill 9.2:** Pull image từ ECS task role
3. **Drill 9.3:** Test lifecycle policy — verify untagged images bị expire
4. **Drill 9.4:** Setup cross-account pull (nếu có multiple AWS accounts)

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| ECS task không pull được image | Task Execution Role thiếu `ecr:GetDownloadUrlForLayer` | Thêm ECR read policy |
| Image scan fail | Scan on push chưa enable | Enable trong ECR repository settings |
| Storage cost cao | Lifecycle policy chưa setup | Setup expire untagged images |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| ECR storage | $0.10/GB/tháng | Lifecycle policy để expire old images |
| Data transfer | $0.09/GB ra internet | Dùng VPC endpoint cho ECR |

---

## Module 10: `efs` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| EFS File System | Encrypted (CMK), Bursting throughput |
| Access Points × 4 | prometheus-data, loki-data, tempo-data, grafana-data |
| Mount Targets × 3 | 1 per private subnet |
| Backup Policy | Enabled (integrated với AWS Backup) |
| Lifecycle Policy | Transition to IA after 30 days |

### 🎯 Learning Outcomes

- [ ] Thiết kế EFS cho Fargate (vì Fargate không có EBS)
- [ ] Cấu hình Access Points để isolate data per service
- [ ] Understand EFS throughput modes (Bursting vs Provisioned)
- [ ] Monitor EFS metrics (Client connections, Burst credit balance)

### 🧪 Hands-on Drills

1. **Drill 10.1:** Mount EFS vào EC2 instance, verify read/write
2. **Drill 10.2:** Test Access Points — verify isolation giữa services
3. **Drill 10.3:** Monitor burst credits, simulate burst exhaustion
4. **Drill 10.4:** Restore EFS từ AWS Backup

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Mount timeout | Security Group chưa mở port 2049 | Thêm NFS inbound rule |
| Throughput thấp | Burst credits exhausted | Switch to Provisioned throughput |
| Permission denied | Access Point chưa setup đúng | Review POSIX permissions |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| EFS Standard | $0.30/GB/tháng | Lifecycle policy để transition to IA |
| EFS IA | $0.016/GB/tháng | Auto-transition after 30 days |

---

## Module 11: `loadbalancer` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| ALB | Internet-facing, public subnets |
| Target Groups | web-ui (:8580), api-gateway (:5000), grafana (:3000) |
| Listener Rules | Host-based routing: app.*, api.*, grafana.* |
| ACM Certificate | *.bd-apa-coi.com (DNS validation) |
| Route53 Records | A records → ALB alias |
| WAF v2 (optional) | AWS Managed Rules: CommonRuleSet, SQLi, XSS, rate limiting |
| Access Logs | S3 bucket |

### 🎯 Learning Outcomes

- [ ] Thiết kế ALB với host-based routing
- [ ] Setup ACM certificate với DNS validation
- [ ] Cấu hình WAF v2 với managed rules
- [ ] Monitor ALB metrics (Target response time, 5xx count)

### 🧪 Hands-on Drills

1. **Drill 11.1:** Deploy ALB, verify host-based routing
2. **Drill 11.2:** Setup ACM certificate, verify HTTPS
3. **Drill 11.3:** Test WAF rules — simulate SQLi attack
4. **Drill 11.4:** Monitor ALB access logs trong S3 + Athena

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Target group unhealthy | Health check fail | Review health check path và interval |
| 502 Bad Gateway | Target service không respond | Check service logs, security groups |
| Certificate expired | ACM renewal fail | Review DNS validation records |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| ALB | $0.023/hr + $0.008/LCU-hour | Monitor LCU usage |
| WAF v2 | $5/web ACL/month + $1/rule/month | Disable khi không dùng |

---

## Module 12: `bastion` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| EC2 Instance | t3.micro, Amazon Linux 2023, mgmt subnet |
| SSM Agent | Pre-installed, no SSH key needed |
| User Data | Install PostgreSQL client, Redis CLI, Kafka tools |
| Instance Profile | Bastion IAM role |
| Security Group | Bastion SG |
| CloudWatch Agent | System metrics + memory/disk |

### 🎯 Learning Outcomes

- [ ] Setup Bastion với SSM Session Manager (no SSH)
- [ ] Understand SSM permissions model
- [ ] Install debugging tools (psql, redis-cli, kafka-console-consumer)
- [ ] Monitor Bastion health với CloudWatch Agent

### 🧪 Hands-on Drills

1. **Drill 12.1:** Connect vào Bastion qua SSM Session Manager
2. **Drill 12.2:** Test psql connection tới RDS từ Bastion
3. **Drill 12.3:** Monitor Bastion metrics trong CloudWatch
4. **Drill 12.4:** Setup SSH tunnel qua Bastion để access private resources

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| SSM không connect được | IAM role thiếu `ssm:StartSession` | Attach `AmazonSSMManagedInstanceCore` |
| psql không connect được RDS | Security Group của RDS chưa mở cho Bastion | Thêm inbound rule |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| EC2 (t3.micro) | $0.01/hr | Stop khi không dùng |

---

## Module 13: `cicd` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| OIDC Provider | Trust token.actions.githubusercontent.com |
| IAM Role: ecr-push | Push images to ECR |
| IAM Role: deploy | Update ECS services / kubectl apply |
| Trust Policy | Scoped to repo + branch (main only) |

### 🎯 Learning Outcomes

- [ ] Setup OIDC federation giữa GitHub Actions và AWS
- [ ] Understand OIDC trust policy (sub claim)
- [ ] Grant least-privilege permissions cho CI/CD
- [ ] Debug OIDC authentication failures

### 🧪 Hands-on Drills

1. **Drill 13.1:** Setup OIDC provider, verify trust policy
2. **Drill 13.2:** Push image từ GitHub Actions lên ECR
3. **Drill 13.3:** Deploy ECS task từ GitHub Actions
4. **Drill 13.4:** Debug OIDC auth failure — review CloudTrail logs

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| OIDC auth fail | Trust policy sai `sub` claim | Review `repo:owner/repo:ref:refs/heads/main` |
| ECR push fail | IAM role thiếu `ecr:PutImage` | Thêm ECR write policy |

### 💰 Cost & Optimization

- OIDC: **FREE**
- IAM: **FREE**

---

## Module 14: `backup` ✅

### 📋 Specification

| Resource | Config |
|----------|--------|
| Backup Vault (primary) | KMS encrypted, vault lock (governance) |
| Backup Vault (DR region) | Cross-region copy destination |
| Backup Plan — Daily | Daily 3AM UTC, retention 35 days |
| Backup Plan — Monthly | 1st of month, retention 365 days, cold storage after 30d |
| Backup Selection | Tag-based: `Backup = true` |
| Cross-Region Copy | Daily backup → DR region vault |
| Vault Lock | Governance mode |

### 🎯 Learning Outcomes

- [ ] Thiết kế centralized backup strategy với AWS Backup
- [ ] Cấu hình cross-region copy cho DR
- [ ] Understand vault lock (governance vs compliance mode)
- [ ] Restore từ backup và verify data integrity

### 🧪 Hands-on Drills

1. **Drill 14.1:** Trigger manual backup, verify trong AWS Backup console
2. **Drill 14.2:** Verify cross-region copy trong DR region
3. **Drill 14.3:** Restore RDS từ backup, verify data
4. **Drill 14.4:** Test vault lock — try delete backup (should fail)

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Backup fail | IAM role thiếu quyền | Attach `AWSBackupServiceRolePolicy` |
| Cross-region copy fail | DR region vault chưa tạo | Tạo vault trong DR region trước |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| AWS Backup | $0.05/GB/tháng | Transition to cold storage after 30 days |

---

## Module 15: `budgets` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| AWS Budget | Monthly cost budget ($50/month cho lab) |
| Budget Alert | 80% threshold → email notification |
| Cost Anomaly Monitor | Detect unusual spending patterns |
| SNS Topic | Shared topic cho budget + backup alerts |

### 🎯 Learning Outcomes

- [ ] Setup AWS Budgets với alert thresholds
- [ ] Configure Cost Anomaly Detection
- [ ] Understand AWS billing metrics trong CloudWatch
- [ ] Create billing alerts trong CloudWatch

### 🧪 Hands-on Drills

1. **Drill 15.1:** Setup budget, verify email alert khi threshold reached
2. **Drill 15.2:** Review Cost Anomaly Detection dashboard
3. **Drill 15.3:** Query billing metrics trong CloudWatch
4. **Drill 15.4:** Setup CloudWatch billing alarm

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Không nhận email alert | SNS subscription chưa confirm | Confirm subscription trong email |
| Cost Anomaly không detect | Monitor chưa setup | Tạo monitor trong Cost Management console |

### 💰 Cost & Optimization

- AWS Budgets: **FREE** (cho 2 budgets đầu tiên)
- Cost Anomaly Detection: **FREE**

---

## Module 16: `fis` 🆕 NEW (Critical for SRE Lab)

### 📋 Specification

| Resource | Config |
|----------|--------|
| FIS Experiment Template: AZ Failure | Stop all EC2 in AZ-a for 5m |
| FIS Experiment Template: Network Partition | Block traffic between AZ-a và AZ-b |
| FIS Experiment Template: RDS Failover | Trigger manual failover |
| FIS Experiment Template: S3 Outage | Deny S3 access cho Loki/Tempo backend |
| FIS Experiment Template: CPU Stress | Stress ECS tasks to 100% CPU |
| IAM Role for FIS | Least privilege, scoped to specific resources |
| Stop Condition | CloudWatch alarm → auto-stop experiment |
| CloudTrail Integration | Log all FIS actions for audit |

### 🎯 Learning Outcomes

- [ ] Thiết kế chaos experiments với AWS FIS
- [ ] Understand blast radius trong production
- [ ] Validate auto-scaling policies dưới failure conditions
- [ ] Test runbooks dưới real AWS failure conditions
- [ ] Setup stop conditions để prevent runaway experiments

### 🧪 Hands-on Drills

1. **Drill 16.1:** Run AZ failure experiment, observe app behavior
2. **Drill 16.2:** Run network partition experiment, measure cross-AZ latency
3. **Drill 16.3:** Trigger RDS failover via FIS, measure RTO
4. **Drill 16.4:** Simulate S3 outage, verify Loki/Tempo graceful degradation
5. **Drill 16.5:** CPU stress test, observe auto-scaling response

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| FIS experiment fail | IAM role thiếu quyền | Attach `FISExperimentRole` policy |
| Experiment không stop | Stop condition chưa setup | Thêm CloudWatch alarm làm stop condition |
| Resource không bị affect | Resource không match target | Review resource selection (tags, filters) |

### 💰 Cost & Optimization

- AWS FIS: **FREE** (cho 100 experiment-hours/tháng đầu tiên)
- Sau đó: $0.01/experiment-hour

---

## Module 17: `dr` 🔲

### 📋 Specification

| Resource | Config |
|----------|--------|
| VPC (DR region) | Mirror primary VPC topology (ap-southeast-1) |
| Subnets (DR region) | Public/Private/Data × 2 AZs |
| RDS Cross-Region Read Replica | Async replication từ primary |
| ALB (DR region) | Pre-provisioned, empty target groups |
| Route53 Failover Routing | Primary → active, DR → standby |
| Route53 Health Check | Monitor primary ALB endpoint |

### 🎯 Learning Outcomes

- [ ] Thiết kế Pilot Light DR strategy
- [ ] Setup cross-region RDS read replica
- [ ] Configure Route53 failover routing
- [ ] Execute DR drill và measure RTO

### 🧪 Hands-on Drills

1. **Drill 17.1:** Setup RDS cross-region replica, verify replication lag
2. **Drill 17.2:** Promote RDS replica thành standalone primary
3. **Drill 17.3:** Scale compute trong DR region từ 0 → desired
4. **Drill 17.4:** Switch Route53 DNS → DR ALB
5. **Drill 17.5:** Full DR drill — measure total RTO

### 🔧 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Replication lag cao | Network latency giữa regions | Review network connectivity |
| Route53 failover không trigger | Health check fail | Review health check configuration |
| DR region không scale | Auto-scaling policy chưa setup | Configure scaling policies |

### 💰 Cost & Optimization

| Resource | Cost | Optimization |
|----------|------|--------------|
| RDS replica | ~50% của primary | Stop replica khi không drill |
| Route53 health check | $0.75/health check/month | Disable khi không dùng |

---

## 📊 FinOps — Hidden Costs

### Những chi phí "ẩn" khiến bill x3 dự kiến

| Source | Cost | Mitigation |
|--------|------|------------|
| **Cross-AZ Data Transfer** | $0.01/GB | Keep traffic within AZ khi có thể |
| **NAT Gateway Processing** | $0.045/GB | Deploy VPC Endpoints cho S3/ECR/SSM |
| **VPC Endpoints hourly** | $0.01/hour/AZ | Chỉ tạo Interface endpoints cần thiết |
| **CloudWatch Logs ingestion** | $0.50/GB | Filter logs ở OTel Collector |
| **CloudWatch Metrics custom** | $0.30/metric/month | Dùng spanmetrics connector |
| **KMS API calls** | $1/million | Enable auto-rotation 1 năm/lần |
| **S3 PUT requests** | $0.005/1000 | Batch Loki/Tempo writes |
| **MSK minimum** | ~$5/day | Destroy cluster khi không dùng |

### Estimated Cost (when running)

| Resource | $/hr | $/day |
|----------|------|-------|
| NAT Gateway (×1) | $0.045 | $1.08 |
| MSK (2 brokers t3.small) | $0.21 | $5.04 |
| RDS (t3.micro, Multi-AZ) | $0.036 | $0.86 |
| ElastiCache (t3.micro) | $0.017 | $0.41 |
| ALB | $0.023 | $0.54 |
| ECS/EC2 (2× t3.medium) | $0.084 | $2.02 |
| EFS | ~$0.01 | ~$0.24 |
| Bastion (t3.micro) | $0.01 | $0.25 |
| **Total shared + 1 phase** | **~$0.44** | **~$10.5** |

💡 **Tip:** `terraform destroy` → $0/day. Apply sáng, destroy tối ≈ $10/ngày.

---

## 🚀 Thứ tự triển khai (Dependency-based)

### Step 1: Protect existing infrastructure
- `backup` (bảo vệ RDS đang chạy)
- **Lý do:** "Protect what you have before building more."

### Step 2: Hoàn tất Shared Data Layer
- `cache` → `streaming` → `opensearch` → `rds-proxy`
- **Lý do:** apps depend on Redis + Kafka + OpenSearch

### Step 3: Platform Services
- `ecr` → `efs` → `loadbalancer`
- **Lý do:** ECR cần trước khi push images. EFS cần cho Fargate observability. ALB cần cho traffic routing.

### Step 4: Operations
- `bastion` → `cicd` → `budgets` → `fis`
- **Lý do:** bastion cho admin access. CICD cho automated deployment. Budgets cho cost monitoring. FIS cho chaos engineering.

### Step 5: First Compute Phase
- `phase-8a` (ECS on EC2) → deploy apps → test → compare

### Step 6: Subsequent Compute Phases
- `phase-8b` → `phase-8c` → `phase-8d` (mỗi phase: deploy → learn → compare → destroy)

### Step 7: Disaster Recovery (sau khi app chạy ổn)
- `dr` (Pilot Light — VPC + RDS replica ở ap-southeast-1) → DR drill test

---

## 📚 OPA Policy Coverage

| Policy File | Validates |
|-------------|-----------|
| general.rego | Tagging, description requirements |
| network.rego | Subnet CIDR, public access restrictions |
| rds.rego | Encryption, backup, multi-AZ, public access |
| security_group.rego | Port ranges, CIDR validation, no 0.0.0.0/0 on data tier |
| iam.rego | No wildcard permissions, trust policy constraints |
| kms.rego | Key rotation, deletion window |
| s3.rego | Encryption, versioning, public access block |
| secrets.rego | Encryption, recovery window |
| logging.rego | Retention, encryption |
| vpc_endpoint.rego | Policy validation |
| elasticache.rego 🆕 | Encryption, auth token, multi-AZ |
| msk.rego 🆕 | Encryption, TLS, IAM auth |
| efs.rego 🆕 | Encryption, backup policy |
| alb.rego 🆕 | HTTPS only, access logging |
| backup.rego 🆕 | Vault lock, cross-region copy |

---

## 🎓 Learning Path (6-Week Curriculum)

### Week 1: Foundation
- Deploy `network`, `vpc-endpoints`, `security`
- Drills 1-3
- Interview: M1 (IaC Core)

### Week 2: Data Layer
- Deploy `database`, `cache`, `streaming`, `opensearch`, `rds-proxy`
- Drills 4-8
- Interview: M2 (Networking & Security)

### Week 3: Platform Services
- Deploy `ecr`, `efs`, `loadbalancer`, `bastion`
- Drills 9-12
- Interview: M3 (DR & Backup)

### Week 4: Operations
- Deploy `cicd`, `backup`, `budgets`, `fis`
- Drills 13-16
- Interview: M4 (FinOps)

### Week 5: Compute Phases
- Deploy `phase-8a` → `phase-8b` → `phase-8c` → `phase-8d`
- Compare pros/cons
- Interview: M5 (Chaos & FIS)

### Week 6: DR & Integration
- Deploy `dr`
- Full DR drill
- End-to-end integration test
- Write post-mortem

---

## 🤝 Contributing

Nếu bạn phát hiện gap trong playbook, đề xuất drill mới, hoặc muốn chia sẻ troubleshooting case từ lab của bạn, hãy mở Issue hoặc PR.

🛡️ **"Reliability is the most important feature."** — Google SRE Book