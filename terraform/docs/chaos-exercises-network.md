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

---

# Phase 4: KMS & Encryption (Advanced)

> 🔴 **Risk: HIGH** — KMS key deletion can make encrypted data permanently unreadable.
> Understand the recovery window before proceeding.

---

## Exercise 4.1: KMS Key — Schedule Deletion & Cancel

**File:** `flow_logs.tf` (KMS section) | **Time:** 25 min | **Interview Q:** Q48, Q52

### Hypothesis

Scheduling KMS key deletion will prevent CloudWatch Logs from decrypting flow logs, but:
- S3 flow logs remain unaffected (different key in logging module)
- Logs written BEFORE deletion remain readable (data key cached by CloudWatch)
- New logs written AFTER deletion will fail to deliver

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Permanent data loss if 7-day window expires | Low | Critical | Set calendar reminder, use 14-day window |
| Production logs become unreadable | Medium | High | Test in lab only, document recovery procedure |
| Cross-region backup affected | Low | Medium | S3 logs use different key |
| Terraform state drift | High | Low | Run `terraform plan` after cancel |

### Steady State

```bash
# 1. Find the KMS key ID
KMS_KEY_ID=$(aws kms list-aliases \
  --query "Aliases[?contains(AliasName,'flow-logs')].TargetKeyId" --output text)
echo "KMS Key ID: $KMS_KEY_ID"

# 2. Verify key state and rotation
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{State:KeyState,Rotation:EnabledKeyRotation,CreationDate:CreationDate}" \
  --output table

# 3. Verify flow logs are currently working
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flow-logs" \
  --query "logGroups[0].{Name:logGroupName,KmsKeyId:kmsKeyId,StoredBytes:storedBytes}" \
  --output table

# 4. Check recent log events (should have data)
aws logs get-log-events \
  --log-group-name "/aws/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/aws/vpc/flow-logs' \
    --query 'logStreams[0].logStreamName' --output text)" \
  --limit 3 \
  --query "events[*].{timestamp:timestamp,message:message}" \
  --output table
```

### Inject

```bash
# Schedule key deletion with 7-day pending window
aws kms schedule-key-deletion \
  --key-id $KMS_KEY_ID \
  --pending-window-in-days 7

# Verify state changed
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{State:KeyState,DeletionDate:DeletionDate}" \
  --output table
# Expected: State = "PendingDeletion", DeletionDate = 7 days from now
```

### Observe (Multiple Dimensions)

**Dimension 1: Key State**

```bash
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.KeyState" --output text
# Expected: "PendingDeletion"

# Question: Can you still use the key for encryption?
aws kms encrypt --key-id $KMS_KEY_ID --plaintext "test" 2>&1 | head -5
# Expected: KMSInvalidStateException - key is pending deletion
```

**Dimension 2: CloudWatch Logs Delivery**

```bash
# Wait 5 minutes for new flow log events to be generated
sleep 300

# Check if new logs are being delivered
aws logs describe-log-streams \
  --log-group-name "/aws/vpc/flow-logs" \
  --order-by LastEventTime --descending \
  --query "logStreams[0:3].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table

# Question: Are new log streams being created? (No — delivery fails silently)
# Question: What does CloudWatch Flow Logs delivery status show?

# Check delivery status via CloudWatch Metrics
aws cloudwatch get-metric-statistics \
  --namespace "AWS/Logs" \
  --metric-name "DeliveryThrottling" \
  --dimensions Name=LogGroupName,Value="/aws/vpc/flow-logs" \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --query "Datapoints[*].{Time:Timestamp,Throttled:Sum}" \
  --output table
```

**Dimension 3: Historical Logs (The Surprising Part)**

```bash
# Try to read logs that were written BEFORE deletion
aws logs get-log-events \
  --log-group-name "/aws/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/aws/vpc/flow-logs' \
    --order-by LastEventTime --descending \
    --query 'logStreams[-1].logStreamName' --output text)" \
  --limit 5 \
  --query "events[*].message" \
  --output text

# Question: Can you still read old logs? (YES — CloudWatch caches data keys)
# Question: Why? (Envelope encryption — data key was decrypted and cached in memory)
```

**Dimension 4: S3 Flow Logs (Different Key)**

```bash
# S3 flow logs use a DIFFERENT KMS key (managed by logging-flow-logs module)
S3_BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name,'flow-logs')].Name" --output text)

# Check if S3 still receiving logs
aws s3 ls s3://$S3_BUCKET/AWSLogs/ --recursive | tail -5

# Question: Are S3 logs affected? (NO — different KMS key)
# Question: This proves the value of dual-destination architecture
```

**Dimension 5: Terraform Drift**

```bash
cd environments/shared
terraform plan 2>&1 | grep -C 5 "kms_key"

# Question: Does Terraform detect the key is pending deletion?
# (No — Terraform only tracks key existence, not state)
# Question: How would you add drift detection for KMS key state?
```

