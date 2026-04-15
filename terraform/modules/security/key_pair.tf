#--------------------------------------------------------------
# SSH Key Pair — Lab / Production Modes
#--------------------------------------------------------------
# Two modes based on var.generate_ssh_key:
#
#   Lab (generate_ssh_key = true):
#     → Auto-generate RSA 4096 key pair
#     → Private key saved to local file (gitignored)
#     → Convenient for personal lab environments
#
#   Production (generate_ssh_key = false):
#     → Import existing public key from var.public_key_path
#     → Private key managed externally (1Password, Vault, etc)
#     → Required for team environments
#
# Note: Only created when enable_bastion = true
# Reference: AWS Well-Architected SEC02-BP04
#--------------------------------------------------------------

# Lab mode: auto-generate key pair
resource "tls_private_key" "bastion" {
  count = var.enable_bastion && var.generate_ssh_key ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  count = var.enable_bastion && var.generate_ssh_key ? 1 : 0

  key_name   = "${var.project_name}-bastion"
  public_key = tls_private_key.bastion[0].public_key_openssh

  tags = merge(var.common_tags, {
    Name       = "${var.project_name}-bastion-key"
    Generated  = "true"
  })
}

# Save private key locally (for lab convenience)
resource "local_sensitive_file" "bastion_key" {
  count = var.enable_bastion && var.generate_ssh_key ? 1 : 0

  content         = tls_private_key.bastion[0].private_key_pem
  filename        = "${path.root}/keys/${var.project_name}-bastion.pem"
  file_permission = "0400"
}

# Production mode: import existing public key
resource "aws_key_pair" "provided" {
  count = var.enable_bastion && !var.generate_ssh_key && var.public_key_path != "" ? 1 : 0

  key_name   = "${var.project_name}-bastion"
  public_key = file(var.public_key_path)

  tags = merge(var.common_tags, {
    Name      = "${var.project_name}-bastion-key"
    Generated = "false"
  })
}

# Unified local for downstream consumption
locals {
  key_pair_name = var.enable_bastion ? (
    var.generate_ssh_key
    ? try(aws_key_pair.generated[0].key_name, "")
    : try(aws_key_pair.provided[0].key_name, "")
  ) : ""
}
