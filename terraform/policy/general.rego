# =============================================================
# General Infrastructure Policies
# =============================================================
# Kiểm tra: tagging, naming conventions, cost guard
#
# =============================================================
# REGO v1 SYNTAX GUIDE
# =============================================================
#
# import rego.v1        = bật Rego v1 syntax (bắt buộc)
# some x in collection  = lặp qua từng item (thay cho x := collection[_])
# deny contains msg if  = partial set rule (thay cho deny[msg])
# warn contains msg if  = warning rule
#
# Cách đọc rule:
#   deny contains msg if {
#     <điều kiện 1>    ← VÀ (AND)
#     <điều kiện 2>    ← VÀ (AND)
#     msg := "..."     ← message khi TẤT CẢ điều kiện TRUE
#   }
#
# Tất cả dòng trong {} = AND logic.
# Nhiều rule `deny contains msg if` = OR logic.
# =============================================================

package terraform.general

import rego.v1

# Danh sách tags bắt buộc
required_tags := ["Project", "Environment", "ManagedBy"]

# Danh sách resource types cần check tags
taggable_types := [
    "aws_db_instance",
    "aws_s3_bucket",
    "aws_kms_key",
    "aws_dynamodb_table",
    "aws_cloudwatch_log_group",
    "aws_secretsmanager_secret",
]

# ----- DENY: Resources phải có required tags -----

deny contains msg if {
    some rc in input.resource_changes
    rc.mode == "managed"
    rc.type in taggable_types

    # Chỉ check khi resource đang được tạo hoặc update
    some action in rc.change.actions
    action != "delete"

    # Dùng tags_all (bao gồm cả default_tags từ provider)
    # tags = chỉ resource-level tags
    # tags_all = tags + default_tags ← dùng cái này
    tags := rc.change.after.tags_all
    some tag in required_tags
    not tags[tag]

    msg := sprintf(
        "🔴 [COMPLIANCE] Resource '%s' (%s) thiếu required tag '%s'",
        [rc.address, rc.type, tag]
    )
}

# ----- DENY: Không cho tạo resources quá đắt -----

expensive_rds_classes := [
    "db.r5.4xlarge",  "db.r5.8xlarge",  "db.r5.12xlarge",
    "db.r6g.4xlarge", "db.r6g.8xlarge", "db.r6g.12xlarge",
    "db.r7g.4xlarge", "db.r7g.8xlarge",
]

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    instance_class := rc.change.after.instance_class
    instance_class in expensive_rds_classes
    msg := sprintf(
        "🔴 [COST] RDS '%s' dùng instance class '%s' quá đắt. Cần approval.",
        [rc.address, instance_class]
    )
}

# ----- WARN: Naming convention -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_db_instance"
    rc.mode == "managed"
    identifier := rc.change.after.identifier
    not startswith(identifier, "obs")
    msg := sprintf(
        "🟡 [NAMING] RDS '%s' có identifier '%s' không bắt đầu bằng 'obs'",
        [rc.address, identifier]
    )
}
