# 🔥 Chaos Exercises — Network Module Deep Dive

> Break it. Fix it. Understand it.
> All exercises target `modules/network/` resources only.
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

---

## Ex 1.1: Console Drift — Route Table

**File:** `routing.tf` | **Time:** 15 min | **Interview Q:** Q38

**Hypothesis:** Adding a route manually via Console will be detected by `terraform plan`.

**Steady State:**
```bash
# Find the private route table
aws ec2 describe-route-tables \
  --filters "Name=tag:Tier,Values=private" \
  --query "RouteTables[0].{ID:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Target:NatGatewayId}}" \
  --output json
```

**Inject:** In AWS Console → VPC → Route Tables → find private route table → Add route: `192.168.0.0/16` → target: local

**Observe:**
```bash
cd environments/shared
terraform plan 2>&1 | grep -C 3 "route"
# Question: Does Terraform detect the extra route?
# Question: Does it propose to DELETE the manual route or UPDATE the table?
```

**Recover:** `terraform apply` — Terraform removes the rogue route.

**Learn:**
- [ ] Was the drift detected as `~` (update) or something else?
- [ ] What if someone added a route that Terraform also manages — conflict?
- [ ] How to automate drift detection? (`terraform plan -detailed-exitcode` in cron/CI)

**Team-size perspective:**
- [ ] **Team 3–5:** Who detects this drift? (Engineer notices during next `plan`)
- [ ] **Team 10–20:** Scheduled drift detection in CI (e.g., nightly `plan` → Slack alert)
- [ ] **Team 50+:** AWS Config rule `vpc-flow-logs-enabled` + auto-remediation via SSM

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

**Recover:** `terraform apply`

---

## Ex 1.3: Console Drift — Flow Log Traffic Type

**File:** `flow_logs.tf` | **Time:** 10 min

**Hypothesis:** You cannot change a flow log's traffic type in-place — AWS requires delete + recreate.

**Observe only (no Console change needed):**
```bash
# Change traffic type in main.tf
# flow_logs_cloudwatch_traffic_type = "ALL"  (was "REJECT")
terraform plan 2>&1 | grep -B 2 -A 5 "flow_log"
# Question: Is it `~` update or `-/+` forces replacement?
# Revert main.tf after observing
```

**Learn:**
- [ ] Why does traffic_type change force replacement? (AWS API limitation)
- [ ] What happens to log continuity during replacement? (gap of ~1-2 minutes)
- [ ] How does the CHANGELOG document this as a breaking change?

---

# Phase 2: Resource Deletion & Recovery (Medium Risk)

