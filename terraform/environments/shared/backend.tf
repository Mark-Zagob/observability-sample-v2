#--------------------------------------------------------------
# Shared Environment — Backend Configuration
#--------------------------------------------------------------
# Production-grade state management with S3 + DynamoDB.
#
# Migration from local state:
#   1. Run bootstrap: cd ../../bootstrap && terraform apply
#   2. Uncomment the S3 backend block below
#   3. Run: terraform init -migrate-state
#   4. Type "yes" when prompted
#--------------------------------------------------------------

#--------------------------------------------------------------
# OPTION 1: S3 + DynamoDB Backend (RECOMMENDED)
#--------------------------------------------------------------
# Production-grade for teams of any size.
# Features: KMS encryption, DynamoDB locking, S3 versioning.
#
# Uncomment after running bootstrap module:

# terraform {
#   backend "s3" {
#     #----------------------------------------------------------
#     # State Storage
#     #----------------------------------------------------------
#     bucket = "obs-terraform-state-ACCOUNT_ID"   # ← Replace with bootstrap output
#     key    = "shared/terraform.tfstate"          # ← Unique per environment
#     region = "ap-southeast-2"
#
#     #----------------------------------------------------------
#     # State Locking (prevent concurrent apply)
#     #----------------------------------------------------------
#     dynamodb_table = "terraform-state-locks"     # ← From bootstrap output
#
#     #----------------------------------------------------------
#     # Encryption at-rest (KMS CMK)
#     #----------------------------------------------------------
#     encrypt    = true
#     kms_key_id = "arn:aws:kms:ap-southeast-2:ACCOUNT_ID:alias/obs-terraform-state"  # ← From bootstrap
#
#     #----------------------------------------------------------
#     # Extra Security (optional but recommended)
#     #----------------------------------------------------------
#     # skip_metadata_api_check     = true    # Skip IMDS check in CI/CD
#     # skip_region_validation      = true    # Skip region validation
#   }
# }


#--------------------------------------------------------------
# OPTION 2: Terraform Cloud Backend (ALTERNATIVE)
#--------------------------------------------------------------
# Use this if you prefer HashiCorp-managed state with built-in
# UI, run history, cost estimation, and VCS integration.
#
# Prerequisites:
#   1. Create account: https://app.terraform.io/signup
#   2. Create organization: Settings → Organizations
#   3. Create workspace: Workspaces → New → CLI-driven
#   4. Login: terraform login
#   5. Uncomment below and run: terraform init -migrate-state
#
# Free tier: 500 managed resources (sufficient for this project).
#
# Features included:
#   ✅ Remote state storage (encrypted, versioned)
#   ✅ State locking (built-in, no DynamoDB needed)
#   ✅ Run history (every plan/apply recorded)
#   ✅ Cost estimation (per-resource cost before apply)
#   ✅ VCS integration (auto plan on git push)
#   ✅ Team access control (RBAC per workspace)
#   ✅ Sentinel policy-as-code (paid plan)
#
# ⚠️ IMPORTANT: cloud {} and backend {} are MUTUALLY EXCLUSIVE.
#    You CANNOT use both at the same time.

# terraform {
#   cloud {
#     #----------------------------------------------------------
#     # Organization (your Terraform Cloud org name)
#     #----------------------------------------------------------
#     organization = "Mark_Zagob"
#
#     #----------------------------------------------------------
#     # Workspace Configuration
#     #----------------------------------------------------------
#     # Option A: Single workspace (simple)
#     workspaces {
#       name = "obs-shared"
#     }
#
#     # Option B: Tag-based workspace selection (multi-env)
#     # Allows switching workspaces with: terraform workspace select
#     # workspaces {
#     #   tags = ["obs", "shared"]
#     # }
#
#     #----------------------------------------------------------
#     # Execution Mode
#     #----------------------------------------------------------
#     # "remote"  = plan/apply runs on TFC servers (default)
#     # "local"   = plan/apply runs locally, state stored on TFC
#     #
#     # For learning: use "local" first, then switch to "remote"
#     # Set in TFC UI: Workspace → Settings → General → Execution Mode
#   }
# }


#--------------------------------------------------------------
# OPTION 3: Multi-Environment Pattern (ADVANCED)
#--------------------------------------------------------------
# When you have dev/staging/prod, each environment gets its own
# state file. Use ONE of the patterns below:
#
# Pattern A: Separate key per environment (S3)
#   backend "s3" {
#     bucket = "obs-terraform-state-ACCOUNT_ID"   # SAME bucket
#     key    = "dev/terraform.tfstate"             # DIFFERENT key
#     key    = "staging/terraform.tfstate"
#     key    = "prod/terraform.tfstate"
#   }
#
# Pattern B: Separate workspace per environment (TFC)
#   cloud {
#     organization = "Mark_Zagob"
#     workspaces { name = "obs-dev" }
#     workspaces { name = "obs-staging" }
#     workspaces { name = "obs-prod" }
#   }
#
# Pattern C: Directory-based (most common)
#   environments/
#   ├── dev/backend.tf      → key = "dev/terraform.tfstate"
#   ├── staging/backend.tf  → key = "staging/terraform.tfstate"
#   └── prod/backend.tf     → key = "prod/terraform.tfstate"
#
# ⚠️ NEVER share state between environments.
#    Each environment = its own isolated state file.
#--------------------------------------------------------------
