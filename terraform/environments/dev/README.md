# Dev Environment — Terraform Cloud Backend

Test environment dùng Terraform Cloud để quản lý state.

## So sánh với Shared (S3 backend)

| Aspect | shared/ (S3) | dev/ (TFC) |
|--------|-------------|-----------|
| State storage | S3 bucket (self-managed) | Terraform Cloud (HashiCorp) |
| State locking | DynamoDB | Built-in |
| Encryption | KMS CMK | Built-in AES-256 |
| Run history | ❌ | ✅ Web UI |
| Cost | ~$1/month | Free (500 resources) |

## Setup

```bash
# 1. Login to Terraform Cloud
terraform login
# → Opens browser → Generate API token → Paste token

# 2. Create workspace in TFC UI
# https://app.terraform.io → Workspaces → New → "obs-dev"
# Workflow: CLI-driven
# Execution Mode: Local (Settings → General)

# 3. Init and apply
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

## Execution Mode khác nhau

### Local (recommended for learning)
- `plan`/`apply` chạy trên **máy bạn**
- State lưu trên **TFC**
- AWS credentials từ **local CLI** (`~/.aws/credentials`)

### Remote (production pattern)
- `plan`/`apply` chạy trên **TFC server**
- AWS credentials phải set trong **TFC workspace variables**:
  - `AWS_ACCESS_KEY_ID` (sensitive)
  - `AWS_SECRET_ACCESS_KEY` (sensitive)
  - `AWS_REGION` = `ap-southeast-2`

## VPC CIDR

Dev dùng `10.1.0.0/16` để tránh conflict với shared (`10.0.0.0/16`).
