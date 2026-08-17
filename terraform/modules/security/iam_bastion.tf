#--------------------------------------------------------------
# IAM — Bastion Host Role + Instance Profile
#--------------------------------------------------------------
# Bastion gets SSM Session Manager support so SSH through
# Internet is NOT required. SSM provides:
# - Encrypted session logging to CloudWatch/S3
# - No inbound port 22 needed (Session Manager uses 443 outbound)
# - IAM-based access control (no SSH keys needed for SSM sessions)
#
# We still support SSH key for direct access as a fallback,
# but SSM is the recommended approach in production.
#
# Reference: AWS Well-Architected SEC05, SEC09
#--------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name = "${var.project_name}-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-bastion-role"
  })
}

# SSM Session Manager — primary access method
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count = var.enable_bastion ? 1 : 0

  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent — instance monitoring
resource "aws_iam_role_policy_attachment" "bastion_cloudwatch" {
  count = var.enable_bastion ? 1 : 0

  role       = aws_iam_role.bastion[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile — required for EC2 to assume the role
resource "aws_iam_instance_profile" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name = "${var.project_name}-bastion"
  role = aws_iam_role.bastion[0].name

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-bastion-profile"
  })
}
