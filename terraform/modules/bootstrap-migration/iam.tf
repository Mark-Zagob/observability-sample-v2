#--------------------------------------------------------------
# Bootstrap Migration Module — IAM
#--------------------------------------------------------------
# Dedicated migration role: Secrets Manager read + KMS decrypt
# Principle of Least Privilege: NO EC2, NO S3, NO ECS control
# App roles (Data Plane) should only have DML — this role has DDL
#--------------------------------------------------------------

resource "aws_iam_role" "migration" {
  name = "${var.project_name}-${var.environment}-migration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-migration-role"
    Purpose = "database-bootstrap"
  })
}

resource "aws_iam_role_policy" "migration" {
  name = "${var.project_name}-${var.environment}-migration-policy"
  role = aws_iam_role.migration.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read database secret (for psql authentication)
      {
        Sid    = "ReadDatabaseSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.db_secret_arn]
      },
      # Decrypt KMS key (secrets are KMS-encrypted)
      {
        Sid    = "DecryptKMSKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}
