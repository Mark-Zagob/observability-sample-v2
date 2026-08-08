#--------------------------------------------------------------
# Bootstrap Migration Module — Main
#--------------------------------------------------------------
# Purpose: Run one-shot ECS Fargate task to bootstrap RDS schema
# Pattern: Control Plane → Migration Plane → Data Plane
#
# Flow:
#   1. Terraform creates task definition + IAM role
#   2. null_resource triggers `aws ecs run-task`
#   3. Task reads secret, connects to RDS, runs init-app.sql
#   4. Exit 0 → Terraform continues (app deploy proceeds)
#   5. Exit 1 → Terraform fails (app deploy blocked)
#--------------------------------------------------------------

resource "aws_cloudwatch_log_group" "migration" {
  name              = "/ecs/${var.project_name}/${var.environment}/migration"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-migration-logs"
    Purpose = "database-bootstrap"
  })
}

resource "aws_ecs_task_definition" "migration" {
  family                   = "${var.project_name}-${var.environment}-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.migration.arn

  container_definitions = jsonencode([{
    name      = "migration"
    image     = var.migration_image
    essential = true

    environment = [
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_PORT", value = tostring(var.db_port) },
      { name = "DB_SECRET_ARN", value = var.db_secret_arn },
      { name = "APP_USER_SECRET_ARN", value = var.app_user_secret_arn },
      { name = "AWS_REGION", value = var.aws_region }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.migration.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "migration"
      }
    }
  }])

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-migration-task"
    Purpose = "database-bootstrap"
  })
}

# --------------------------------------------------------------
# ⚠️ TECH DEBT: local-exec provisioner
# --------------------------------------------------------------
# Current State (Phase 2.1):
#   - Runs on developer's laptop via `terraform apply`
#   - Requires AWS CLI installed locally
#   - No retry mechanism at Terraform level
#
# Migration Path:
#   Phase 3 (CI/CD): Move to GitHub Actions step with retry
#   Phase 7 (EKS):   Migrate to ArgoCD PreSync hook
#
# Why acceptable now:
#   - Learning phase, manual apply is OK
#   - Migration task itself is idempotent (safe to re-run)
#   - Blast radius: only affects this module, not entire infra
#
# See: docs/ADR-019_migration_orchestration.md
# --------------------------------------------------------------
resource "null_resource" "run_migration" {
  depends_on = [aws_ecs_task_definition.migration]

  triggers = {
    # Re-run when task definition changes, SQL content changes, or RDS is recreated
    task_definition_arn = aws_ecs_task_definition.migration.arn
    migration_sql_hash  = var.migration_sql_hash
    db_instance_arn     = var.db_instance_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "🚀 Running database migration task..."

      TASK_ARN=$(aws ecs run-task \
        --cluster ${var.ecs_cluster_name} \
        --task-definition ${aws_ecs_task_definition.migration.arn} \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${join(",", var.private_subnet_ids)}],securityGroups=[${var.security_group_id}],assignPublicIp=DISABLED}" \
        --region ${var.aws_region} \
        --query 'tasks[0].taskArn' \
        --output text)

      echo "Task ARN: $TASK_ARN"
      echo "⏳ Waiting for migration task (max 10 minutes)..."

      # timeout prevents infinite hang if task stuck in PENDING/PROVISIONING
      timeout 600 aws ecs wait tasks-stopped \
        --cluster ${var.ecs_cluster_name} \
        --tasks "$TASK_ARN" \
        --region ${var.aws_region} || {
          echo "❌ Migration task timed out after 600s — stopping task"
          aws ecs stop-task --cluster ${var.ecs_cluster_name} \
            --task "$TASK_ARN" --region ${var.aws_region}
          exit 1
        }

      EXIT_CODE=$(aws ecs describe-tasks \
        --cluster ${var.ecs_cluster_name} --tasks "$TASK_ARN" \
        --region ${var.aws_region} \
        --query 'tasks[0].containers[0].exitCode' --output text)
      STOP_REASON=$(aws ecs describe-tasks \
        --cluster ${var.ecs_cluster_name} --tasks "$TASK_ARN" \
        --region ${var.aws_region} \
        --query 'tasks[0].stoppedReason' --output text)

      if [ "$EXIT_CODE" != "0" ]; then
        echo "❌ Migration FAILED (exit code: $EXIT_CODE)"
        echo "   Reason: $STOP_REASON"
        echo "   Logs: ${aws_cloudwatch_log_group.migration.name}"
        # SSM Gate: signal failure to Data Plane
        aws ssm put-parameter \
          --name "/${var.project_name}/${var.environment}/migration/status" \
          --value "FAILED" --type "String" --overwrite \
          --region ${var.aws_region} || true
        exit 1
      fi

      # SSM Gate: signal success to Data Plane
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/migration/status" \
        --value "SUCCESS" --type "String" --overwrite \
        --region ${var.aws_region}
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/migration/schema_version" \
        --value "2.1.0" --type "String" --overwrite \
        --region ${var.aws_region}
      aws ssm put-parameter \
        --name "/${var.project_name}/${var.environment}/migration/last_success" \
        --value "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --type "String" --overwrite \
        --region ${var.aws_region}

      echo "✅ Migration completed successfully"
      echo "🔓 Migration gate updated: status=SUCCESS, version=2.1.0"
    EOT
  }
}
