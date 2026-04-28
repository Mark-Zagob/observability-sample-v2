# Basic Example — Backup Module

# Minimal usage (no DR, daily backup only):
module "backup_minimal" {
  source = "../../modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  project_name = "my-project"
  environment  = "dev"

  # Disable cross-region (minimal cost)
  enable_cross_region_copy = false
  enable_monthly_plan      = false

  # Short retention for dev
  daily_retention_days = 7

  common_tags = {
    Team = "platform"
  }
}

# Full production usage (DR + monthly + compliance vault lock):
module "backup_production" {
  source = "../../modules/backup"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  project_name = "my-project"
  environment  = "prod"

  # Compliance mode — nobody can delete backups
  vault_lock_mode              = "compliance"
  vault_lock_min_retention_days = 7
  vault_lock_max_retention_days = 400

  # Daily: 35 days
  daily_retention_days = 35

  # Monthly: 1 year, cold storage after 30 days
  enable_monthly_plan             = true
  monthly_retention_days          = 365
  monthly_cold_storage_after_days = 30

  # Cross-region DR copy
  enable_cross_region_copy        = true
  cross_region_copy_retention_days = 35

  # Team notification
  notification_email = "ops-team@company.com"

  common_tags = {
    Team        = "platform"
    CostCenter  = "infra"
    Compliance  = "SOC2"
  }
}
