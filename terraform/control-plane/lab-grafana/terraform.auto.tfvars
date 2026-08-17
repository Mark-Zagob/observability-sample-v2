#--------------------------------------------------------------
# Grafana Config — Values cho lab
#--------------------------------------------------------------
# PHẢI đồng bộ 1-1 với control-plane/lab/terraform.auto.tfvars —
# 2 state đọc/ghi chung 1 SSM namespace (/${project_name}/${environment}/*).
#--------------------------------------------------------------

project_name = "obs"
aws_region   = "ap-southeast-2"
environment  = "lab"
