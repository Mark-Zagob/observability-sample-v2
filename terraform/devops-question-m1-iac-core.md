# DevOps Interview — AWS / Terraform & IaC Core
## Milestone 1: Infrastructure as Code Fundamentals
### Based on Observability Lab — Terraform Modules (Network, Database, Backup)

> **Context**: This question set is based on a real AWS infrastructure project with
> 5 Terraform modules (network, vpc-endpoints, database, backup, security),
> remote state (S3 + DynamoDB), Policy-as-Code (OPA/Conftest + Checkov),
> and contract/integration testing. All questions reference actual implementation patterns.
>
> **How to use**: Answer each question in your own words. Interviewers evaluate
> understanding of *why*, not just *what*. Use examples from the lab where possible.

---

# Part A: Junior to Mid-Level

> Questions in this section test foundational IaC knowledge, basic Terraform operations,
> and the ability to work within an existing module-based infrastructure.

---

## Section 1: Terraform Fundamentals (7 questions)

**Q1.** What is Infrastructure as Code (IaC) and why is it preferred over manually creating resources in the AWS Console? Give at least three specific benefits.

**Q2.** Explain the Terraform workflow: `init` → `plan` → `apply`. What does each step do? Why is `plan` considered the most important step in a team environment?

**Q3.** In our project, `environments/shared/main.tf` calls modules using relative paths:
```hcl
module "network" {
  source = "../../modules/network"
}
```
What does `terraform init` do with this `source` path? What would change if we used a Git URL instead (e.g., `git::ssh://...?ref=network/v1.0.1`)?

**Q4.** What is the difference between `terraform plan` output showing `+` (create), `~` (update in-place), and `-/+` (destroy and recreate)? Why is `-/+` dangerous and what kinds of changes typically cause it?

**Q5.** You run `terraform apply` and it fails halfway — 3 out of 5 resources were created successfully. What happens to those 3 resources? What is the state of your infrastructure now? How do you recover?

**Q6.** In our backup module, we have this validation block:
```hcl
variable "environment" {
  type    = string
  default = "lab"
  validation {
    condition     = contains(["dev", "staging", "prod", "lab"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, lab."
  }
}
```
When does this validation run — during `plan` or `apply`? What happens if someone passes `environment = "production"` (typo)?

**Q7.** What is the difference between `variable`, `local`, and `output` in Terraform? Give an example of when you would use each one from our module structure.

---

## Section 2: State Management (5 questions)

**Q8.** Our project stores Terraform state in S3 with DynamoDB locking:
```hcl
backend "s3" {
  bucket         = "obs-lab-terraform-state"
  key            = "shared/terraform.tfstate"
  region         = "ap-southeast-2"
  dynamodb_table = "terraform-locks"
  encrypt        = true
}
```
Why do we use remote state instead of keeping `terraform.tfstate` as a local file? What would happen if two team members ran `terraform apply` at the same time without DynamoDB locking?

**Q9.** *(Mid-Senior)* You accidentally deleted a security group using `terraform destroy -target=aws_security_group.data`. The RDS instance that depends on it is now in a broken state. How would you recover? What Terraform commands might help?

**Q10.** What does `terraform refresh` do? Why has HashiCorp recommended against running it directly in recent versions? What replaced it?

**Q11.** A colleague asks you to check what resources Terraform is currently managing. How do you list them? What command would you use, and what does the output look like?

**Q12.** *(Mid)* You need to rename a resource from `aws_s3_bucket.reports` to `aws_s3_bucket.backup_reports` in your code. If you just rename it and run `terraform plan`, what will Terraform propose? How do you avoid destroying and recreating the bucket?

---

## Section 3: Module Design & Structure (6 questions)

**Q13.** Our project has this structure:
```
terraform/
├── environments/
│   └── shared/main.tf      ← calls modules
├── modules/
│   ├── network/             ← VPC, subnets, NAT
│   ├── database/            ← RDS, KMS, monitoring
│   └── backup/              ← Vault, plan, reporting
└── policy/                  ← OPA rules
```
Why do we separate `modules/` from `environments/`? What problem does this solve compared to putting all resources in one flat directory?

**Q14.** Our network module outputs the VPC ID, and the database module needs it as input:
```hcl
module "database" {
  source = "../../modules/database"
  vpc_id = module.network.vpc_id
}
```
How does Terraform know to create the VPC before the RDS instance? What mechanism handles this dependency? What happens if you create a circular dependency?

**Q15.** The backup module has 14 files (vault.tf, plan.tf, kms.tf, iam.tf, notifications.tf, reporting.tf, etc). Why split into multiple files instead of putting everything in one `main.tf`? Does Terraform care about filenames?

**Q16.** In our database module, we use `count` to conditionally create a read replica:
```hcl
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0
  ...
}
```
What is the difference between using `count` and `for_each` for conditional resources? When would you prefer one over the other?

