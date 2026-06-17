# 🔥 Chaos Exercises — Network Module Deep Dive

> Break it. Fix it. Understand it.
> All exercises target `modules/network/` and related module wiring.
> Future modules (security, database, backup) will have their own exercise files.

## Prerequisites

- All modules deployed via `terraform apply` in `environments/shared/`
- AWS CLI configured with appropriate permissions
- State backend (S3 + DynamoDB) verified working

## Network Module Resources Map

```
modules/network/
├── vpc.tf          → aws_vpc, aws_internet_gateway
├── subnets.tf      → aws_subnet (public, private, data, mgmt × 3 AZs)
├── nat.tf          → aws_eip, aws_nat_gateway
├── routing.tf      → aws_route_table, aws_route, aws_route_table_association
├── flow_logs.tf    → aws_flow_log (cloudwatch + s3), aws_cloudwatch_log_group,
│                     aws_kms_key, aws_iam_role, aws_iam_role_policy
├── nacl.tf         → aws_network_acl (commented out)
├── data.tf         → data.aws_availability_zones
├── outputs.tf      → 18 outputs
└── variables.tf    → 10 variables
```

## Rules

1. Read the **entire exercise** before executing any command
2. Verify **steady state** before injecting failure
3. **One failure at a time** — never stack experiments
4. **Document** what you observe vs what you expected

---

# Phase 1: Drift Detection (Safe — No Destruction)

> 🟢 **Risk: LOW** — You only modify existing resources, Terraform restores them.

## Ex 1.1: Console Drift — Route Table Tag

**File:** `routing.tf` | **Time:** 15 min | **Interview Q:** Q38

**Hypothesis:** Modifying a route table tag via Console will be detected by `terraform plan`.

> **Note:** This module uses separate `aws_route` resources (not inline `route {}` blocks inside `aws_route_table`). This means Terraform only tracks routes it created — manually added routes are invisible to `terraform plan`. Tag changes, however, are always detected because `aws_route_table` itself is in state.

**Steady State:**

```bash
# Find private route tables (tag Name contains "rt-private")
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=*rt-private*" \
  --query "RouteTables[*].{ID:RouteTableId,Name:Tags[?Key=='Name'].Value|[0]}" \
  --output table
```

**Inject:** In AWS Console → VPC → Route Tables → find any `*-rt-private-*` route table → Tags tab → edit the `Name` tag → change value to `hacked-private-rt`

**Observe:**

```bash
# 1. Inspect what Terraform "thinks" the resource looks like in state (State Inspection)
terraform state show 'module.network.aws_route_table.private["a"]'

# 2. Run plan to detect drift (Using exact project filter to avoid noise)
cd environments/shared
terraform plan 2>&1 | grep -C 3 "route_table"

# Question: Does Terraform detect the tag change? (Yes, tags are tracked in state)
# Question: What symbol does it show — `~` (update) or `-/+` (replace)? (~ update in-place)
# Question: If a Dev added a new VPC Peering route via Console, would Terraform delete it?
```

**Recover:**

```bash
terraform apply  # Terraform restores the original tag Name
```

**Learn:**

- [ ] Was the drift detected as `~` (update in-place)? (Yes — tags are always in-place)
- [ ] **Disjoint vs Inline Management:** Why does this module use separate `aws_route` resources instead of inline `route {}` blocks inside `aws_route_table`?
  - *Inline:* Terraform assumes "sole ownership". If someone adds a route via Console, Terraform will DELETE it on next apply.
  - *Disjoint (`aws_route`):* Terraform only manages routes it created. It "coexists" with routes added by other teams (e.g., VPC Peering, Transit Gateway). This is the Enterprise Best Practice.
- [ ] How to automate drift detection in CI/CD? (`terraform plan -detailed-exitcode` returns exit code 2 when drift exists, useful for GitHub Actions/GitLab CI pipelines).

**Team-size perspective:**

- [ ] **Team 3–5:** Who detects this drift? (Engineer notices during next `plan`)
- [ ] **Team 10–20:** Scheduled drift detection in CI (e.g., nightly `plan` → Slack alert)
- [ ] **Team 50+:** AWS Config rule + auto-remediation via SSM

---

## Ex 1.2: Console Drift — VPC DNS Settings

