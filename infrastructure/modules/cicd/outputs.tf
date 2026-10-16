output "pipeline_name" { value = var.enable_pipeline ? aws_codepipeline.this[0].name : null }
output "connection_arn" { value = aws_codestarconnections_connection.github.arn }
output "connection_status" { value = aws_codestarconnections_connection.github.connection_status }
output "build_project_name" { value = aws_codebuild_project.build.name }
output "verify_project_name" { value = aws_codebuild_project.verify.name }
output "artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