**Q17.** Each module has a `versions.tf` file pinning the provider version:
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
  }
}
```
Why do we use `>= 5.0, < 6.0` instead of just `>= 5.0`? What could go wrong with an unpinned major version?

**Q18.** Our modules have both `examples/` and `tests/` directories. What is the purpose of each? How do they complement each other? Can you have one without the other?

---

## Section 4: Day-to-Day Operations & Team Workflow (8 questions)

**Q19.** You need to update the RDS instance class from `db.t3.micro` to `db.t3.small`. Walk through the steps you would take from editing the code to the change being live. What should you check in the `terraform plan` output before applying?

**Q20.** After running `terraform apply`, you notice that a resource shows as "created" in the output, but when you check the AWS Console, it doesn't exist. What could cause this? How would you troubleshoot?

**Q21.** A junior developer wants to add a new S3 bucket directly in `environments/shared/main.tf` instead of creating a module for it. When is this acceptable and when should you insist on creating a module?

**Q22.** You run `terraform plan` and see `(known after apply)` for several attributes. What does this mean? Give an example from our lab where this would appear.

**Q23.** Our project uses `common_tags` passed to every module:
```hcl
common_tags = {
  Project     = "obs-lab"
  Environment = "shared"
  ManagedBy   = "terraform"
}
```
Why is tagging important in AWS? How would you enforce that all resources have these tags?

**Q24.** A team member opens a Pull Request that modifies the database module's `variables.tf`. Describe the ideal review process for Terraform changes. What should the reviewer check beyond normal code review? How does `terraform plan` output help in the review?

**Q25.** You run `terraform plan` on a module change and it shows it will create 3 new resources. Your team lead asks: "What's the estimated monthly cost impact?" How would you answer this question? Is there a way to automate this in the team's workflow?

**Q26.** In a team of 5, everyone has AWS credentials and can run `terraform apply` directly. What risks does this create? At what team size would you enforce that only CI/CD pipelines can apply changes? What is the simplest first step to add this control?

---

# Part B: Senior Level and Above

> Questions in this section test architectural thinking, trade-off analysis,
> blast radius management, and the ability to design systems for scale.
> Candidates should demonstrate deep understanding of *why* decisions are made,
> not just *how* to implement them.

---

## Section 5: Architecture & Design Decisions (8 questions)

**Q27.** Our project uses **one state file** for all modules (`shared/terraform.tfstate`). The network, database, and backup modules are all managed together. What are the risks of this approach as the team grows? At what point would you recommend splitting into separate state files, and how would you do it?

**Q28.** We have a `modules/` directory alongside `environments/`. A colleague proposes creating an `environments/prod/` that reuses the same modules with different variables. Another colleague says we should use Terraform workspaces instead. Compare these two approaches. Which would you recommend and why?

**Q29.** The backup module creates resources in **two AWS regions** (ap-southeast-2 for primary, ap-southeast-1 for DR) using provider aliases:
```hcl
provider "aws" {
  alias  = "dr"
  region = "ap-southeast-1"
}
```
What are the challenges of managing multi-region infrastructure in a single Terraform configuration? When would you split it into separate configurations?

**Q30.** Our database module handles RDS, KMS, monitoring, secrets, and SSM parameters — all in one module. A new team member argues it should be split into smaller modules (one for RDS, one for KMS, one for monitoring). What are the trade-offs? How would you decide?

**Q31.** You are designing the module interface (variables/outputs) for a new module. What principles guide which values should be variables vs hardcoded? Give an example of something that should NOT be a variable even though it could be.

**Q32.** We use `local.identifier` (e.g., `obs-lab-backup`) as a naming prefix throughout modules. What naming collision risks exist? How would you design a naming strategy that works across multiple environments, teams, and AWS accounts?

**Q33.** Our modules use `merge(var.common_tags, { ... })` for tagging. In a multi-team organization, how would you enforce a mandatory tagging policy? Compare three approaches: Terraform validation, OPA policy, and AWS Organizations SCP. When would you use each?

**Q34.** Currently, if someone runs `terraform apply` on the shared environment, a mistake in the backup module could force-replace the RDS instance (blast radius = everything). How would you redesign the state architecture to isolate blast radius? What is the trade-off between isolation and operational complexity?

---

## Section 6: State Management — Advanced (5 questions)

**Q35.** You need to refactor the network module — moving `aws_subnet` resources from a flat list (`count`) to a map (`for_each` with AZ keys). This changes resource addresses from `aws_subnet.private[0]` to `aws_subnet.private["ap-southeast-2a"]`. How do you perform this migration without destroying and recreating subnets? Walk through the exact steps.

**Q36.** A failed `terraform apply` left your state file locked in DynamoDB. The engineer who started the apply has gone home. How do you safely unlock the state? What risks does force-unlocking carry?

**Q37.** Your state file contains sensitive data (RDS master password, KMS key ARNs). How does Terraform handle sensitive values in state? What additional measures should you take to protect the state file at rest and in transit?

**Q38.** You discover that a resource in AWS was modified manually (someone changed a security group rule via the Console). Terraform doesn't know about this change. How do you detect drift? What are your options for resolving it — and what factors influence which option you choose?

**Q39.** An engineer accidentally ran `terraform state rm aws_db_instance.postgres` on the production state. The RDS instance still exists in AWS but Terraform no longer tracks it. Describe the recovery process. What is the blast radius, and how would you prevent this from happening again?

---

## Section 7: Module Design — Advanced (5 questions)

**Q40.** Our backup module uses `lifecycle { precondition }` to validate that retention periods satisfy AWS constraints:
```hcl
lifecycle {
  precondition {
    condition     = var.monthly_retention_days >= var.cold_storage_after_days + 90
    error_message = "Monthly retention must be >= cold_storage_after + 90 days."
  }
}
```
What is the difference between variable `validation` blocks, `precondition`, and `postcondition`? When would you use each? Can you give a scenario where `postcondition` is the only correct choice?

**Q41.** You are publishing a module to a private Terraform registry for other teams to consume. How do you handle **breaking changes** (e.g., renaming a variable)? Describe a complete versioning and communication strategy that doesn't break consumers.

**Q42.** Our modules don't use `terraform_remote_state` data source — instead, module outputs are passed directly via module composition in `main.tf`. Why is direct composition preferred over `terraform_remote_state`? When is `terraform_remote_state` actually appropriate?

**Q43.** A module currently works for a single environment. You need to deploy it to dev, staging, and prod with different configurations. Compare three approaches:
- A) Copy-paste the module call three times with different variables
- B) Use `for_each` on the module block
- C) Use separate directories per environment

What are the trade-offs of each? What would you recommend for a team of 10?

**Q44.** Our backup module creates its own KMS key internally. The database module also creates its own KMS key. A security architect asks: "Should we have a centralized KMS module that all other modules reference?" Analyze this proposal — what are the benefits and risks?

---

## Section 8: Troubleshooting & Edge Cases (6 questions)

**Q45.** You run `terraform plan` and see `~ (forces replacement)` on the RDS instance due to a change in `engine_version`. What does "forces replacement" mean for a database? How would you handle this in production to avoid data loss?

**Q46.** Terraform apply fails with the error:
```
Error: creating IAM Role: LimitExceededException: 
Cannot exceed quota for RolesPerAccount: 1000
```
How do you resolve this? What does this tell you about how the infrastructure has been managed?

**Q47.** A module that has been working for months suddenly fails during `terraform init` with:
```
Error: Failed to query available provider packages
│ Could not retrieve the list of available versions for provider hashicorp/aws
```
What are the possible causes? How do you make your Terraform configuration resilient to registry outages?

**Q48.** You run `terraform plan` and see **200+ changes** even though you only modified one variable. What could cause Terraform to show a "blast radius" much larger than expected? How do you investigate which change is cascading?

**Q49.** Your team uses a shared S3 bucket for state, and one morning you discover the state file is 0 bytes (corrupted/empty). How do you recover? What preventive measures should have been in place?

**Q50.** A colleague submits a PR that adds a `provisioner "local-exec"` block to run a database migration script after RDS creation. What are your concerns with this approach? What alternatives would you suggest?

---

## Section 9: Strategic Thinking (4 questions)

**Q51.** You join a company that manages 50+ AWS accounts with no IaC — everything was created via Console. You're tasked with "terraforming" the infrastructure. Describe your strategy. What do you import first? How do you structure the project? What is your 3-month roadmap?

**Q52.** Your CTO asks: "Why don't we just use AWS CloudFormation instead of Terraform? It's native to AWS and we only use AWS." How do you respond? Be balanced — give honest pros and cons of each.

**Q53.** A startup with 3 engineers asks you to set up their Terraform workflow. An enterprise with 50 engineers asks the same thing. How would your recommendations differ? Focus on state management, module governance, and pipeline design.

**Q54.** You are reviewing another team's Terraform code and notice they have:
- No tests
- No `.checkov.yml`
- No `CHANGELOG.md`
- Hardcoded values everywhere
- One massive `main.tf` with 800+ lines
- State stored in a local file

How do you prioritize improvements? What do you fix first, second, third? Justify your ordering.

---

## Question Distribution

| Section | Part | Level | Count |
|---------|------|-------|-------|
| Terraform Fundamentals | A | Junior–Mid | 7 |
| State Management Basics | A | Junior–Mid | 5 |
| Module Design Basics | A | Junior–Mid | 6 |
| Day-to-Day Ops & Team Workflow | A | Junior–Mid | 8 |
| Architecture & Blast Radius | B | Senior+ | 8 |
| State Management Advanced | B | Senior+ | 5 |
| Module Design Advanced | B | Senior+ | 5 |
| Troubleshooting & Edge Cases | B | Senior+ | 6 |
| Strategic Thinking | B | Senior+ | 4 |
| **Total** | | | **54** |

> **Evaluation criteria:**
> - **Technical accuracy** — Is the answer correct?
> - **Depth of understanding** — Do you understand *why*, not just *what*?
> - **Blast radius awareness** — Do you think about what can go wrong?
> - **Trade-off analysis** — Can you compare approaches objectively?
> - **Real-world experience** — Can you relate answers to actual situations?