### Recover

```bash
# Cancel the scheduled deletion
aws kms cancel-key-deletion --key-id $KMS_KEY_ID

# Re-enable the key (it's automatically disabled when scheduled for deletion)
aws kms enable-key --key-id $KMS_KEY_ID

# Verify state is back to normal
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{State:KeyState,Enabled:Enabled}" \
  --output table
# Expected: State = "Enabled", Enabled = true

# Wait 5-10 minutes for CloudWatch Logs to resume delivery
sleep 600

# Verify new logs are flowing again
aws logs get-log-events \
  --log-group-name "/aws/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/aws/vpc/flow-logs' \
    --order-by LastEventTime --descending \
    --query 'logStreams[0].logStreamName' --output text)" \
  --limit 3 \
  --query "events[*].{timestamp:timestamp,message:message}" \
  --output table
```

### Learn

- **The 7-Day Safety Net:** Why does AWS enforce a mandatory 7–30 day pending window? Prevents accidental/immediate data loss; gives you time to catch mistakes.
- **Why our module uses 14 days:** `deletion_window_in_days = 14` in `flow_logs.tf` — more time to catch mistakes, aligns with monthly security review cycles.
- **The Data Key Cache:** CloudWatch Logs caches decrypted data keys in memory for performance. This is why old logs remain readable even after key is pending deletion.
- **The Silent Failure:** CloudWatch Flow Logs delivery status becomes `FAILED` but doesn't trigger an alert by default. You need a CloudWatch Metric Filter on the `DeliveryErrors` metric.
- **Dual-Destination ROI:** S3 flow logs use a DIFFERENT KMS key (managed by `logging-flow-logs` module). This is exactly why dual-destination matters — if one key is compromised/deleted, the other destination survives.

### E-commerce Blast Radius Analysis

**What BREAKS:**
- ❌ CloudWatch Flow Logs: new logs fail to deliver, historical logs eventually unreadable
- ❌ CloudWatch Metric Filters: if based on flow logs, alerts stop firing
- ❌ CloudWatch Alarms: if based on metric filters, alerts go silent

**What DOES NOT break:**
- ✅ S3 flow logs: different KMS key (logging module manages it)
- ✅ Application traffic: VPC networking unaffected
- ✅ Terraform state: state file uses separate KMS key (bootstrap module)
- ✅ Secrets Manager: uses AWS-managed key or separate customer-managed key

**The Hidden Dependency Chain:**

```
Flow Logs → KMS key → CloudWatch Log Group → Metric Filters → CloudWatch Alarms

If KMS key deleted → Log Group fails → Metric Filters stop → Alarms go silent
Result: You lose BOTH logs AND the alerts that would tell you about the problem!
```

### Team-size Perspective

**Team 3–5:**
- Manual monitoring — engineer checks key state during monthly security review
- Recovery is manual: run `cancel-key-deletion` CLI command
- No automated alerting on key state changes

**Team 10–20:**
- CloudWatch alarm on `kms:ScheduleKeyDeletion` CloudTrail event → PagerDuty
- Runbook: "KMS Key Pending Deletion" with step-by-step recovery
- Weekly automated audit: script lists all keys pending deletion

**Team 50+:**
- AWS Config rule `kms-key-not-scheduled-for-deletion` (custom rule)
- SCP (Service Control Policy) `DENY kms:ScheduleKeyDeletion` for all non-break-glass roles
- Cross-account KMS keys (shared services account) with additional approval workflow
- Key rotation automation: new key created 30 days before old key expiry, gradual migration

### Interview Q References

- **Q48:** What happens when you delete a KMS key? What's the recovery window?
- **Q52:** How does envelope encryption work? Why doesn't KMS encrypt data directly?
- **Q55:** What's the difference between KMS Key Policy and IAM Policy?
- **Q58:** How do you prevent accidental KMS key deletion in production?

---

## Exercise 4.2: Key Rotation Mechanics

**File:** `flow_logs.tf` (KMS section) | **Time:** 20 min | **Interview Q:** Q53, Q54

### Hypothesis

Enabling automatic key rotation will:
- Create a new key version every 365 days
- Old encrypted data remains decryptable (old key versions retained)
- New data encrypted with new key version
- No application changes required (KMS handles transparently)

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Rotation fails silently | Low | High | CloudWatch alarm on rotation status |
| Old key version accidentally deleted | Low | Critical | Key versions cannot be deleted (AWS design) |
| Performance impact during rotation | Very Low | Low | Rotation is background operation |

### Steady State

```bash
# 1. Check if key rotation is enabled
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{KeyId:KeyId,EnabledKeyRotation:EnabledKeyRotation}" \
  --output table

# 2. List key material versions (should have 1 version initially)
aws kms list-key-rotations --key-id $KMS_KEY_ID \
  --query "Rotations[*].{RotationDate:RotationDate,RotationType:RotationType}" \
  --output table

# 3. Check key policy allows rotation (our module has enable_key_rotation = true)
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.Statement[] | select(.Sid=="EnableRootAccountAccess")'
```

