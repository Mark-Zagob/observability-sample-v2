terraform {
  backend "s3" {
    bucket         = "obs-terraform-state-730335245469" # ← Cùng bucket, nhưng KHÁC key
    key            = "data-plane/payment-service/terraform.tfstate" # ← State của riêng Payment
    region         = "ap-southeast-2"
    use_lockfile   = true
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-southeast-2:730335245469:alias/obs-terraform-state"
  }
}