# =============================================================
# AWS Backup Security Policies
# =============================================================
# Enforces: encryption, vault lock, tag-based selection,
#           backup retention, cross-region copy
#
# Reference: AWS Well-Architected REL09-BP01, REL09-BP02
# =============================================================

package terraform.backup

import rego.v1

# ----- DENY: Hard rules — vi phạm = BLOCK -----

# Rule 1: Backup vault phải dùng KMS CMK encryption
# Note: kms_key_arn is a computed reference — check both after AND after_unknown
# to avoid false positives on plan (value is null in after, true in after_unknown)
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_backup_vault"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    not rc.change.after.kms_key_arn
    not object.get(rc.change.after_unknown, "kms_key_arn", false)
    msg := sprintf(
        "🔴 [CRITICAL] Backup vault '%s' phải dùng KMS CMK encryption (kms_key_arn required)",
        [rc.address]
    )
}

# Rule 2: Backup vault phải có vault lock configuration
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_backup_vault"
    rc.mode == "managed"
    rc.change.actions[_] in ["create"]

    # Check no vault lock exists for this vault
    not has_vault_lock(rc.change.after.name)

    msg := sprintf(
        "🔴 [SECURITY] Backup vault '%s' phải có vault lock configuration để prevent accidental deletion",
        [rc.address]
    )
}

has_vault_lock(vault_name) if {
    some rc in input.resource_changes
    rc.type == "aws_backup_vault_lock_configuration"
    rc.change.after.backup_vault_name == vault_name
}

# Rule 3: Backup plan phải có retention >= 7 ngày
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_backup_plan"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    some rule in rc.change.after.rule
    retention := rule.lifecycle[_].delete_after
    retention < 7
    msg := sprintf(
        "🔴 [DATA] Backup plan '%s' rule '%s' retention = %d ngày (phải >= 7 ngày)",
        [rc.address, rule.rule_name, retention]
    )
}

# Rule 4: Backup selection nên dùng tag-based (not ARN-based)
warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_backup_selection"
    rc.mode == "managed"
    rc.change.actions[_] in ["create"]

    # If resources list is populated but no selection_tag, warn
    count(rc.change.after.resources) > 0
    not rc.change.after.selection_tag

    msg := sprintf(
        "🟡 [BEST-PRACTICE] Backup selection '%s' nên dùng tag-based selection thay vì ARN-based để auto-discover new resources",
        [rc.address]
    )
}

# Rule 5: SNS topic cho backup notifications phải encrypted
# Note: kms_master_key_id is computed — check after_unknown to avoid false positives
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_sns_topic"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    contains(rc.address, "backup")
    not rc.change.after.kms_master_key_id
    not object.get(rc.change.after_unknown, "kms_master_key_id", false)
    msg := sprintf(
        "🔴 [SECURITY] SNS topic '%s' cho backup notifications phải dùng KMS encryption",
        [rc.address]
    )
}

# Rule 6: S3 report bucket phải block public access
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket"
    rc.mode == "managed"
    rc.change.actions[_] in ["create"]
    contains(rc.address, "backup")

    # Check no public access block exists for this bucket
    not has_public_access_block(rc.address)

    msg := sprintf(
        "🔴 [SECURITY] S3 bucket '%s' cho backup reports phải có public access block",
        [rc.address]
    )
}

has_public_access_block(bucket_address) if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_public_access_block"
    contains(rc.address, "backup")
}

# Rule 7: S3 report bucket phải dùng KMS encryption
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_s3_bucket_server_side_encryption_configuration"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    contains(rc.address, "backup")
    some rule in rc.change.after.rule
    sse := rule.apply_server_side_encryption_by_default[_]
    sse.sse_algorithm != "aws:kms"
    msg := sprintf(
        "🔴 [SECURITY] S3 bucket encryption '%s' phải dùng aws:kms (không dùng AES256)",
        [rc.address]
    )
}

# Rule 8: Backup plan completion_window phải >= 120 phút
warn contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_backup_plan"
    rc.mode == "managed"
    rc.change.actions[_] in ["create", "update"]
    some rule in rc.change.after.rule
    rule.completion_window < 120
    msg := sprintf(
        "🟡 [RELIABILITY] Backup plan '%s' rule '%s' completion_window = %d phút (nên >= 120 để tránh timeout với DB lớn)",
        [rc.address, rule.rule_name, rule.completion_window]
    )
}
