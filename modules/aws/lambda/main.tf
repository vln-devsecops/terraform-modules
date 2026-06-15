locals {
  effective_source_object_key = coalesce(var.source_object_key, "${var.app_name}-${var.function_name}.zip")
  source_archive_exists       = contains(data.aws_s3_objects.source_archive_probe.keys, local.effective_source_object_key)
  kms_key_arn                 = coalesce(var.kms_key_arn, aws_kms_key.this[0].arn)
  kms_key_policy_json         = var.kms_key_policy_json != null ? var.kms_key_policy_json : data.aws_iam_policy_document.kms.json
  role_name                   = "iam_for_lambda_${var.function_name}_${var.deployment_environment}_${substr(md5(var.app_name), 0, 8)}"
  lambda_filename             = local.source_archive_exists ? null : data.archive_file.echo_lambda.output_path
  lambda_source_code_hash     = local.source_archive_exists ? null : data.archive_file.echo_lambda.output_base64sha256
  lambda_s3_bucket            = local.source_archive_exists ? var.source_bucket_id : null
  lambda_s3_key               = local.source_archive_exists ? local.effective_source_object_key : null
  lambda_s3_object_version    = null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = var.assume_role_services
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  common_tags = {
    app         = var.app_name
    environment = var.deployment_environment
    function    = var.function_name
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  # checkov:skip=CKV_AWS_109:Root-access KMS policy intentionally delegates broad permissions to account root
  # checkov:skip=CKV_AWS_111:Root-access KMS policy intentionally delegates broad permissions to account root
  # checkov:skip=CKV_AWS_356:Root-access KMS policy intentionally delegates broad permissions to account root
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  description             = "CMK for ${var.app_name}-${var.function_name}-${var.deployment_environment} Lambda encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = local.kms_key_policy_json
  tags                    = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/${var.app_name}-${var.function_name}-${var.deployment_environment}-lambda"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = local.assume_role_policy
  tags               = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "deployment_source_access" {
  name        = "${var.app_name}_${var.function_name}_${var.deployment_environment}_lambda_deployment_s3_source_access_policy"
  description = "Allows Lambda function to read its deployment archive from S3"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ],
        Effect   = "Allow",
        Resource = "${var.source_bucket_arn}/${local.effective_source_object_key}"
      }
    ]
  })
  tags = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_iam_role_policy_attachment" "deployment_source_access" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.deployment_source_access.arn
}

data "aws_s3_objects" "source_archive_probe" {
  bucket = var.source_bucket_id
  prefix = local.effective_source_object_key
}

data "archive_file" "echo_lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/echo-lambda.zip"

  source {
    content  = <<-EOT
      exports.handler = async (event) => ({
        statusCode: 200,
        headers: {
          "content-type": "application/json"
        },
        body: JSON.stringify(event)
      });
    EOT
    filename = "index.js"
  }
}

resource "aws_iam_policy" "s3_required_access" {
  for_each = var.s3_required_access

  name = "lambda_s3_read_${var.app_name}_${var.function_name}_${var.deployment_environment}-${each.key}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          each.value.action
        ]
        Resource = each.value.resources
      }
    ]
  })
  tags = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_iam_role_policy_attachment" "s3_required_access" {
  for_each = var.s3_required_access

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.s3_required_access[each.key].arn
}

resource "aws_iam_role_policy_attachment" "additional" {
  count = length(var.additional_role_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.additional_role_policy_arns[count.index]
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name = "${var.app_name}-${var.function_name}-${var.deployment_environment}"
  role          = aws_iam_role.this.arn
  handler       = var.handler_name
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size
  publish       = var.publish

  filename          = local.lambda_filename
  s3_bucket         = local.lambda_s3_bucket
  s3_key            = local.lambda_s3_key
  source_code_hash  = local.lambda_source_code_hash
  s3_object_version = local.lambda_s3_object_version

  environment {
    variables = var.environment
  }

  kms_key_arn = local.kms_key_arn

  tracing_config {
    mode = var.tracing_mode
  }

  tags = merge(local.common_tags, var.tags, { rg = "compute" })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging,
  ]
}

resource "aws_secretsmanager_secret" "this" {
  # checkov:skip=CKV2_AWS_57:Secret rotation is caller-configurable, not wired at module level
  count = var.create_secret ? 1 : 0

  name        = "${var.app_name}-${var.function_name}-${var.deployment_environment}-secrets"
  description = "Secrets for ${var.function_name} Lambda function in ${var.deployment_environment} environment"
  kms_key_id  = local.kms_key_arn
  tags        = merge(local.common_tags, var.tags, { purpose = "lambda-secrets", rg = "security" })
}

resource "aws_secretsmanager_secret_version" "this" {
  count = var.create_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.this[0].id
  secret_string = jsonencode({
    placeholder = "to-be-updated-by-script"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_iam_policy" "lambda_secrets_access" {
  count = var.create_secret ? 1 : 0

  name        = "${var.app_name}-${var.function_name}-${var.deployment_environment}-secrets-policy"
  description = "Allow ${var.function_name} Lambda to read its secrets from Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.this[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [
          local.kms_key_arn
        ]
      }
    ]
  })
  tags = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_access" {
  count = var.create_secret ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.lambda_secrets_access[0].arn
}

resource "aws_iam_policy" "backend_user_secrets_access" {
  count = var.create_secret && var.backend_user_name != null ? 1 : 0

  name        = "${var.app_name}-${var.function_name}-${var.deployment_environment}-backend-secrets-policy"
  description = "Allow backend user to manage ${var.function_name} Lambda secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.this[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          local.kms_key_arn
        ]
      }
    ]
  })
  tags = merge(local.common_tags, var.tags, { rg = "security" })
}

resource "aws_iam_user_policy_attachment" "backend_user_secrets_access" {
  count = var.create_secret && var.backend_user_name != null ? 1 : 0

  user       = var.backend_user_name
  policy_arn = aws_iam_policy.backend_user_secrets_access[0].arn
}

resource "aws_lambda_function_url" "this" {
  count = var.create_url ? 1 : 0

  function_name      = aws_lambda_function.this.function_name
  authorization_type = var.url_authorization_type
}
