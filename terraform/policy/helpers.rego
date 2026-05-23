# =============================================================
# Shared Helpers — Environment Detection & Utilities
# =============================================================
# Cung cấp hàm detect environment từ plan metadata.
#
# Cách hoạt động:
#   1. Tìm tag "Environment" trong bất kỳ resource nào
#   2. Nếu tìm thấy "production" hoặc "prod" → is_production = true
#   3. Nếu không tìm thấy → mặc định KHÔNG phải production
#
# Import: import data.terraform.helpers
# Sử dụng: helpers.is_production
# =============================================================

package terraform.helpers

import rego.v1

# Detect environment từ resource tags
detected_environments contains env if {
    some rc in input.resource_changes
    tags := object.get(rc.change.after, "tags_all", {})
    env := object.get(tags, "Environment", "")
    env != ""
}

# Production nếu bất kỳ resource nào có tag Environment = production/prod
is_production if {
    some env in detected_environments
    lower(env) == "production"
}

is_production if {
    some env in detected_environments
    lower(env) == "prod"
}

# Staging detection
is_staging if {
    some env in detected_environments
    lower(env) == "staging"
}

is_staging if {
    some env in detected_environments
    lower(env) == "stg"
}

# Dev detection
is_dev if {
    some env in detected_environments
    lower(env) == "dev"
}

is_dev if {
    some env in detected_environments
    lower(env) == "development"
}

# Default: nếu không detect được, coi là unknown (treated as production for safety)
is_unknown_env if {
    count(detected_environments) == 0
}

# Production-or-unknown = apply strict rules (safe default)
is_strict if {
    is_production
}

is_strict if {
    is_unknown_env
}
