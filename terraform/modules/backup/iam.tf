#--------------------------------------------------------------
# Backup Module — IAM Role for AWS Backup
#--------------------------------------------------------------
# AWS Backup needs an IAM role to:
# - Take snapshots of RDS, EFS, etc.
# - Copy snapshots cross-region
# - Restore from recovery points
#
# Uses AWS managed policies — no custom policy needed.
# Reference: AWS Well-Architected REL09-BP01
#--------------------------------------------------------------

resource "aws_iam_role" "backup" {
  name = "${local.identifier}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBackupServiceAssume"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-role"
    Component = "backup"
  })
}

# AWS managed policy: covers RDS, EFS, EBS, DynamoDB, S3 backup operations
resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# AWS managed policy: covers restore operations
resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Additional: S3 backup support (separate managed policy)
resource "aws_iam_role_policy_attachment" "backup_s3" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "backup_s3_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}