**File:** `vpc.tf` | **Time:** 10 min | **Interview Q:** Q38

**Hypothesis:** Disabling DNS hostnames on the VPC will break service discovery. Terraform will detect and restore it.

**Inject:** Console → VPC → select VPC → Actions → Edit DNS hostnames → **Disable**

**Observe:**

```bash
terraform plan 2>&1 | grep -C 3 "dns"
# Question: What attribute changed?
# Question: What downstream impact does disabling DNS hostnames have?
# (Hint: RDS endpoint resolution, VPC endpoint private DNS)
```

**Recover:**

```bash
terraform apply
```

**Learn:**

- [ ] Was the drift detected as `~` (update in-place)? (Yes, VPC attributes update in-place)
- [ ] **Downstream Impact (The Hidden Blast Radius):** Disabling DNS hostnames/support doesn't just break EC2 hostnames. It breaks the **AmazonProvidedDNS** (`169.254.169.253`).
  - *AWS Managed Services:* RDS, MSK (Kafka), OpenSearch endpoints will fail to resolve.
  - *VPC Interface Endpoints:* The "Private DNS" feature (which resolves `s3.ap-southeast-2.amazonaws.com` to the VPC endpoint's private IP) **REQUIRES** both DNS flags to be enabled. Disabling them forces S3/DynamoDB traffic out to the Public Internet (causing NAT Gateway data transfer costs or outright failures).
  - *Internal AWS Calls:* Services like Secrets Manager, SSM, or CloudWatch Logs rely on internal DNS. The Shipping Worker will fail to fetch DB passwords or push logs.

---

## Ex 1.3: Console Drift — Flow Log Traffic Type

**File:** `flow_logs.tf` | **Time:** 10 min

**Hypothesis:** You cannot change a flow log's traffic type in-place — AWS requires delete + recreate.

**Observe only** (no Console change needed):

```bash
# Change traffic type in main.tf
# flow_logs_cloudwatch_traffic_type = "ALL"  (was "REJECT")
terraform plan 2>&1 | grep -B 2 -A 5 "flow_log"
# Question: Is it `~` update or `-/+` forces replacement?
# Revert main.tf after observing
```

**Learn:**

- [ ] **Immutable Infrastructure Attribute:** `traffic_type` is a *ForceNew* attribute. The AWS API does not support in-place updates for this specific field.
- [ ] **The Compliance Gap (Forensic Blindspot):** When Terraform executes `-/+ forces replacement`, it **Deletes** the old flow log and **Creates** a new one. During that 1-2 minute gap, VPC Flow Logs are completely blind. If a breach occurs exactly then, you have no forensic data.
- [ ] **Dual-Destination ROI:** This is exactly why Compliance Policies (SOC2, PCI-DSS) mandate Dual-Destination (CloudWatch + S3) as designed in our `flow_logs.tf`. S3 acts as an "immutable fallback" that is completely decoupled from the CloudWatch Log Group's lifecycle.
- [ ] How does the CHANGELOG document this as a breaking change? (Any change to `traffic_type` requires a maintenance window acknowledgment due to the forensic blindspot).

---

# Phase 2: Resource Deletion & Recovery (Medium Risk)

> 🟡 **Risk: MEDIUM** — Resources are deleted but contain no persistent data. Terraform re-creates them on next apply. Expect brief connectivity impact.

---

## Ex 2.1: Delete NAT Gateway

**File:** `nat.tf` | **Time:** 20 min | **Interview Q:** Q48

**Hypothesis:** Deleting NAT Gateway causes private subnets to lose internet. Terraform recreates it.

**Steady State:**

```bash
NAT_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" --output text)
echo "NAT: $NAT_ID"
```

**Inject:**

```bash
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID
# Wait 30 seconds for state to change to "deleting"
```

**Observe:**

```bash
# 1. Check Route Table status in AWS (Notice the "blackhole" state)
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=*rt-private*" \
  --query "RouteTables[*].Routes[?DestinationCidrBlock=='0.0.0.0/0'].{State:State,NatGatewayId:NatGatewayId}" \
  --output table

# 2. Check EIP status (It is NOT deleted, just disassociated)
aws ec2 describe-addresses --filters "Name=tag:Name,Values=*nat-eip*" \
  --query "Addresses[*].{PublicIp:PublicIp,InstanceId:InstanceId,AssociationId:AssociationId}"

# 3. Run Terraform Plan
terraform plan 2>&1 | grep -E "(nat_gateway|route|eip)"
# Question: Does Terraform want to recreate the EIP? (No, EIP still exists in AWS)
# Question: What happens to the `aws_route`? (It will show `~ update in-place` to point to the NEW NAT Gateway ID)
```

**Recover:**

```bash
terraform apply
# Time it: NAT Gateway creation takes ~2-3 minutes. During this time, Private Subnet has NO internet.
```

**Learn:**

- [ ] **The Blackhole Effect:** When NAT GW is deleted out-of-band, AWS doesn't delete the route. It marks the route state as `blackhole`. Traffic from Private Subnet hits the route table and is silently dropped.
- [ ] **EIP Orphan & FinOps:** Deleting NAT GW does NOT delete the EIP. The EIP becomes "unassociated". Since Feb 2024, AWS charges for ALL public IPv4 addresses (~$3.6/month). Terraform will re-associate the existing EIP with the new NAT GW, preventing EIP recreation cost.
- [ ] **E-commerce Blast Radius:** What actually breaks?
  - ECS/EKS nodes in Private Subnet cannot pull images from public DockerHub/ECR.
  - Shipping Worker cannot call external Payment Gateways (Stripe/PayPal).
  - Notification Worker cannot send webhooks/emails via external SMTP.
- [ ] **Monitoring:** What CloudWatch metric detects this? (`NatGateway` → `ErrorPortAllocation` or `PacketsDropCount`).

**Team-size perspective:**

- [ ] **Team 3–5:** Manual detection — engineer notices connectivity issues → checks NAT → runs `terraform apply`
- [ ] **Team 10–20:** CloudWatch alarm on `NatGateway` → `ErrorPortAllocation` metric → PagerDuty → on-call runs apply
- [ ] **Team 50+:** EventBridge rule detects `DeleteNatGateway` API call → Lambda triggers automated `terraform apply` or creates incident ticket
- [ ] **Cost question:** 1 NAT ($32/mo) vs 3 NATs ($96/mo) — at what traffic level does HA justify the cost?

---

## Ex 2.2: Delete Internet Gateway

**File:** `vpc.tf` | **Time:** 15 min

**Hypothesis:** IGW deletion breaks ALL public subnet routing. Terraform detects and recreates it.

> ⚠️ This will break NAT Gateway (it needs IGW). Expect cascade.

**Inject:**

```bash
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query "InternetGateways[0].InternetGatewayId" --output text)

# Must detach before deleting
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID \
  --vpc-id $(terraform output -raw vpc_id)
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
```

**Observe:**

```bash
terraform plan 2>&1 | grep -c "will be created"
# Question: How many resources affected? (IGW + routes pointing to IGW)
# Question: Is NAT Gateway also affected? (Yes — NAT needs IGW for internet)
```

**Recover:**

```bash
terraform apply
```

**Learn:**

- [ ] **The Detach Prerequisite:** AWS API strictly forbids deleting an IGW while it is attached to a VPC. You MUST `detach-internet-gateway` first. Terraform handles this automatically via its dependency graph, but manual CLI requires 2 steps.
- [ ] **Cascade Failure (The Domino Effect):**
  1. IGW deleted → Public Subnet loses internet (ALB goes dark, Web UI unreachable).
  2. NAT Gateway relies on IGW for its own outbound path → NAT loses internet.
  3. Private Subnet relies on NAT → Private Subnet loses internet.
  
  *Result: Total VPC internet blackout (both Inbound and Outbound).*
- [ ] **Blast Radius:** IGW deletion affects `aws_internet_gateway` + `aws_route.public_internet` (becomes blackhole) + implicitly breaks NAT Gateway.
- [ ] **Security & Auditing:** This is a Severity-1 Incident. In Production, `ec2:DeleteInternetGateway` and `ec2:DetachInternetGateway` should be DENIED by SCP (Service Control Policy) for all IAM roles except the Break-Glass/Incident-Response role. CloudTrail is your only way to find out WHO ran the command.

**Team-size perspective:**

- [ ] **All teams:** IGW deletion = total VPC internet outage. This is a severity-1 incident at any team size.
- [ ] **Team 10+:** AWS CloudTrail logs who called `DeleteInternetGateway` — essential for post-mortem
- [ ] **Team 50+:** SCP (Service Control Policy) should DENY `ec2:DeleteInternetGateway` for all accounts except break-glass roles

---

## Ex 2.3: Delete CloudWatch Log Group (Flow Logs)

**File:** `flow_logs.tf` | **Time:** 15 min

**Hypothesis:** Deleting the log group causes flow log delivery to fail silently. Historical logs are permanently lost.

**Steady State:**

```bash
LOG_GROUP="/vpc/flow-logs"
aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP \
  --query "logGroups[0].{Name:logGroupName,Stored:storedBytes,Retention:retentionInDays}"
```

**Inject:**

```bash
aws logs delete-log-group --log-group-name "$(aws logs describe-log-groups \
  --log-group-name-prefix '/vpc/flow-logs' \
  --query 'logGroups[0].logGroupName' --output text)"
```

**Observe:**

```bash
terraform plan 2>&1 | grep -C 3 "log_group"
# Question: Does Terraform want to recreate just the log group or the flow log too?
# Question: Are the old logs recoverable? (No — CloudWatch logs are gone permanently)
```

**Verify dual-destination resilience:**

```bash
# CloudWatch logs are GONE. But S3 flow logs should be INTACT:
BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name,'flow-logs')].Name" --output text)

# Check S3 still receiving new logs (look for recent files)
aws s3 ls s3://$BUCKET/AWSLogs/ --recursive | tail -5

# Query via Athena to prove S3 data is independent
# (requires logging-flow-logs module deployed)
# This is the ROI of dual-destination architecture.
```

**Recover:**

```bash
terraform apply
```

**Learn:**

- [ ] **The Silent Failure:** When the Log Group is deleted, the `aws_flow_log` resource in AWS is NOT deleted. It remains "Active" but its delivery status becomes `FAILED` because the destination ARN no longer exists. Terraform will recreate the Log Group, but you lose all historical logs in CloudWatch.
- [ ] **Dual-Destination ROI:** This exercise proves why we designed S3 as a secondary destination in `flow_logs.tf`. CloudWatch is ephemeral (for real-time alerting), S3 is immutable (for forensic/compliance). Hackers often delete CloudWatch logs to cover their tracks, but they rarely notice or cannot delete the centralized S3 log archive in a separate AWS Account.
- [ ] **Production Best Practice (`prevent_destroy`):** In a real Production module, stateful resources (Log Groups, S3 Buckets, RDS) MUST have a lifecycle rule to prevent accidental deletion:

```hcl
  resource "aws_cloudwatch_log_group" "flow_logs" {
    # ...
    lifecycle {
      prevent_destroy = true
    }
  }
```

  If this rule exists, `terraform destroy` or CLI deletion will be blocked, saving you from a resume-generating event.

**Team-size perspective:**

- [ ] **Team 3–5:** CloudWatch loss is acceptable if S3 archive exists for forensics
- [ ] **Team 10–20:** Alert on missing log groups via AWS Config rule `cloudwatch-log-group-encrypted`
- [ ] **Team 50+:** Centralized log account — log groups are in a separate account that app teams cannot delete

---

## Ex 2.4: Targeted Destroy Cascade — Observe Only

**Time:** 10 min | **Interview Q:** Q34 (blast radius isolation)

**Hypothesis:** `terraform destroy -target=module.network` will show cascade destruction of ALL dependent modules (vpc-endpoints, security, database) because they reference `module.network` outputs.

> ⚠️ **DO NOT APPLY** — observe plan output only.

**Observe:**

```bash
cd environments/shared

# Preview the blast radius
terraform plan -destroy -target=module.network 2>&1 | tail -40

# Count affected resources
terraform plan -destroy -target=module.network 2>&1 | grep -c "will be destroyed"

# Question: How many resources from OTHER modules are included?
# Question: Is the RDS instance in the destroy list? (Yes — depends on vpc_id)
# Question: Is the S3 flow log bucket in the destroy list? (No — separate module lifecycle!)
```

**Learn:**

- [ ] **The Dependency Graph:** Terraform reads `main.tf` and builds a DAG (Directed Acyclic Graph).
  - `module.network` outputs `vpc_id` and `subnet_ids`.
  - `module.security` and `module.database` consume these outputs.
  - Therefore, destroying Network FORCES Terraform to destroy Security and Database to maintain a valid state.
- [ ] **State Isolation Proof:** Notice that `module.logging-flow-logs` (S3 Bucket) is NOT in the destroy list. Why? Because Network depends on Logging (for the bucket ARN), not the other way around. The S3 bucket survives the VPC destruction. This is the core value of modular design and state isolation.
- [ ] **The Danger of `-target`:** Using `terraform destroy -target=...` bypasses Terraform's safety checks. In CI/CD pipelines, `-target` should be strictly forbidden (via OPA/Sentinel policies) because it can leave the AWS environment in a half-broken, inconsistent state that the next `terraform apply` might struggle to reconcile.
- [ ] **Architecture Insight:** If you want to destroy the VPC without destroying the Database (e.g., migrating to a new VPC), you CANNOT do it in one step. You must first decouple the dependencies, or use `terraform state mv` / `terraform state rm` to manage the lifecycle manually.

**Team-size perspective:**

- [ ] **Team 3–5:** `-target` is acceptable for experienced engineers in non-prod
- [ ] **Team 10–20:** CI/CD pipeline should REJECT any plan containing `-target` flag
- [ ] **Team 50+:** Separate state files per module — destroying network state CANNOT cascade to database state
- [ ] **Architecture insight:** This exercise proves the value of state isolation (Q27, Q34)

---

# Phase 3: State Management (Critical Skill)

> 🟡 **Risk: MEDIUM** — AWS resources are untouched. Only Terraform state is manipulated.
> Always back up state before starting.

---

## Ex 3.1: Force-Unlock State Lock

**Time:** 15 min | **Interview Q:** Q36

> ⚠️ **Architecture Catch:** Our `backend.tf` uses `use_lockfile = true` (Terraform 1.10+ S3 native locking). It does **NOT** use DynamoDB for locking anymore! Terraform creates a `.tflock` file in the S3 bucket.

**Inject:**

```bash
# Simulate a stuck lock by uploading a fake .tflock file to S3
STATE_BUCKET="obs-terraform-state-730335245469" # Adjust to your bucket
cat <<EOF > /tmp/fake.tflock
{"ID":"fake-lock-id-123","Operation":"OperationTypeApply","Who":"ghost","Version":"1.10.0"}
EOF
aws s3 cp /tmp/fake.tflock s3://$STATE_BUCKET/shared/terraform.tfstate.tflock
```

**Observe:**

```bash
cd environments/shared
terraform plan
# Should fail with "Error acquiring state lock"
# Notice the error message mentions the S3 .tflock file, not DynamoDB.
```

**Recover:**

```bash
# Option A: Use Terraform's built-in force-unlock (reads the ID from the error message)
terraform force-unlock fake-lock-id-123

# Option B: Manually delete the lock file via AWS CLI (if force-unlock fails)
aws s3 rm s3://$STATE_BUCKET/shared/terraform.tfstate.tflock
```

**Learn:**

- [ ] **S3 Native Locking vs DynamoDB:** TF 1.10+ replaced DynamoDB with S3 `.tflock` files. This reduces infrastructure footprint (no DynamoDB table to manage/pay for) and relies on S3's strong consistency.
- [ ] What if a REAL apply is running when you force-unlock? (State corruption risk — two applies writing to state simultaneously, causing serial number conflicts).
- [ ] How to verify no one is running apply? (Check CI/CD pipeline status, ask team, check S3 bucket CloudTrail events for `PutObject` on `.tflock`).

---

## Ex 3.2: State Remove + Import (Flow Log)

**Time:** 20 min | **Interview Q:** Q39

**Steady State:**

```bash
cd environments/shared
terraform state pull > /tmp/state-backup-ex32.json
terraform state list | grep "flow_log"
```

**Inject:**

```bash
terraform state rm 'module.network.aws_flow_log.cloudwatch["vpc"]'
```

**Observe:**

```bash
terraform plan 2>&1 | grep -C 3 "flow_log"
# Terraform wants to CREATE a new flow log — but the old one still exists in AWS!
```

**Recover (Approach A: Imperative CLI — The "Old" Way):**

```bash
FLOW_LOG_ID=$(aws ec2 describe-flow-logs \
  --filter "Name=log-destination-type,Values=cloud-watch-logs" \
  --query "FlowLogs[0].FlowLogId" --output text)
terraform import 'module.network.aws_flow_log.cloudwatch["vpc"]' $FLOW_LOG_ID
```

**Recover (Approach B: Declarative `import` block — Terraform 1.5+ BEST PRACTICE):**

```hcl
# 1. Add this block temporarily to main.tf or a migration.tf file
import {
  to = module.network.aws_flow_log.cloudwatch["vpc"]
  id = "fl-xxxxxxxxxxxxxxxxx" # Replace with actual Flow Log ID from AWS Console
}
# 2. Run terraform plan -> It will show "Import" instead of "Create"
# 3. Run terraform apply -> State is updated safely
# 4. DELETE the import block after successful apply.
```

**Learn:**

- [ ] What if you applied without importing? (Terraform creates a DUPLICATE flow log. AWS allows multiple flow logs on the same VPC, causing duplicate logs in CloudWatch and doubling the cost).
- [ ] **The GitOps Shift:** Why is the `import {}` block (Approach B) preferred over `terraform import` CLI for teams?
  - *CLI:* Imperative "ClickOps" — changes state locally without a PR. Dev/Staging/Prod environments will drift.
  - *Import Block:* Declarative, reviewable in Pull Request, and reproducible across all environments via CI/CD.
- [ ] Prevention: who should have permission to run `terraform state rm`? (Only Break-Glass roles. Normal devs should use `import` blocks via PRs).

**Team-size perspective:**

- [ ] **Team 3–5:** `state rm` is a known risk — all engineers should understand `import`. Document the recovery in a runbook.
- [ ] **Team 10–20:** Restrict `state` subcommands to senior engineers. CI/CD pipeline is the only path to `apply` — no local state access.
- [ ] **Team 50+:** State bucket has MFA Delete enabled. `state rm` requires break-glass IAM role with CloudTrail audit. Automated alert on any `state rm` operation.

---

## Ex 3.3: State Corruption + S3 Versioning Recovery

**Time:** 25 min | **Interview Q:** Q49

**Steady State:**

```bash
STATE_BUCKET="obs-lab-terraform-state"  # adjust to your bucket
cd environments/shared
terraform state list | wc -l  # note count: ___
```

**Inject:**

```bash
echo '{"version":4,"resources":[]}' > /tmp/corrupt.json
aws s3 cp /tmp/corrupt.json s3://$STATE_BUCKET/shared/terraform.tfstate
```

**Observe:**

```bash
terraform state list    # Empty! All resources "lost"
terraform plan          # Wants to CREATE everything — DO NOT APPLY!
```

**Recover:**

```bash
# 1. List state file versions
aws s3api list-object-versions --bucket $STATE_BUCKET \
  --prefix "shared/terraform.tfstate" \
  --query "Versions[].{Version:VersionId,Date:LastModified,Size:Size}" \
  --output table

# 2. Restore last good version
GOOD_VERSION="<pick-version-before-corrupt>"
aws s3api get-object --bucket $STATE_BUCKET \
  --key "shared/terraform.tfstate" \
  --version-id $GOOD_VERSION /tmp/good-state.json

# 3. Push the restored state back to S3 (Overwrite the corrupted one)
aws s3 cp /tmp/good-state.json s3://$STATE_BUCKET/shared/terraform.tfstate

# 4. Verify
terraform state list | wc -l  # Should match original count
terraform plan                 # Should show "No changes"
```

**Learn:**

- [ ] **State Lineage & Serial:** How does Terraform know the restored file is valid? Every state file has a `lineage` (unique UUID generated on creation) and a `serial` (increments on every apply). If you manually edit a state file and push it, Terraform will reject it unless you use `terraform state push -force` to override the serial check. S3 Versioning bypasses this by restoring the exact original bytes.
- [ ] What if S3 versioning was NOT enabled? (Unrecoverable without an external backup. This is why `bootstrap` module MUST enforce versioning).
- [ ] Team 50+: Terraform Cloud/Enterprise has a "State Version History" UI with a 1-click "Rollback" button, eliminating the need for AWS CLI gymnastics.

**Team-size perspective:**

- [ ] **Team 3–5:** S3 versioning is your only safety net. Recovery is manual — know the AWS CLI commands by heart.
- [ ] **Team 10–20:** Automate state backup to a separate S3 bucket (cross-account). Add CI step: `terraform state list | wc -l` as a health check before every apply.
- [ ] **Team 50+:** Terraform Cloud/Enterprise with built-in state versioning and rollback UI. State bucket has Object Lock (compliance mode) to prevent even admins from deleting versions.

---

## Ex 3.4: Rename Resource — `moved` Block vs `state mv`

**Time:** 15 min | **Interview Q:** Q12, Q35

**Observe only** (do not apply):

```bash
# Our CHANGELOG documents: aws_flow_log.this → aws_flow_log.cloudwatch
# This was a rename. Without migration, Terraform would:
#   - Delete aws_flow_log.this
#   - Create aws_flow_log.cloudwatch
# = 1-2 minute flow log gap

# Two migration approaches:
# A) terraform state mv (imperative, done before code change)
# B) moved { } block (declarative, Terraform 1.1+, done in code)
```

```hcl
# Approach B example (preferred for teams):
moved {
  from = aws_flow_log.this["vpc"]
  to   = aws_flow_log.cloudwatch["vpc"]
}
# terraform plan → shows "has moved" instead of destroy+create
```

**Learn:**

- [ ] **Declarative vs Imperative:** `moved {}` block is Declarative (GitOps). `state mv` is Imperative (ClickOps).
- [ ] In a CI/CD pipeline, if you use `state mv` locally, the pipeline's state will drift from your local state. The next `terraform apply` in CI/CD will try to recreate the resource and fail. `moved {}` block is checked into Git, so the CI/CD pipeline understands the rename and applies it safely to all environments.

---

## Ex 3.5: Module Rename — State Conflict Recovery (Real Incident)

**Time:** 20 min | **Interview Q:** Q12, Q35, Q39

> ⚠️ This exercise is based on a **real incident** that occurred in this project when `module "logging"` was renamed to `module "logging-flow-logs"` without proper state migration.

**Background:**

Renaming a module in `main.tf` without a `moved` block or `state mv` causes Terraform to:

1. Schedule **destruction** of all resources under the old module name
2. Schedule **creation** of all resources under the new module name
3. If apply runs → S3 bucket destroyed + recreated → **all flow log archives permanently lost**

**Scenario:**

```hcl
# Before (in main.tf):
module "logging" {
  source = "../../modules/logging-flow-logs"
  ...
}

# After (renamed without migration):
module "logging-flow-logs" {
  source = "../../modules/logging-flow-logs"
  ...
}
```

**What happened:**

1. `terraform apply -target=module.network` → error:

```
   Error: creating S3 Bucket: BucketAlreadyOwnedByYou (409)
```

   State had resources at BOTH `module.logging` and `module.logging-flow-logs`.

2. Adding a `moved` block failed:

```
   Warning: Unresolved resource instance address changes
   module.logging could not move to module.logging-flow-logs
```

   Because `module.logging-flow-logs` already had partial data sources in state.

**Recovery (what we actually did):**

```bash
# 1. Check state — confirm both module names exist
terraform state list | grep -E "module\.(logging|logging-flow-logs)"
# module.logging.aws_s3_bucket.flow_logs                     ← old (has the real bucket)
# module.logging-flow-logs.data.aws_caller_identity.current  ← new (only data sources)

# 2. Remove old module entry from state (bucket stays in AWS)
terraform state rm 'module.logging.aws_s3_bucket.flow_logs'

# 3. Import existing bucket into new module name
terraform import 'module.logging-flow-logs.aws_s3_bucket.flow_logs' \
  'obs-flow-logs-730335245469'

# 4. Verify
terraform plan  # Should show no destroy/create for S3 bucket
```

**Prevention — correct approaches:**

```hcl
# Approach A: moved block (BEFORE any apply - Safest for CI/CD)
moved {
  from = module.logging
  to   = module.logging-flow-logs
}
```

```bash
# Approach B: state mv (Imperative - ONLY for local emergency fixes)
terraform state mv 'module.logging' 'module.logging-flow-logs'
```

**Learn:**

- [ ] Why did `moved` block fail in our real incident? (Because a partial `apply` had already created data sources under the NEW module name in the state file. Terraform's `moved` block refuses to overwrite existing state addresses to prevent data loss).
- [ ] **The Golden Rule of State:** NEVER rename modules or resources directly in `main.tf` without preparing a migration strategy (`moved` block) FIRST.
- [ ] Team 10-20: CI/CD pipeline should have an OPA/Sentinel policy that scans PRs for module renames and forces the author to include a corresponding `moved {}` block.

**Team-size perspective:**

- [ ] **Team 3–5:** Always run `terraform plan` and **read the output** before apply. If you see `destroy` on S3/RDS → STOP.
- [ ] **Team 10–20:** CI/CD pipeline should have a **guard rule**: block apply if plan contains `destroy` on stateful resources (S3 buckets, RDS instances, KMS keys). Example OPA rule:

```rego
  deny[msg] {
    input.resource_changes[_].type == "aws_s3_bucket"
    input.resource_changes[_].change.actions[_] == "delete"
    msg := "Destroying S3 bucket requires manual approval"
  }
```

- [ ] **Team 50+:** Separate state files per module layer. Renaming a module in the "logging" state cannot cascade to "network" state. Combined with SCP denying `s3:DeleteBucket` except break-glass roles.

---

# Phase 4: KMS & Encryption (Advanced)

> 🔴 **Risk: HIGH** — KMS key deletion can make encrypted data permanently unreadable.
> Understand the recovery window before proceeding.

---

## Ex 4.1: KMS Key — Schedule Deletion & Cancel

**File:** `flow_logs.tf` (KMS section) | **Time:** 15 min

**Steady State:**
```bash
KMS_KEY_ID=$(aws kms list-aliases \
  --query "Aliases[?contains(AliasName,'flow-logs')].TargetKeyId" --output text)
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{State:KeyState,Rotation:KeyRotationStatus}"
```

**Inject:**
```bash
aws kms schedule-key-deletion --key-id $KMS_KEY_ID --pending-window-in-days 7
```

**Observe:**
```bash
# Key state is now "PendingDeletion"
aws kms describe-key --key-id $KMS_KEY_ID --query "KeyMetadata.KeyState"

# Can you read encrypted flow logs?
aws logs get-log-events --log-group-name "/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/vpc/flow-logs' \
    --query 'logStreams[0].logStreamName' --output text)" \
  --limit 1
# Expected: AccessDeniedException
```

**Recover:**
```bash
aws kms cancel-key-deletion --key-id $KMS_KEY_ID
aws kms enable-key --key-id $KMS_KEY_ID
# Logs should be readable again
```

**Learn:**
- [ ] If the 7-day window expires → key is **permanently deleted**, logs unreadable forever
- [ ] Why does our module set `deletion_window_in_days = 14`? (More time to catch mistakes)
- [ ] What CloudWatch alarm would detect "KMS key pending deletion"?
- [ ] S3 flow logs use a DIFFERENT KMS key (in logging module) — are they affected? (No)

---

# Progression Schedule

| Week | Exercises | Focus | Time |
|------|-----------|-------|------|
| 1 | Ex 1.1, 1.2, 1.3 | Drift detection — safe, build confidence | 35 min |
| 2 | Ex 2.1, 2.2 | NAT/IGW deletion — blast radius + team-size response | 35 min |
| 3 | Ex 2.3, 2.4 | Dual-destination proof + cascade analysis | 25 min |
| 4 | Ex 3.1, 3.2 | State locking + state rm/import | 35 min |
| 5 | Ex 3.3, 3.4, 3.5 | State corruption + rename migration + real incident | 55 min |
| 6 | Ex 4.1 | KMS lifecycle — highest risk exercise | 15 min |

---

# Post-Exercise Template

```markdown
## Exercise X.X: [Title]
**Date:** YYYY-MM-DD | **Duration:** XX min

### What happened
- [Actual behavior observed]

### What surprised me
- [Unexpected outcomes]

### Production implications
- [What would this mean at team size 5/20/50?]

### Action items
- [ ] [Monitoring/prevention improvement to implement]
```

---

# What's Next

After completing all network exercises:
- `chaos-exercises-security.md` — Security groups, IAM roles, key pair
- `chaos-exercises-database.md` — RDS, Secrets Manager, backup/restore
- `chaos-exercises-backup.md` — Vault lock, cross-region, compliance
