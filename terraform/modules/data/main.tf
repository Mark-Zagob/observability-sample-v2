#--------------------------------------------------------------
# Data Module - RDS, ElastiCache (Redis), MSK (Kafka)
#--------------------------------------------------------------

#--------------------------------------------------------------
# Subnet Groups
#--------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-redis-subnet-group"
  })
}

#--------------------------------------------------------------
# RDS PostgreSQL
#--------------------------------------------------------------

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "16.4"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.data_security_group_id]

  # Cost-saving: single AZ, no multi-AZ
  multi_az = false

  # Disable backups for lab (cost saving)
  backup_retention_period = 0
  skip_final_snapshot     = true

  # Performance monitoring (free tier)
  performance_insights_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-postgres"
  })
}

#--------------------------------------------------------------
# ElastiCache Redis
#--------------------------------------------------------------

resource "aws_elasticache_cluster" "redis" {
  cluster_id      = "${var.project_name}-redis"
  engine          = "redis"
  engine_version  = "7.1"
  node_type       = var.redis_node_type
  num_cache_nodes = 1

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.data_security_group_id]

  # Lab: no automatic snapshots
  snapshot_retention_limit = 0

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-redis"
  })
}

#--------------------------------------------------------------
# MSK (Managed Kafka)
#--------------------------------------------------------------

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.project_name}-kafka"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.kafka_broker_count

  broker_node_group_info {
    instance_type  = var.kafka_instance_type
    client_subnets = slice(var.data_subnet_ids, 0, var.kafka_broker_count)

    storage_info {
      ebs_storage_info {
        volume_size = var.kafka_ebs_volume_size
      }
    }

    security_groups = [var.data_security_group_id]
  }

  # Plaintext for lab simplicity
  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = false
    }
  }

  # Basic monitoring (free)
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = false
        log_group = ""
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-kafka"
  })
}
