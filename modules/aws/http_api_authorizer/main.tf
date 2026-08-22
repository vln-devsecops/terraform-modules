# A random_password, not the Secrets-Manager-out-of-band pattern used
# elsewhere in this repo for real secrets (e.g. vlinder_auth's session
# signing key): this secret's whole purpose is to be handed back to the
# caller (via the origin_verify_secret output) for baking into a CDN's
# static origin-config (e.g. a CloudFront custom_header), which is itself a
# Terraform-managed resource attribute stored in state. There is no way to
# keep this value out of state while also using it there, so avoiding
# random_password here would add machinery without adding any real
# confidentiality.
resource "random_password" "origin_verify_secret" {
  length  = 32
  special = false
}

# --- npm-packaged authorizer Lambda ------------------------------------------
#
# Lambda source is consumed from @vln-devsecops/http-api-authorizer-lambda on
# GitHub Packages (published from node-http-api-authorizer) rather than
# vendored here, so version bumps flow through Dependabot PRs on
# lambda-build/package.json -- same pattern as contact_form and vlinder_auth.
# Contract tests mock the archive provider so they don't require a live npm
# install.
#
# To install locally before running terraform validate/test:
#   npm install --prefix modules/aws/http_api_authorizer/lambda-build

resource "null_resource" "lambda_package" {
  # See contact_form/main.tf's identical null_resource for why triggers is
  # always_run rather than keyed on package.json's hash, and why the command
  # itself (not the trigger) decides whether to actually reinstall.
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "test -d ${path.module}/lambda-build/node_modules/@vln-devsecops/http-api-authorizer-lambda/dist || npm install --prefix ${path.module}/lambda-build --ignore-scripts"
  }
}

data "archive_file" "lambda_package" {
  depends_on  = [null_resource.lambda_package]
  type        = "zip"
  source_dir  = "${path.module}/lambda-build/node_modules/@vln-devsecops/http-api-authorizer-lambda/dist"
  output_path = "${path.module}/.terraform/lambda-package.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-authorizer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "logging" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda needs an explicit grant to decrypt its own env vars under a
# caller-supplied CMK -- the KMS key's own policy alone isn't enough; see the
# identical gotcha called out in vlinder_auth/main.tf's auth_api IAM policy.
resource "aws_iam_policy" "kms" {
  count = var.kms_key_arn != null ? 1 : 0

  name = "${var.name}-authorizer-kms"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [var.kms_key_arn]
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "kms" {
  count = var.kms_key_arn != null ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.kms[0].arn
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name    = "${var.name}-authorizer"
  role             = aws_iam_role.this.arn
  handler          = "handler.handler"
  runtime          = "nodejs22.x"
  timeout          = var.timeout
  publish          = true
  kms_key_arn      = var.kms_key_arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = merge(
      {
        ORIGIN_VERIFY_SECRET = random_password.origin_verify_secret.result
      },
      var.require_jwt ? {
        REQUIRE_JWT        = "true"
        JWT_ISSUER_URL     = var.jwt_issuer_url
        JWT_AUDIENCE       = var.jwt_audience
        JWT_FORWARD_CLAIMS = join(",", var.jwt_forward_claims)
      } : {}
    )
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.logging]
}