### Inject

```bash
# Manually trigger key rotation (bypasses 365-day schedule)
aws kms rotate-key-on-demand --key-id $KMS_KEY_ID

# Wait 30 seconds for rotation to complete
sleep 30

# Verify new key version created
aws kms list-key-rotations --key-id $KMS_KEY_ID \
  --query "Rotations[*].{RotationDate:RotationDate,RotationType:RotationType}" \
  --output table
# Expected: 2 rotations — 1 automatic (if any) + 1 on-demand

# Describe key to see current key material
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.{KeyId:KeyId,KeyState:KeyState,Origin:Origin}" \
  --output table
```

### Observe (Multiple Dimensions)

**Dimension 1: Encryption with New Key Version**

```bash
# Encrypt some data (will use new key version)
ENCRYPTED=$(aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "test-data-after-rotation" \
  --query "CiphertextBlob" --output text)

# Decrypt it (KMS automatically uses correct key version)
aws kms decrypt \
  --ciphertext-blob fileb://<(echo $ENCRYPTED | base64 -d) \
  --query "Plaintext" --output text | base64 -d
# Expected: "test-data-after-rotation"

# Question: Did you need to specify which key version to use? (NO — KMS tracks automatically)
```

**Dimension 2: Old Data Still Decryptable**

```bash
# The flow logs encrypted BEFORE rotation should still be readable
aws logs get-log-events \
  --log-group-name "/aws/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/aws/vpc/flow-logs' \
    --order-by LastEventTime --descending \
    --query 'logStreams[-1].logStreamName' --output text)" \
  --limit 5 \
  --query "events[*].message" \
  --output text

# Question: Can you still read old logs? (YES — old key version retained)
# Question: How does KMS know which version to use? (Encrypted data key contains version ID)
```

**Dimension 3: Key Version Metadata**

```bash
# List all key versions with metadata
aws kms list-key-rotations --key-id $KMS_KEY_ID \
  --query "Rotations[*].{RotationDate:RotationDate,RotationType:RotationType,KeyId:KeyId}" \
  --output table

# Question: Can you delete old key versions? (NO — AWS retains all versions indefinitely)
# Question: Why? (Compliance — you must be able to decrypt historical data)
```

**Dimension 4: CloudWatch Logs Behavior**

```bash
# Check if CloudWatch Logs seamlessly uses new key version
# (It should — CloudWatch automatically re-encrypts data keys)

# Wait 5 minutes for new logs to be generated with new key version
sleep 300

aws logs get-log-events \
  --log-group-name "/aws/vpc/flow-logs" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name '/aws/vpc/flow-logs' \
    --order-by LastEventTime --descending \
    --query 'logStreams[0].logStreamName' --output text)" \
  --limit 3 \
  --query "events[*].{timestamp:timestamp,message:message}" \
  --output table

# Question: Are new logs being encrypted with new key version? (YES — transparent to CloudWatch)
```

### Recover

```bash
# No recovery needed — rotation is non-destructive
# But let's verify everything is working normally

# Check key state
aws kms describe-key --key-id $KMS_KEY_ID \
  --query "KeyMetadata.KeyState" --output text
# Expected: "Enabled"

# Verify flow logs still working
aws logs describe-log-streams \
  --log-group-name "/aws/vpc/flow-logs" \
  --order-by LastEventTime --descending \
  --query "logStreams[0:3].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table
```

### Learn

- **Transparent Rotation:** AWS automatically rotates the backing key material. The Key ID (ARN) stays the same — only the internal key material changes. Applications don't need to update their configuration.
- **Version Retention:** All key versions are retained indefinitely. You cannot delete old versions. This ensures you can always decrypt historical data.
- **On-Demand vs Automatic:** `rotate-key-on-demand` is useful for compliance audits or security incidents. Automatic rotation happens every 365 days.
- **Cost Impact:** No additional cost for key versions. You pay per KMS key ($1/month) regardless of how many versions exist.
- **Compliance Value:** Many compliance frameworks (PCI-DSS, SOC2, HIPAA) require key rotation. AWS KMS makes this trivial — just enable the flag.

### Production Best Practice

```hcl
# In flow_logs.tf — our module already does this correctly
resource "aws_kms_key" "flow_logs" {
  # ...
  enable_key_rotation     = true  # ✅ Automatic rotation every 365 days
  deletion_window_in_days = 14    # ✅ Safety net for accidental deletion
}
```

**What about custom rotation schedules?**
- AWS KMS only supports 365-day automatic rotation
- If you need 90-day rotation (some compliance frameworks), you must: create a new KMS key manually every 90 days, update resource configurations (CloudWatch Log Group, S3 bucket, etc.) to use the new key, and keep the old key for historical decryption
- This is complex — most teams accept 365-day rotation

