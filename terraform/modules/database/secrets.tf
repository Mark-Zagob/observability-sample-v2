#--------------------------------------------------------------
# Database Module — Secrets Management
#--------------------------------------------------------------
# Pattern: RDS Managed Secret (Level 3)
#
# AWS manages the master password lifecycle:
#   1. Creates secret in Secrets Manager automatically
#   2. Rotates password every 7 days
#   3. Encrypts with CMK (master_user_secret_kms_key_id)
#   4. No Lambda function needed
#
# App reads secret via:
#   aws_db_instance.postgres.master_user_secret[0].secret_arn
#
# Previous approach (Level 1 — manual):
#   random_password → aws_secretsmanager_secret → password arg
#   → No rotation, manual management, password in state file
#--------------------------------------------------------------

# Note: random_password and aws_secretsmanager_secret resources
# have been REMOVED. AWS RDS now manages the secret lifecycle
# via manage_master_user_password = true in rds.tf.
#
# The secret ARN is available at:
#   aws_db_instance.postgres.master_user_secret[0].secret_arn
#
# To retrieve the secret value in app code:
#   aws secretsmanager get-secret-value \
#     --secret-id <secret_arn> \
#     --query SecretString --output text
