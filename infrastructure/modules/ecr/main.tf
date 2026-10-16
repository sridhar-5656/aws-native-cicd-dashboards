variable "name" { type = string }
variable "max_image_count" { type = number }
variable "force_delete" { type = bool }

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image (reliable rollback)
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the newest N images so rollback targets remain available but storage cannot grow forever.
# The running image is always among the newest (every deploy pushes a new image).
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last ${var.max_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
output "repository_name" { value = aws_ecr_repository.this.name }