### Team-size Perspective

**Team 3–5:**
- Enable automatic rotation and forget about it
- Annual review: check that rotation is enabled for all keys
- Document: "All KMS keys must have `enable_key_rotation = true`"

**Team 10–20:**
- AWS Config rule `kms-key-rotation-enabled` (managed rule) — alerts on keys without rotation
- Quarterly audit: script lists all keys and their rotation status
- Runbook: "Manual Key Rotation" for compliance requirements

**Team 50+:**
- Custom key management service that creates new keys every 90 days
- Automated migration: new key created → resources updated → old key deprecated
- Cross-account key rotation coordination (shared services account)
- Compliance dashboard: key age, rotation status, upcoming rotation dates

### Interview Q References

- **Q53:** How does KMS key rotation work? Do applications need to change?
- **Q54:** Can you delete old KMS key versions? Why or why not?
- **Q56:** What's the difference between automatic and on-demand key rotation?

---

## Exercise 4.3: Key Policy Debugging (Least Privilege)

**File:** `flow_logs.tf` (KMS policy section) | **Time:** 30 min | **Interview Q:** Q55, Q57, Q59

### Hypothesis

Modifying the KMS key policy to remove the CloudWatch Logs service principal will:
- Cause flow log delivery to fail with `AccessDeniedException`
- IAM role permissions are irrelevant if KMS key policy doesn't allow the service
- This is the #1 KMS misconfiguration in production

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Flow logs stop delivering | High | Medium | Quick recovery (restore policy) |
| Hard to debug (silent failure) | High | High | Document troubleshooting steps |
| Terraform drift | High | Low | Run `terraform apply` to restore |

### Steady State

```bash
# 1. View current KMS key policy
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.'

# 2. Identify the CloudWatch Logs statement
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.Statement[] | select(.Sid=="AllowCloudWatchLogs")'

# Expected output:
# {
#   "Sid": "AllowCloudWatchLogs",
#   "Effect": "Allow",
#   "Principal": {
#     "Service": "logs.ap-southeast-2.amazonaws.com"
#   },
#   "Action": [
#     "kms:Encrypt*",
#     "kms:Decrypt*",
#     "kms:ReEncrypt*",
#     "kms:GenerateDataKey*",
#     "kms:Describe*"
#   ],
#   "Resource": "*",
#   "Condition": {
#     "ArnLike": {
#       "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:ap-southeast-2:ACCOUNT_ID:log-group:/aws/vpc/flow-logs/*"
#     }
#   }
# }

# 3. Verify flow logs are currently working
aws logs describe-log-streams \
  --log-group-name "/aws/vpc/flow-logs" \
  --order-by LastEventTime --descending \
  --query "logStreams[0].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table
```

### Inject

```bash
# Create a modified policy that REMOVES the CloudWatch Logs statement
cat > /tmp/broken-kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):root"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
EOF

# Apply the broken policy (removes CloudWatch Logs access)
aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file:///tmp/broken-kms-policy.json

# Verify policy changed
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.Statement | length'
# Expected: 1 (only root account access)

# Wait 5 minutes for flow log delivery to fail
sleep 300
```

### Observe (Multiple Dimensions)

**Dimension 1: Flow Log Delivery Failure**

```bash
# Check if new logs are being delivered (they shouldn't be)
aws logs describe-log-streams \
  --log-group-name "/aws/vpc/flow-logs" \
  --order-by LastEventTime --descending \
  --query "logStreams[0:3].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table

# Question: Are new log streams being created? (NO — delivery fails)
# Question: What error does CloudWatch Flow Logs see?

# Check CloudWatch Metrics for delivery errors
aws cloudwatch get-metric-statistics \
  --namespace "AWS/Logs" \
  --metric-name "IncomingLogEvents" \
  --dimensions Name=LogGroupName,Value="/aws/vpc/flow-logs" \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --query "Datapoints[*].{Time:Timestamp,Events:Sum}" \
  --output table
# Expected: Sum = 0 or very low (no new logs)
```

**Dimension 2: Manual Encryption Test**

```bash
# Try to encrypt data using the KMS key (as root account — should work)
aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "test-manual-encryption" \
  --query "CiphertextBlob" --output text

# Question: Does manual encryption work? (YES — root account has kms:* access)
# Question: Why does manual work but CloudWatch fails? (CloudWatch uses service principal, not IAM role)
```

**Dimension 3: CloudTrail Audit**

```bash
# Check CloudTrail for KMS access denied errors
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Decrypt \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --query "Events[?contains(CloudTrailEvent,'AccessDenied')].{Time:EventTime,User:Username,Error:CloudTrailEvent}" \
  --output table | head -20

# Question: Do you see AccessDenied errors from logs.amazonaws.com? (YES)
# Question: What's the error message? ("User arn:aws:sts::ACCOUNT_ID:assumed-role/... is not authorized to perform: kms:Decrypt")
```