> 🟡 **Risk: MEDIUM** — Resources are deleted but contain no persistent data.
> Terraform re-creates them on next apply. Expect brief connectivity impact.

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
terraform plan 2>&1 | grep -c "will be created"
# Question: How many resources? Just NAT or routes too?
# Question: Does Terraform also recreate the EIP?
```

**Recover:**
```bash
terraform apply
# Time it: NAT Gateway creation takes ~2-3 minutes
```

**Learn:**
- [ ] Recovery time = ___ minutes. Acceptable for production?
- [ ] With `single_nat_gateway = false` (3 NATs), would losing 1 NAT cause total outage? (No — other AZs unaffected)
- [ ] What monitoring alert would detect "NAT Gateway deleted"?

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

**Recover:** `terraform apply`

**Learn:**
- [ ] Blast radius: IGW deletion affected ___ resources
- [ ] This is why Phase 1 drift detection matters — catch before it cascades

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

**Recover:** `terraform apply`

**Learn:**
- [ ] CloudWatch logs: **permanently lost**. S3 logs: **still intact** ← dual-destination proof
- [ ] What CloudWatch alarm would detect "log group deleted"?
- [ ] Should log groups have `prevent_destroy`? Trade-off?

**Team-size perspective:**
- [ ] **Team 3–5:** CloudWatch loss is acceptable if S3 archive exists for forensics
- [ ] **Team 10–20:** Alert on missing log groups via AWS Config rule `cloudwatch-log-group-encrypted`
- [ ] **Team 50+:** Centralized log account — log groups are in a separate account that app teams cannot delete

---

## Ex 2.4: Targeted Destroy Cascade — Observe Only

**Time:** 10 min | **Interview Q:** Q34 (blast radius isolation)

**Hypothesis:** `terraform destroy -target=module.network` will show cascade destruction
of ALL dependent modules (vpc-endpoints, security, database) because they reference
`module.network` outputs.

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
- [ ] Blast radius of destroying network = ___ total resources (across all modules)
- [ ] This proves why `logging-flow-logs` is a separate module — S3 bucket survives VPC destruction
- [ ] `-target` is dangerous because it bypasses normal dependency safety

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

**Inject:**
```bash
# Simulate stuck lock
aws dynamodb put-item --table-name terraform-locks --item '{
  "LockID": {"S": "obs-lab-terraform-state/shared/terraform.tfstate"},
  "Info": {"S": "{\"ID\":\"fake-lock\",\"Operation\":\"OperationTypeApply\",\"Who\":\"ghost\"}"}
}'
```

**Observe:**
```bash
cd environments/shared
terraform plan  # Should fail with "Error acquiring state lock"
```

**Recover:**
```bash
terraform force-unlock fake-lock
terraform plan  # Should work now
```

**Learn:**
- [ ] What if a REAL apply is running when you force-unlock? (State corruption risk)
- [ ] How to verify no one is running apply? (Check DynamoDB, ask team, CI/CD dashboard)

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

**Recover:**
```bash
FLOW_LOG_ID=$(aws ec2 describe-flow-logs \
  --filter "Name=log-destination-type,Values=cloud-watch-logs" \
  --query "FlowLogs[0].FlowLogId" --output text)

terraform import 'module.network.aws_flow_log.cloudwatch["vpc"]' $FLOW_LOG_ID
terraform plan  # Should show "No changes"
```

**Learn:**
- [ ] What if you applied without importing? (Duplicate flow log created)
- [ ] Some resources cannot be imported — which ones? (Check Terraform docs)
- [ ] Prevention: who should have permission to run `terraform state rm`?

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
# List state file versions
aws s3api list-object-versions --bucket $STATE_BUCKET \
  --prefix "shared/terraform.tfstate" \
  --query "Versions[].{Version:VersionId,Date:LastModified,Size:Size}" \
  --output table

# Restore last good version
GOOD_VERSION="<pick-version-before-corrupt>"
aws s3api get-object --bucket $STATE_BUCKET \
  --key "shared/terraform.tfstate" \
  --version-id $GOOD_VERSION /tmp/good-state.json

aws s3 cp /tmp/good-state.json s3://$STATE_BUCKET/shared/terraform.tfstate

# Verify
terraform state list | wc -l  # Should match original count
terraform plan                 # Should show "No changes"
```

**Learn:**
- [ ] What if S3 versioning was NOT enabled? (Unrecoverable without backup)
- [ ] Should you add lifecycle rules to delete old state versions? (No — they are your backup)
- [ ] How to detect state corruption in CI before damage? (Compare resource count)

**Team-size perspective:**
- [ ] **Team 3–5:** S3 versioning is your only safety net. Recovery is manual — know the AWS CLI commands by heart.
- [ ] **Team 10–20:** Automate state backup to a separate S3 bucket (cross-account). Add CI step: `terraform state list | wc -l` as a health check before every apply.
- [ ] **Team 50+:** Terraform Cloud/Enterprise with built-in state versioning and rollback UI. State bucket has Object Lock (compliance mode) to prevent even admins from deleting versions.

---

## Ex 3.4: Rename Resource — `moved` Block vs `state mv`

**Time:** 15 min | **Interview Q:** Q12, Q35

**Observe only (do not apply):**
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
- [ ] Why is `moved` block preferred over `state mv` for teams? (Declarative, reviewable in PR)
- [ ] Can `moved` blocks be removed after apply? (Yes, after all environments have applied)
- [ ] What about `count` → `for_each` migration? (Same technique, more complex addresses)

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
| 5 | Ex 3.3, 3.4 | State corruption recovery + rename migration | 40 min |
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
