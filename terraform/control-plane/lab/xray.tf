#--------------------------------------------------------------
# X-Ray — Custom Sampling Rules
#--------------------------------------------------------------
# Phase 1.5: Override implicit AWS "Default" sampling rule (1 req/s +
# 5%) cho các critical-path services — tránh mất trace quan trọng khi
# traffic thấp (lab) hoặc cần visibility cao hơn khi chạy Chaos Drills.
#
# `local.monitored_services` được định nghĩa ở observability.tf (dùng
# chung với CloudWatch Alarms) — cùng 1 danh sách service, 1 nguồn sự thật.
#--------------------------------------------------------------

module "xray" {
  source = "../../modules/observability/xray"

  project_name = var.project_name
  environment  = var.environment
  services     = local.monitored_services

  reservoir_size = 1
  # Lab: sample nhiều hơn để quan sát đầy đủ trace trong Chaos Drills.
  # Prod: giảm fixed_rate để tiết kiệm chi phí X-Ray (billed per trace).
  fixed_rate = var.environment == "prod" ? 0.05 : 0.3

  common_tags = {
    Module = "observability"
    Plane  = "Control"
  }
}