**Dimension 4: IAM vs KMS Policy (The Dual Gate)**

```bash
# Check the IAM role that CloudWatch Flow Logs uses
FLOW_LOGS_ROLE=$(aws iam list-roles \
  --query "Roles[?contains(RoleName,'vpc-flow-logs')].RoleName" --output text)

# View the IAM policy attached to this role
aws iam get-role-policy \
  --role-name $FLOW_LOGS_ROLE \
  --policy-name "$(aws iam list-role-policies --role-name $FLOW_LOGS_ROLE --query 'PolicyNames[0]' --output text)" \
  --query "PolicyDocument" --output text | jq '.'

# Question: Does the IAM role have kms:Decrypt permission? (YES — in flow_logs.tf)
# Question: Why doesn't it work then? (KMS key policy doesn't allow logs.amazonaws.com service principal)
# Question: This proves BOTH gates must pass — IAM policy AND KMS key policy
```

### Recover

```bash
# Restore the correct KMS key policy
cat > /tmp/fixed-kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.$(aws configure get region).amazonaws.com"
      },
      "Action": [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:$(aws configure get region):$(aws sts get-caller-identity --query Account --output text):log-group:/aws/vpc/flow-logs/*"
        }
      }
    }
  ]
}
EOF

aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file:///tmp/fixed-kms-policy.json

# Verify policy restored
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.Statement | length'
# Expected: 2 statements

# Wait 5 minutes for flow logs to resume
sleep 300

# Verify logs flowing again
aws logs describe-log-streams \
  --log-group-name "/aws/vpc/flow-logs" \
  --order-by LastEventTime --descending \
  --query "logStreams[0:3].{Name:logStreamName,LastEvent:lastEventTimestamp}" \
  --output table
# Expected: Recent timestamps

# Run terraform apply to sync state
cd environments/shared
terraform apply -auto-approve
```

### Learn

- **The Dual Gate:** Access to KMS key requires BOTH IAM policy (attached to role) AND KMS key policy (attached to key) to allow the action. Missing either = Access Denied.
- **Service Principals:** AWS services (CloudWatch Logs, S3, RDS) use service principals like `logs.region.amazonaws.com`, NOT IAM roles. You must explicitly allow these in the KMS key policy.
- **Condition Keys:** The `ArnLike` condition restricts which log groups can use this key. This is least privilege — prevents other log groups from using this key.
- **Silent Failure:** CloudWatch Flow Logs doesn't alert you when delivery fails. You need to monitor the `IncomingLogEvents` metric or CloudTrail `AccessDenied` events.
- **Terraform Best Practice:** Always define KMS key policy in Terraform (like `flow_logs.tf` does). Manual policy changes cause drift and are hard to debug.

### Production Debugging Checklist

When you see `AccessDeniedException` for KMS:

1. **Check KMS Key Policy** — does it allow the service principal or IAM role?
2. **Check IAM Policy** — does the role have `kms:*` permissions?
3. **Check Condition Keys** — are there restrictive conditions (like `ArnLike`)?
4. **Check CloudTrail** — what's the exact error message?
5. **Check Key State** — is the key enabled? Not pending deletion?
6. **Check Key Rotation** — did rotation just happen? (Rare, but possible timing issue)

### Team-size Perspective

**Team 3–5:**
- Document KMS key policy structure in runbook
- Manual debugging: check CloudTrail, check key policy
- Use Terraform to manage all KMS policies (no manual changes)

**Team 10–20:**
- AWS Config rule `kms-key-policy-has-required-statements` (custom rule)
- CloudWatch alarm on `AccessDenied` CloudTrail events for KMS
- Runbook: "KMS Access Denied Troubleshooting" with step-by-step debugging

**Team 50+:**
- Centralized KMS key management in shared services account
- Automated policy validation: CI/CD pipeline checks KMS policies before apply
- Cross-account KMS access with approval workflow
- Policy-as-code: OPA/Sentinel rules validate KMS policies in Terraform plans

### Interview Q References

- **Q55:** What's the difference between KMS Key Policy and IAM Policy?
- **Q57:** How do you debug KMS AccessDenied errors?
- **Q59:** What are KMS condition keys? Why use them?

---

## Exercise 4.4: Cross-Account KMS Access (Multi-Account Patterns)

**File:** New exercise (no existing code) | **Time:** 35 min | **Interview Q:** Q60, Q61

### Hypothesis

In production, KMS keys often live in a "shared services" account, and application accounts need cross-account access. This requires:
- KMS key policy allowing the external account
- IAM role in the application account with `kms:*` permissions
- Both gates must pass (KMS policy + IAM policy)

### Risk Assessment

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Misconfigured cross-account access | High | High | Use condition keys to restrict |
| Overly permissive policy | Medium | High | Least privilege with conditions |
| Hard to audit | Medium | Medium | CloudTrail cross-account logging |

