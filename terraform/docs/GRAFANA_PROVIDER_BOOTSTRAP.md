# 🐔🥚 Grafana Provider Bootstrap — Chicken-and-Egg Problem

*Tài liệu kỹ thuật giải thích vấn đề circular dependency giữa `provider "grafana"` và `module.amg`, kèm 2 hướng giải quyết: 2-phase apply (ngắn hạn) và tách state (khuyến nghị production).*

> **✅ Status:** Giải pháp 2 (tách state) đã được triển khai tại [`control-plane/lab-grafana/`](../control-plane/lab-grafana/). Giải pháp 1 (2-phase apply) được giữ lại làm tài liệu tham khảo.

---

## 📍 Vấn đề

[control-plane/lab/amg.tf](../control-plane/lab/amg.tf) khai báo `provider "grafana"` ngay trong cùng root module với `module.amg`:

```hcl
module "amg" {
  source = "../../modules/observability/amg"
  # ...
}

provider "grafana" {
  url  = "https://${module.amg.workspace_endpoint}"   # ← output của module.amg
  auth = module.amg.service_account_token              # ← output của module.amg
}

resource "grafana_data_source" "prometheus" {
  # ... dùng provider "grafana" ở trên
}
```

**Vấn đề cốt lõi:** Terraform cần **cấu hình xong toàn bộ provider blocks** (bao gồm resolve giá trị `url`/`auth`) **trước khi** build dependency graph để plan bất kỳ resource nào — kể cả resource không thuộc provider đó. Nhưng `url` và `auth` lại phụ thuộc vào output của `module.amg`, output này chỉ có **sau khi** `aws_grafana_workspace` + `aws_grafana_workspace_service_account_token` được apply.

```mermaid
graph LR
    A["terraform plan"] --> B{"Configure providers"}
    B --> C["provider grafana<br/>cần module.amg.workspace_endpoint"]
    C --> D["module.amg chưa apply<br/>→ output = unknown"]
    D --> E["❌ Error: Invalid provider configuration<br/>(hoặc plan với giá trị rỗng → apply fail)"]
```

### Triệu chứng thực tế khi chạy `terraform apply` lần đầu (workspace mới, chưa có state)

```
│ Error: Invalid provider configuration
│
│ Provider "registry.terraform.io/grafana/grafana" requires explicit
│ configuration. Add a provider block to the root module and configure
│ the provider's required arguments as described in the documentation.
```

Hoặc nếu Terraform "chấp nhận" plan với giá trị unknown, resource `grafana_data_source.*` sẽ fail ở bước apply với lỗi 401/connection refused vì `url`/`auth` rỗng.

---

## ✅ Giải pháp 1 (Ngắn hạn / Lab): 2-Phase Apply

Không thay đổi code — chỉ thay đổi **quy trình apply**. Dùng `-target` để buộc Terraform tạo xong AMG workspace + token trước, sau đó apply toàn bộ.

### Quy trình

```bash
cd terraform/control-plane/lab

# Phase 1: Chỉ tạo AMG workspace + IAM role + service account token
# (module.amg không phụ thuộc gì từ grafana provider nên apply được ngay)
terraform apply -target=module.amg

# Phase 2: Apply toàn bộ — lúc này module.amg đã có output thật,
# provider "grafana" configure thành công, grafana_data_source.* apply được
terraform apply
```

### Khi nào phải lặp lại Phase 1?

- Lần đầu tạo workspace mới (`terraform init` mới, state trống).
- Sau khi `terraform destroy` toàn bộ rồi tạo lại.
- Sau khi **xóa thủ công** `aws_grafana_workspace` hoặc `aws_grafana_workspace_service_account_token` khỏi state (`terraform state rm`).

Trong CI/CD pipeline, bước "Phase 1" nên được thêm như một **pre-apply step riêng** (không phải `terraform plan` chung), vì `-target` luôn tạo ra một partial plan gây warning trong CI nếu không handle rõ ràng:

```yaml
# Ví dụ GitHub Actions step (minh họa — pipeline thật ở Phase 3 ROADMAP)
- name: Bootstrap AMG workspace (idempotent — no-op nếu đã tồn tại)
  run: terraform apply -target=module.amg -auto-approve
  continue-on-error: true   # workspace đã tồn tại → apply -target là no-op, không lỗi

- name: Full apply
  run: terraform apply -auto-approve
```

### Trade-offs

| Ưu điểm | Nhược điểm |
|---|---|
| Không cần thay đổi cấu trúc code/state | Vi phạm nguyên tắc "1 lệnh apply duy nhất" của IaC — dễ quên bước Phase 1 khi teammate mới join |
| Áp dụng được ngay, không cần thêm backend config | `-target` che khuất một phần dependency graph thật — rủi ro drift nếu dùng lặp lại nhiều lần |
| Phù hợp cho Lab/Dev — tốc độ ưu tiên hơn structure | Không scale tốt khi nhiều người cùng apply — dễ conflict thứ tự |

---

## 🏗️ Giải pháp 2 (Khuyến nghị Production): Tách State

Root cause thật sự là **`module.amg` (hạ tầng AWS) và `grafana_data_source.*` (cấu hình bên trong Grafana) đang sống chung 1 state/1 root module**, dù chúng thuộc 2 "tốc độ thay đổi" khác nhau và có quan hệ phụ thuộc một chiều rõ ràng (data source **luôn** cần workspace tồn tại trước).

### Kiến trúc đề xuất

