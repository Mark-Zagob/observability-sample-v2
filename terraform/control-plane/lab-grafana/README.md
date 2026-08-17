# control-plane/lab-grafana

Root module con để tạo **Grafana data sources** (Prometheus/AMP, X-Ray, CloudWatch) trên workspace Amazon Managed Grafana (AMG) đã tạo ở `control-plane/lab/`.

## Vì sao tách state riêng?

`provider "grafana"` cần `url` (AMG endpoint) và `auth` (service account token) để khởi tạo. Cả hai giá trị này chỉ tồn tại **sau khi** `module.amg` trong `control-plane/lab/` đã apply xong. Nếu khai báo provider này chung state với `module.amg`, Terraform sẽ cố resolve provider config *trước khi* build dependency graph → apply lần đầu luôn fail ("chicken-and-egg problem").

Giải pháp: tách thành state riêng, đọc AMG endpoint + token qua **SSM Parameter Store** (do `lab/` ghi ra) thay vì qua Terraform outputs/`terraform_remote_state`. Cách này giảm blast radius: state này chỉ cần quyền `ssm:GetParameter` + `kms:Decrypt` trên đúng parameter cần dùng, không cần quyền đọc toàn bộ state file của `lab/`.

Chi tiết đầy đủ (kèm sơ đồ kiến trúc): xem [`../../docs/GRAFANA_PROVIDER_BOOTSTRAP.md`](../../docs/GRAFANA_PROVIDER_BOOTSTRAP.md).

## Prerequisite — BẮT BUỘC

`control-plane/lab/` phải được `apply` thành công **trước** state này, vì `providers.tf` đọc các SSM parameter sau ngay tại bước `plan`/`refresh` (không phải chỉ lúc apply):

- `/${project_name}/${environment}/observability/amg_endpoint`
- `/${project_name}/${environment}/observability/amg_service_account_token` (SecureString)
- `/${project_name}/${environment}/observability/amp_endpoint`

Nếu chạy `lab-grafana` trước khi các parameter trên tồn tại, `terraform plan`/`apply` sẽ fail với lỗi dạng:

```
Error: ParameterNotFound: ... /obs/lab/observability/amg_endpoint
```

→ Khắc phục: `cd ../lab && terraform apply` trước, rồi quay lại đây.

## Thứ tự chạy

```powershell
# 1. Đảm bảo control-plane/lab đã apply xong (module.amg đã tạo endpoint + token trong SSM)
cd ../lab
terraform apply

# 2. Chạy state này
cd ../lab-grafana
terraform init
terraform plan
terraform apply
```

## Inputs

`project_name`, `environment`, `aws_region` — **không có default**, phải khai báo qua `terraform.auto.tfvars` và **đồng bộ 1-1** với `control-plane/lab/terraform.auto.tfvars` (2 state dùng chung 1 SSM namespace `/${project_name}/${environment}/*`).

## Outputs

| Output            | Mô tả                                                |
| ------------------ | ----------------------------------------------------- |
| `datasource_uids`  | Map UID của 3 data source (prometheus/xray/cloudwatch) đã tạo trên AMG, dùng để tham chiếu khi tạo dashboard/alert qua Terraform hoặc script. |

## File structure

```
lab-grafana/
├── backend.tf      # S3 state riêng (control-plane/lab-grafana/terraform.tfstate)
├── providers.tf     # provider "grafana" — auth lấy từ SSM (ghi bởi lab/module.amg)
├── main.tf          # 3x grafana_data_source (prometheus, xray, cloudwatch)
├── variables.tf     # project_name / environment / aws_region — no default
├── terraform.auto.tfvars
└── outputs.tf
```