### Steady State

```bash
# This exercise simulates cross-account access
# In real production, you'd have:
# - Account A (Shared Services): KMS key lives here
# - Account B (Application): Needs to use the key

# For this lab, we'll use the same account but simulate cross-account
# by creating a separate IAM role

# 1. Get current account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Current Account: $ACCOUNT_ID"

# 2. Create a new IAM role (simulating "application account" role)
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name cross-account-kms-test \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --query "Role.Arn" --output text

# 3. Attach KMS permissions to the role
cat > /tmp/kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:$(aws configure get region):$ACCOUNT_ID:key/$KMS_KEY_ID"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name cross-account-kms-test \
  --policy-name KMSAccess \
  --policy-document file:///tmp/kms-policy.json

# 4. Verify role created
aws iam get-role --role-name cross-account-kms-test \
  --query "Role.Arn" --output text
```

### Inject

```bash
# Step 1: Try to use the KMS key with the new role (will fail)
ROLE_ARN=$(aws iam get-role --role-name cross-account-kms-test --query "Role.Arn" --output text)

# Assume the role
CREDS=$(aws sts assume-role \
  --role-arn $ROLE_ARN \
  --role-session-name cross-account-test \
  --query "Credentials" --output json)

# Extract credentials
ACCESS_KEY=$(echo $CREDS | jq -r '.AccessKeyId')
SECRET_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Try to encrypt with assumed role (will fail — KMS policy doesn't allow this role)
AWS_ACCESS_KEY_ID=$ACCESS_KEY \
AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
AWS_SESSION_TOKEN=$SESSION_TOKEN \
aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "cross-account-test" \
  --query "CiphertextBlob" --output text 2>&1 | head -5
# Expected: AccessDeniedException — KMS key policy doesn't allow this role
```

### Observe (Multiple Dimensions)

**Dimension 1: Access Denied (Expected)**

```bash
# The encryption failed because KMS key policy doesn't allow the role
# Check CloudTrail for the error

aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=Encrypt \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --query "Events[?contains(CloudTrailEvent,'cross-account-test')].{Time:EventTime,Error:CloudTrailEvent}" \
  --output table | head -10

# Question: What's the error message? ("The ciphertext refers to a customer master key that does not exist, does not exist in this region, or you are not allowed to access.")
# Question: Why is it so vague? (Security — AWS doesn't reveal whether key exists or you lack permission)
```

**Dimension 2: Fix KMS Key Policy**

```bash
# Update KMS key policy to allow the role
cat > /tmp/cross-account-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.$(aws configure get region).amazonaws.com"
      },
      "Action": [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:$(aws configure get region):$ACCOUNT_ID:log-group:/aws/vpc/flow-logs/*"
        }
      }
    },
    {
      "Sid": "AllowCrossAccountRole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:role/cross-account-kms-test"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file:///tmp/cross-account-policy.json

# Verify policy updated
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default \
  --query "Policy" --output text | jq '.Statement | length'
# Expected: 3 statements
```

**Dimension 3: Success (After Fix)**

```bash
# Try again with assumed role (should work now)
AWS_ACCESS_KEY_ID=$ACCESS_KEY \
AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
AWS_SESSION_TOKEN=$SESSION_TOKEN \
aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "cross-account-test-after-fix" \
  --query "CiphertextBlob" --output text

# Question: Does it work now? (YES — both gates pass)
# Question: What changed? (KMS key policy now allows the role)
```

**Dimension 4: Condition Keys (Least Privilege)**

```bash
# Add a condition to restrict what the role can encrypt
cat > /tmp/condition-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.$(aws configure get region).amazonaws.com"
      },
      "Action": [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:$(aws configure get region):$ACCOUNT_ID:log-group:/aws/vpc/flow-logs/*"
        }
      }
    },
    {
      "Sid": "AllowCrossAccountRole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:role/cross-account-kms-test"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:EncryptionContext:purpose": "testing"
        }
      }
    }
  ]
}
EOF

aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file:///tmp/condition-policy.json

# Try to encrypt WITHOUT the required encryption context (will fail)
AWS_ACCESS_KEY_ID=$ACCESS_KEY \
AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
AWS_SESSION_TOKEN=$SESSION_TOKEN \
aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "test-without-context" \
  --query "CiphertextBlob" --output text 2>&1 | head -5
# Expected: AccessDeniedException

# Try to encrypt WITH the required encryption context (should work)
AWS_ACCESS_KEY_ID=$ACCESS_KEY \
AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
AWS_SESSION_TOKEN=$SESSION_TOKEN \
aws kms encrypt \
  --key-id $KMS_KEY_ID \
  --plaintext "test-with-context" \
  --encryption-context purpose=testing \
  --query "CiphertextBlob" --output text

# Question: Why use encryption context? (Auditing + additional security layer)
# Question: What happens if you lose the encryption context? (Cannot decrypt — it's part of the ciphertext)
```