```
control-plane/lab/                 ← State hiện tại: VPC, IAM, RDS, ECS Cluster, AMP, AMG (workspace only)
    amg.tf                         ← CHỈ còn module "amg" (bỏ toàn bộ provider "grafana" + grafana_data_source.*)

control-plane/lab-grafana/         ← State MỚI: Grafana config (data sources, dashboards, alert rules)
    main.tf                        ← đọc AMP endpoint qua SSM
    providers.tf                   ← provider "grafana" (đọc AMG endpoint + token qua SSM)
    variables.tf                   ← aws_region, project_name, environment
    outputs.tf                     ← datasource_uids map
    backend.tf                     ← S3 backend (cùng bucket, khác key)
```

### Cross-state communication: SSM (không dùng `terraform_remote_state`)

Thay vì đọc toàn bộ state file qua `terraform_remote_state` (cần `s3:GetObject` → expose toàn bộ state), `lab-grafana` đọc SSM Parameters — giống pattern Data Plane đang dùng:

```
/{project}/{env}/observability/amg_endpoint                  ← String  (AMG module export)
/{project}/{env}/observability/amg_service_account_token      ← SecureString + KMS (AMG module export)
/{project}/{env}/observability/amp_endpoint                   ← String  (AMP module export)
```

### `control-plane/lab-grafana/providers.tf`

```hcl
data "aws_ssm_parameter" "amg_endpoint" {
  name = "/${var.project_name}/${var.environment}/observability/amg_endpoint"
}

data "aws_ssm_parameter" "amg_service_account_token" {
  name            = "/${var.project_name}/${var.environment}/observability/amg_service_account_token"
  with_decryption = true
}

provider "grafana" {
  url  = "https://${data.aws_ssm_parameter.amg_endpoint.value}"
  auth = data.aws_ssm_parameter.amg_service_account_token.value
}
```

> ✅ Token được lưu dạng `SecureString` trong SSM (KMS-encrypted). Principal chỉ cần `ssm:GetParameter` + `kms:Decrypt` trên key cụ thể, không cần `s3:GetObject` trên toàn bộ state file.

### `control-plane/lab-grafana/main.tf`

```hcl
data "aws_ssm_parameter" "amp_endpoint" {
  name = "/${var.project_name}/${var.environment}/observability/amp_endpoint"
}

resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Amazon Managed Prometheus"
  uid        = "amp-datasource"
  is_default = true

  url                = data.aws_ssm_parameter.amp_endpoint.value
  basic_auth_enabled = false

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigV4Auth     = true
    sigV4AuthType = "workspace-iam-role"
    sigV4Region   = var.aws_region
    timeInterval  = "15s"
  })
}

# ... xray, cloudwatch data sources tương tự
```

### Quy trình apply (không còn 2-phase thủ công)

```bash
# 1. Apply control-plane (AMG workspace được tạo xong, output có giá trị thật)
cd terraform/control-plane/lab
terraform apply

# 2. Apply grafana config (đọc remote state đã "chín" — không còn unknown)
cd ../lab-grafana
terraform init    # chỉ cần lần đầu
terraform apply
```

Đây **vẫn là 2 lệnh apply**, nhưng khác biệt cốt lõi so với Giải pháp 1:
- Không dùng `-target` (partial plan) — mỗi state tự plan đầy đủ dependency graph của nó.
- Ranh giới rõ ràng theo **tốc độ thay đổi**: AMG workspace hiếm khi đổi (tháng/quý), data source config có thể đổi thường xuyên hơn (thêm dashboard, đổi data source mới) — tách state giúp blast radius nhỏ hơn khi apply nhầm.
- Đúng nguyên tắc *Control Plane vs Data Plane Boundary* đã định nghĩa trong [ROADMAP.md](../ROADMAP.md) — coi `grafana_data_source` như một "Data Plane" nhỏ của riêng AMG.

### Trade-offs

| Ưu điểm | Nhược điểm |
|---|---|
| Không còn circular dependency — mỗi state tự đủ điều kiện apply | Thêm 1 state file, 1 backend key, 1 thư mục cần maintain |
| Blast radius nhỏ: sửa dashboard data source không đụng tới VPC/IAM/RDS state | Cross-state dependency qua SSM — cần đồng bộ SSM path convention |
| Dễ áp dụng CI/CD riêng cho từng state (khác tốc độ approve) | Cần IAM `ssm:GetParameter` + `kms:Decrypt` cho pipeline chạy `lab-grafana` |
| Token truyền qua SSM SecureString (KMS) — không expose toàn bộ state | Thêm 3 SSM parameters (chi phí không đáng kể) |

---

## 🔐 Rủi ro còn lại

`aws_grafana_workspace_service_account_token` là **admin token** vẫn tồn tại dạng plaintext trong Terraform state file của `control-plane/lab/` (dù output có `sensitive = true`, giá trị vẫn nằm trong state file, chỉ bị che khi hiển thị ở CLI/UI).

**Đã giảm thiểu:**
- [backend.tf](../control-plane/lab/backend.tf) dùng S3 + KMS CMK encryption at-rest.
- `lab-grafana` **không đọc state file trực tiếp** — dùng SSM SecureString thay vì `terraform_remote_state`, giảm blast radius từ "toàn bộ state" xuống "1 SSM key cụ thể".

**Production nên bổ sung:**
1. IAM policy giới hạn `ssm:GetParameter` trên path `/.../amg_service_account_token` chỉ cho CI/CD role.
2. SSM Parameter Store resource policy nếu cần cross-account access.

---

## 📋 Khuyến nghị

| Môi trường | Giải pháp |
|---|---|
| **Lab (đã triển khai)** | Giải pháp 2 (tách state) — [`control-plane/lab-grafana/`](../control-plane/lab-grafana/) |
| **Production (Phase 3 — PR-Driven IaC)** | Giải pháp 2 (tách state) — bắt buộc trước khi đưa vào CI/CD pipeline, tránh `-target` trong pipeline tự động (anti-pattern, che khuất plan thật) |
