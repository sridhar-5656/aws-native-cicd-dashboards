data "aws_caller_identity" "current" {}

locals {
  build_project_name  = "${var.name_prefix}-build"
  verify_project_name = "${var.name_prefix}-verify"
  pipeline_name       = "${var.name_prefix}-pipeline"
  account_id          = data.aws_caller_identity.current.account_id
  service_arn         = "arn:aws:ecs:${var.aws_region}:${local.account_id}:service/${var.cluster_name}/${var.service_name}"
}

# ------------------------------------------------------------------ artifact bucket
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name_prefix}-artifacts-${local.account_id}-${var.aws_region}"
  force_destroy = var.artifact_force_destroy
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "artifacts_tls" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket     = aws_s3_bucket.artifacts.id
  policy     = data.aws_iam_policy_document.artifacts_tls.json
  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# ------------------------------------------------------------------ GitHub connection
# Created in PENDING state. A human MUST authorize it once in the AWS console (docs/aws-setup.md).
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-github"
  provider_type = "GitHub"
}

# ------------------------------------------------------------------ CodeBuild: logs + roles
resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${local.build_project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "verify" {
  name              = "/aws/codebuild/${local.verify_project_name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# --- build role: logs, artifacts, ECR push (this repository only), test reports
resource "aws_iam_role" "build" {
  name               = "${var.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "build" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.build.arn}:*"]
  }
  statement {
    sid       = "ArtifactObjects"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    sid       = "ArtifactBucket"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPushThisRepositoryOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
      "ecr:PutImage", "ecr:DescribeImages",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid = "TestReports"
    actions = [
      "codebuild:CreateReportGroup", "codebuild:CreateReport", "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
    ]
    resources = ["arn:aws:codebuild:${var.aws_region}:${local.account_id}:report-group/${local.build_project_name}-*"]
  }
}

resource "aws_iam_role_policy" "build" {
  name   = "least-privilege-build"
  role   = aws_iam_role.build.id
  policy = data.aws_iam_policy_document.build.json
}

# --- verify role: logs + read source artifact only
resource "aws_iam_role" "verify" {
  name               = "${var.name_prefix}-verify-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "verify" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.verify.arn}:*"]
  }
  statement {
    sid       = "ReadArtifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "verify" {
  name   = "least-privilege-verify"
  role   = aws_iam_role.verify.id
  policy = data.aws_iam_policy_document.verify.json
}

# ------------------------------------------------------------------ CodeBuild projects
resource "aws_codebuild_project" "build" {
  name          = local.build_project_name
  description   = "Run tests, build the Docker image, push to ECR, emit imagedefinitions.json"
  service_role  = aws_iam_role.build.arn
  build_timeout = 30

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type    = var.build_compute_type
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # required to run the Docker daemon for `docker build`
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = var.ecr_repository_url
    }
    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.container_name
    }
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.build.name
    }
  }
  depends_on = [aws_iam_role_policy.build]
}

resource "aws_codebuild_project" "verify" {
  name          = local.verify_project_name
  description   = "Post-deployment HTTP verification of the live application"
  service_role  = aws_iam_role.verify.arn
  build_timeout = 15

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-verify.yml"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
    environment_variable {
      name  = "APP_BASE_URL"
      value = var.app_base_url
    }
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.verify.name
    }
  }
  depends_on = [aws_iam_role_policy.verify]
}

# ------------------------------------------------------------------ CodePipeline role
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${var.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    sid       = "ArtifactObjects"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    sid       = "ArtifactBucket"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    sid       = "StartTheTwoBuildProjects"
    actions   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"]
    resources = [aws_codebuild_project.build.arn, aws_codebuild_project.verify.arn]
  }
  statement {
    sid       = "UseGitHubConnection"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.github.arn]
  }
  statement {
    sid       = "EcsDeployScopedToService"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [local.service_arn]
  }
  statement {
    sid = "EcsDeployTaskDefinitions"
    # These actions do not support resource-level restrictions.
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks", "ecs:TagResource"]
    resources = ["*"]
  }
  statement {
    sid       = "PassOnlyTheTwoTaskRolesToEcs"
    actions   = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "pipeline" {
  name   = "least-privilege-pipeline"
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

# ------------------------------------------------------------------ the pipeline (Phase C)
resource "aws_codepipeline" "this" {
  count         = var.enable_pipeline ? 1 : 0
  name          = local.pipeline_name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V1"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_full_repository_id
        BranchName           = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  stage {
    name = "BuildAndTest"
    action {
      name             = "TestBuildPush"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "BuildVars"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
        EnvironmentVariables = jsonencode([
          { name = "COMMIT_ID", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "EcsDeploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["BuildOutput"]
      configuration = {
        ClusterName       = var.cluster_name
        ServiceName       = var.service_name
        FileName          = "imagedefinitions.json"
        DeploymentTimeout = tostring(var.deploy_timeout_minutes)
      }
    }
  }

  stage {
    name = "Verify"
    action {
      name            = "HttpHealthCheck"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.verify.name
        EnvironmentVariables = jsonencode([
          { name = "EXPECTED_IMAGE_TAG", value = "#{BuildVars.IMAGE_TAG}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}
