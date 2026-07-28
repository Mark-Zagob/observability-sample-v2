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

resource "null_resource" "run_migration" {
  depends_on = [aws_ecs_task_definition.migration]

  triggers = {
    # Re-run when task definition changes OR when SQL content changes
    task_definition_arn = aws_ecs_task_definition.migration.arn
    migration_sql_hash = var.migration_sql_hash
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

      echo "⏳ Waiting for migration task to complete (timeout: 10 minutes)..."
      aws ecs wait tasks-stopped \
        --cluster ${var.ecs_cluster_name} \
        --tasks "$TASK_ARN" \
        --region ${var.aws_region}

      # Check exit code
      EXIT_CODE=$(aws ecs describe-tasks \
        --cluster ${var.ecs_cluster_name} \
        --tasks "$TASK_ARN" \
        --region ${var.aws_region} \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)

      STOP_REASON=$(aws ecs describe-tasks \
        --cluster ${var.ecs_cluster_name} \
        --tasks "$TASK_ARN" \
        --region ${var.aws_region} \
        --query 'tasks[0].stoppedReason' \
        --output text)

      if [ "$EXIT_CODE" != "0" ]; then
        echo "❌ Migration FAILED (exit code: $EXIT_CODE)"
        echo "   Reason: $STOP_REASON"
        echo "   Logs: ${aws_cloudwatch_log_group.migration.name}"
        exit 1
      fi

      echo "✅ Migration task completed successfully"
    EOT
  }
}
