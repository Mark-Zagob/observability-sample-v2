#--------------------------------------------------------------
# Grafana Config — Variables
#--------------------------------------------------------------
# KHÔNG dùng default — bắt buộc set qua terraform.auto.tfvars, đồng bộ
# 1-1 với control-plane/lab/terraform.auto.tfvars. Lý do: nếu project_name/
# environment/aws_region lệch giữa 2 state, SSM path đọc ở đây
# (/${project_name}/${environment}/observability/*) sẽ trỏ sai và fail
# với lỗi "ParameterNotFound" khó truy ra nguyên nhân gốc là do drift
# giữa 2 tfvars, không phải do thiếu prerequisite.

variable "project_name" {
  description = "Project name for tagging — PHẢI trùng với control-plane/lab"
  type        = string
}

variable "environment" {
  description = "Environment name — PHẢI trùng với control-plane/lab"
  type        = string
}

variable "aws_region" {
  description = "AWS region — PHẢI trùng với control-plane/lab"
  type        = string
}
