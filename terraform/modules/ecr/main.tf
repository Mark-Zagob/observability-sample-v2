#--------------------------------------------------------------
# ECR Module — Container Repositories
#--------------------------------------------------------------
# Creates one ECR repository per service with:
#   - Lifecycle policy (keep N tagged, expire untagged)
#   - Basic image scanning on push (free)
#   - AES-256 encryption (default, free)
#--------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true # Lab convenience — remove for production

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # AES-256 default encryption (free, sufficient for lab)
  # Switch to KMS CMK for production compliance
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}/${each.key}"
    Service = each.key
  })
}

#--------------------------------------------------------------
# Lifecycle Policy — Applied to all repositories
#--------------------------------------------------------------
# Rule 1: Expire untagged images after N days
# Rule 2: Keep only N most recent tagged images
#--------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only ${var.max_tagged_images} most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
