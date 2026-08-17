#--------------------------------------------------------------
# Logging Module — Athena / Glue Catalog
#--------------------------------------------------------------
# Pre-configured Glue table with partition projection so
# Athena queries work immediately without MSCK REPAIR TABLE
# or Glue crawlers.
#
# Partition projection automatically infers partitions from
# the S3 path structure that VPC Flow Logs creates:
#   s3://bucket/AWSLogs/{account}/vpcflowlogs/{region}/{year}/{month}/{day}/
#
# Example query:
#   SELECT srcaddr, dstaddr, dstport, action, protocol
#   FROM vpc_flow_logs
#   WHERE region = 'ap-southeast-2'
#     AND date = '2025/01/15'
#     AND action = 'REJECT'
#   ORDER BY packets DESC
#   LIMIT 100;
#
# Reference: AWS Athena VPC Flow Logs documentation
#--------------------------------------------------------------

resource "aws_glue_catalog_database" "flow_logs" {
  name        = replace("${var.project_name}_flow_logs", "-", "_")
  description = "VPC Flow Logs analysis database — ${local.identifier}"
}

resource "aws_glue_catalog_table" "flow_logs" {
  name          = "vpc_flow_logs"
  database_name = aws_glue_catalog_database.flow_logs.name
  description   = "VPC Flow Logs with partition projection (auto-partitioned)"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    # Enable partition projection (no crawlers needed)
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2024/01/01,NOW"
    "projection.date.format"        = "yyyy/MM/dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "projection.region.type"        = "enum"
    "projection.region.values"      = local.region
    "projection.account_id.type"    = "enum"
    "projection.account_id.values"  = local.account_id

    # Storage location with partition template
    "storage.location.template" = "s3://${aws_s3_bucket.flow_logs.id}/AWSLogs/$${account_id}/vpcflowlogs/$${region}/$${date}"

    "classification"         = "csv"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.flow_logs.id}/AWSLogs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters = {
        "serialization.format" = " "
        "field.delim"          = " "
      }
    }

    # VPC Flow Logs v2 default fields
    # https://docs.aws.amazon.com/vpc/latest/userguide/flow-log-records.html
    columns {
      name = "version"
      type = "int"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "interface_id"
      type = "string"
    }
    columns {
      name = "srcaddr"
      type = "string"
    }
    columns {
      name = "dstaddr"
      type = "string"
    }
    columns {
      name = "srcport"
      type = "int"
    }
    columns {
      name = "dstport"
      type = "int"
    }
    columns {
      name = "protocol"
      type = "bigint"
    }
    columns {
      name = "packets"
      type = "bigint"
    }
    columns {
      name = "bytes"
      type = "bigint"
    }
    columns {
      name = "start"
      type = "bigint"
    }
    columns {
      name = "end_time"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "log_status"
      type = "string"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
  partition_keys {
    name = "region"
    type = "string"
  }
  partition_keys {
    name = "account_id"
    type = "string"
  }
}

#--------------------------------------------------------------
# Athena Workgroup — Query Result Management
#--------------------------------------------------------------
# Dedicated workgroup for flow log queries with:
# - Encrypted query results (same KMS key)
# - Auto-cleanup of results after N days
# - Cost control via query result reuse
#--------------------------------------------------------------

resource "aws_athena_workgroup" "flow_logs" {
  name        = "${var.project_name}-flow-logs"
  description = "VPC Flow Logs analysis workgroup"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.flow_logs.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.flow_logs_s3.arn
      }
    }
  }

  tags = merge(var.common_tags, {
    Name      = "${local.identifier}-athena-workgroup"
    Component = "logging"
  })
}
