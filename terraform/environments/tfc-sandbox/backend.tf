#--------------------------------------------------------------
# Dev Environment — Backend: Terraform Cloud
#--------------------------------------------------------------
# This environment uses Terraform Cloud for state management.
# Purpose: Learn TFC workflow (remote state, run history, UI).
#
# Setup:
#   1. Create TFC account: https://app.terraform.io/signup
#   2. Create organization (or use existing: Mark_Zagob)
#   3. Create workspace: "obs-dev" (CLI-driven workflow)
#   4. Set Execution Mode to "Local" in workspace settings
#      (Workspace → Settings → General → Execution Mode → Local)
#   5. Login: terraform login
#   6. Run: terraform init
#
# ⚠️ Execution Mode:
#   "local"  = plan/apply runs on YOUR machine, state stored on TFC
#              → Use this first (simpler, same as S3 backend experience)
#   "remote" = plan/apply runs on TFC servers
#              → Requires environment variables in TFC for AWS creds
#--------------------------------------------------------------

terraform {
  cloud {
    organization = "Mark_Zagob"

    workspaces {
      name = "observability-sample-v2"
    }
  }
}