### Recover

```bash
# Restore original KMS key policy (from flow_logs.tf)
cat > /tmp/original-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableRootAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.$(aws configure get region).amazonaws.com"
      },
      "Action": [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:$(aws configure get region):$ACCOUNT_ID:log-group:/aws/vpc/flow-logs/*"
        }
      }
    }
  ]
}
EOF

aws kms put-key-policy \
  --key-id $KMS_KEY_ID \
  --policy-name default \
  --policy file:///tmp/original-policy.json

# Delete the test IAM role
aws iam delete-role-policy --role-name cross-account-kms-test --policy-name KMSAccess
aws iam delete-role --role-name cross-account-kms-test

# Verify cleanup
aws iam get-role --role-name cross-account-kms-test 2>&1 | head -3
# Expected: NoSuchEntity error

# Run terraform apply to sync state
cd environments/shared
terraform apply -auto-approve
```

### Learn

- **Cross-Account Pattern:** In production, KMS keys often live in a "shared services" account. Application accounts need cross-account access. This requires BOTH KMS key policy (allowing external account) AND IAM policy (in application account).
- **Condition Keys:** Use `kms:EncryptionContext:*` to restrict what can be encrypted. This adds an additional security layer and enables auditing.
- **Encryption Context:** Key-value pairs that are cryptographically bound to the ciphertext. You must provide the same context to decrypt. Useful for auditing (CloudTrail logs the context).
- **Least Privilege:** Don't give `kms:*` to cross-account roles. Give only `kms:Encrypt`, `kms:Decrypt`, `kms:DescribeKey` as needed.
- **Audit Trail:** CloudTrail logs cross-account KMS access. Use this for security audits and incident response.

### Production Architecture (Multi-Account)

```text
┌─────────────────────────────────────────────────────────────┐
│  Shared Services Account                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  KMS Key (arn:aws:kms:...:key/abc123)                 │  │
│  │  Key Policy:                                          │  │
│  │    - Allow root account                               │  │
│  │    - Allow Account B (arn:aws:iam::ACCOUNT_B:root)    │  │
│  │    - Allow Account C (arn:aws:iam::ACCOUNT_C:root)    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ Cross-account access
                          │
┌─────────────────────────┴───────────────────────────────────┐
│  Account B (Application)                                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  IAM Role (arn:aws:iam::ACCOUNT_B:role/app-role)      │  │
│  │  IAM Policy:                                          │  │
│  │    - kms:Encrypt on arn:aws:kms:...:key/abc123        │  │
│  │    - kms:Decrypt on arn:aws:kms:...:key/abc123        │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  Application uses KMS key for:                              │
│    - Encrypting S3 buckets                                  │
│    - Encrypting RDS databases                                │
│    - Encrypting Secrets Manager secrets                     │
└─────────────────────────────────────────────────────────────┘
```

### Team-size Perspective

**Team 3–5:**
- Single AWS account — no cross-account KMS needed
- All KMS keys in same account as applications
- Simple key policies (root account + service principals)

**Team 10–20:**
- 2–3 AWS accounts (dev, staging, prod)
- KMS keys per account (no cross-account)
- Document cross-account patterns for future expansion

**Team 50+:**
- Multi-account architecture (10+ accounts)
- Centralized KMS key management in shared services account
- Cross-account KMS access with approval workflow
- Automated key policy validation in CI/CD
- Compliance dashboard: cross-account access audit

### Interview Q References

- **Q60:** How does cross-account KMS access work?
- **Q61:** What are KMS encryption contexts? Why use them?
- **Q62:** How do you audit cross-account KMS usage?

---

## 🚨 Real Incident Case Study: "The Silent Log Apocalypse"

### Incident Summary

| Field | Value |
|---|---|
| **Date** | 2026-03-15 |
| **Duration** | 48 hours undetected |
| **Severity** | High (Compliance violation) |
| **Impact** | 48 hours of VPC flow logs permanently lost |

### Timeline

**Day 0, 14:30 UTC**
Security engineer manually schedules KMS key deletion via AWS Console. Intention: clean up "unused" KMS key (misidentified as test key). Pending window: 7 days (default).

**Day 0, 14:35 UTC**
KMS key state changes to `PendingDeletion`. CloudWatch Flow Logs delivery starts failing silently. No alert fires (no monitoring on KMS key state).

**Day 0–2**
Flow logs accumulate in CloudWatch Logs buffer. Delivery status: `FAILED` (but no alerting on this metric). Security team unaware.

**Day 2, 09:00 UTC**
Security incident detected: suspicious network traffic. Team attempts to investigate via VPC flow logs. Discovers: no flow logs for past 48 hours. Realizes KMS key is pending deletion.

**Day 2, 09:15 UTC**
Engineer cancels key deletion (`aws kms cancel-key-deletion`), re-enables key (`aws kms enable-key`), waits for flow logs to resume.

