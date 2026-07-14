#--------------------------------------------------------------
# Grafana Config — Backend Configuration
#--------------------------------------------------------------
# State tách riêng với control-plane/lab/ để giải quyết
# chicken-and-egg problem giữa provider "grafana" và module.amg.
# Chi tiết: docs/GRAFANA_PROVIDER_BOOTSTRAP.md
#--------------------------------------------------------------

terraform {
  backend "s3" {
    bucket       = "obs-terraform-state-730335245469"
    key          = "control-plane/lab-grafana/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
    kms_key_id   = "arn:aws:kms:ap-southeast-2:730335245469:alias/obs-terraform-state"
  }
}
