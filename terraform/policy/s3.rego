# =============================================================
# S3 Security Policies
# =============================================================
# Kiểm tra: public access block, encryption, versioning
# =============================================================

package terraform.s3

import rego.v1

# ----- DENY: S3 phải block public access [CIS-AWS-2.1.5] [SOC2-CC6.6] -----

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_public_access_block"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]

    checks := {
        "block_public_acls":       rc.change.after.block_public_acls,
        "block_public_policy":     rc.change.after.block_public_policy,
        "ignore_public_acls":      rc.change.after.ignore_public_acls,
        "restrict_public_buckets": rc.change.after.restrict_public_buckets,
    }

    some field_name, value in checks
    value != true

    msg := sprintf(
        "🔴 [CRITICAL][CIS-AWS-2.1.5] S3 '%s' phải set %s = true",
        [rc.address, field_name]
    )
}

# Rule 2: S3 bucket phải có encryption [CIS-AWS-2.1.1] [SOC2-CC6.1]
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_server_side_encryption_configuration"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    not rc.change.after.rule
    msg := sprintf(
        "🔴 [CRITICAL][CIS-AWS-2.1.1] S3 '%s' phải có server-side encryption configuration",
        [rc.address]
    )
}

# ----- WARN: S3 nên có versioning -----

warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_versioning"
    rc.mode == "managed"
    some vc in rc.change.after.versioning_configuration
    vc.status != "Enabled"
    msg := sprintf(
        "🟡 [WARNING] S3 '%s' nên bật versioning để rollback data",
        [rc.address]
    )
}

# ----- DENY: S3 log bucket phải có lifecycle configuration [SOC2-A1.2] -----
# Log data without lifecycle → storage cost grows unbounded.
# Applies to S3 buckets used for log storage (matched by name pattern).

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]

    # Only apply to log-related buckets
    contains(rc.address, "log")

    # Check no lifecycle configuration references this bucket
    not has_lifecycle(rc.address)

    msg := sprintf(
        "🔴 [COMPLIANCE][SOC2-A1.2] S3 log bucket '%s' phải có lifecycle configuration để tránh chi phí lưu trữ không giới hạn",
        [rc.address]
    )
}

# Helper: check if a bucket address has a matching lifecycle configuration
has_lifecycle(bucket_address) if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_lifecycle_configuration"
    rc.mode == "managed"
    # Same module prefix means they belong together
    startswith(rc.address, trim_suffix(bucket_address, split(bucket_address, ".")[count(split(bucket_address, ".")) - 1]))
}