**Day 2, 09:30 UTC**
Flow logs resume delivery. But 48 hours of logs permanently lost (buffer overflowed).

**Day 2, 10:00 UTC**
Post-mortem initiated. Root cause: manual key deletion + no monitoring.

### Root Cause Analysis

**Primary Cause:** Manual KMS key deletion without understanding dependencies; no monitoring on KMS key state changes.

**Contributing Factors:**
- **Misidentification:** key was misidentified as "test key" (no proper tagging)
- **No Alerts:** no CloudWatch alarm on `kms:ScheduleKeyDeletion` CloudTrail event
- **Silent Failure:** CloudWatch Flow Logs delivery failure doesn't trigger alert
- **No Runbook:** no documented procedure for KMS key lifecycle management
- **Insufficient Training:** engineer didn't understand KMS dependencies

### Lessons Learned

1. **Never manually delete KMS keys without dependency analysis** — use `aws kms list-grants` to see what's using the key; check CloudTrail for recent usage; document all KMS keys with proper tags.
2. **Monitor KMS key state changes** — CloudWatch alarm on `kms:ScheduleKeyDeletion` CloudTrail event; AWS Config rule to detect keys pending deletion; SCP to deny `kms:ScheduleKeyDeletion` except break-glass roles.
3. **Monitor flow log delivery** — CloudWatch alarm on `IncomingLogEvents` metric (alert if = 0); CloudWatch Metric Filter on delivery status.
4. **Dual-destination is critical** — S3 flow logs (different KMS key) would have survived. This is why the module has dual-destination architecture.
5. **Tagging is essential** — all KMS keys must have `Purpose`, `Owner`, `Environment` tags; prevents misidentification as "unused".

### Prevention Measures Implemented

**1. Automated Monitoring:**

```hcl
# CloudWatch alarm on KMS key deletion
resource "aws_cloudwatch_metric_alarm" "kms_key_deletion" {
  alarm_name          = "kms-key-scheduled-for-deletion"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ScheduleKeyDeletion"
  namespace           = "AWS/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerts when KMS key is scheduled for deletion"

  dimensions = {
    EventName = "ScheduleKeyDeletion"
  }
}
```

**2. SCP Restriction:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyKMSKeyDeletion",
      "Effect": "Deny",
      "Action": "kms:ScheduleKeyDeletion",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalTag/BreakGlass": "true"
        }
      }
    }
  ]
}
```

**3. AWS Config Rule:**

```hcl
resource "aws_config_config_rule" "kms_key_not_pending_deletion" {
  name = "kms-key-not-pending-deletion"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.kms_check.arn
  }
}
```

**4. Runbook Created:** "KMS Key Lifecycle Management" — step-by-step procedure for key deletion, dependency analysis checklist, recovery procedures.

### Production Best Practices

```hcl
# 1. Always use lifecycle rules to prevent accidental deletion
resource "aws_kms_key" "critical" {
  # ...
  lifecycle {
    prevent_destroy = true  # Terraform won't delete this key
  }
}

# 2. Tag all KMS keys
resource "aws_kms_key" "flow_logs" {
  # ...
  tags = {
    Purpose     = "vpc-flow-logs-encryption"
    Owner       = "platform-team"
    Environment = "production"
    Critical    = "true"
  }
}

# 3. Use longer deletion windows
resource "aws_kms_key" "flow_logs" {
  # ...
  deletion_window_in_days = 30  # Maximum safety net
}

# 4. Monitor key state
resource "aws_cloudwatch_metric_alarm" "kms_deletion" {
  alarm_name          = "kms-key-pending-deletion"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ScheduleKeyDeletion"
  namespace           = "AWS/CloudTrail"
  period              = 300
  statistic           = "Sum"
  threshold           = 0

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}
```

---

# Progression Schedule

| Week | Exercises | Focus | Time |
|------|-----------|-------|------|
| 1 | Ex 1.1, 1.2, 1.3 | Drift detection — safe, build confidence | 35 min |
| 2 | Ex 2.1, 2.2 | NAT/IGW deletion — blast radius + team-size response | 35 min |
| 3 | Ex 2.3, 2.4 | Dual-destination proof + cascade analysis | 25 min |
| 4 | Ex 3.1, 3.2 | State locking + state rm/import | 35 min |
| 5 | Ex 3.3, 3.4, 3.5 | State corruption + rename migration + real incident | 55 min |
| 6 | Ex 4.1 | KMS lifecycle — schedule deletion & cancel | 25 min |
| 7 | Ex 4.2 | Key rotation mechanics — automatic vs on-demand | 20 min |
| 8 | Ex 4.3 | Key policy debugging — dual gate (IAM + KMS) | 30 min |
| 9 | Ex 4.4 | Cross-account KMS access — multi-account patterns | 35 min |
| 10 | Real Incident | Case study — "The Silent Log Apocalypse" | 20 min (read) |

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
