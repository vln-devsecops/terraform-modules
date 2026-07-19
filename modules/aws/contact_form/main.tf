locals {
  common_tags = merge(var.tags, {
    app         = var.app_name
    environment = var.deployment_environment
  })

  short_region = replace(data.aws_region.current.region, "-", "")
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- Storage -----------------------------------------------------------------
#
# Single logical partition (hash key pk, constant "CONTACT" -- enforced by the
# Lambda code, not this module) makes "list newest first" a direct Query
# (ScanIndexForward: false) instead of a full-table Scan sorted in Lambda
# memory. The messageId-index GSI is a real get/delete-by-id lookup, not a
# provisioned-and-unused index.

module "table" {
  source = "../dynamodb"

  app_name                = var.app_name
  deployment_environment  = var.deployment_environment
  function                = "contact-form"
  short_deployment_region = local.short_region

  attributes = [
    { name = "pk", type = "S" },
    { name = "submittedAt", type = "S" },
    { name = "messageId", type = "S" },
  ]
  hash_key  = "pk"
  range_key = "submittedAt"

  global_secondary_indices = [
    {
      name            = "messageId-index"
      projection_type = "ALL"
      hash_key        = "messageId"
      range_key       = "submittedAt"
    }
  ]
}

# --- Shared encryption key (Lambda env vars + reCAPTCHA secret) --------------

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
  description             = "CMK for ${var.app_name}-${var.deployment_environment} contact_form encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = merge(local.common_tags, { rg = "security" })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.app_name}-${var.deployment_environment}-contact-form"
  target_key_id = aws_kms_key.this.key_id
}

# --- reCAPTCHA secret ----------------------------------------------------------
#
# Terraform only creates a placeholder value -- the real reCAPTCHA v3 secret
# key is populated out of band (e.g. `aws secretsmanager put-secret-value`)
# after apply, same pattern as aws/lambda's create_secret option.

resource "aws_secretsmanager_secret" "recaptcha" {
  # checkov:skip=CKV2_AWS_57:Secret rotation is caller-configurable, not wired at module level
  name        = "${var.app_name}-${var.deployment_environment}-contact-form-recaptcha-secret"
  description = "reCAPTCHA v3 secret key for the ${var.app_name} contact form (${var.deployment_environment})."
  kms_key_id  = aws_kms_key.this.arn
  tags        = merge(local.common_tags, { rg = "security" })
}

resource "aws_secretsmanager_secret_version" "recaptcha" {
  secret_id     = aws_secretsmanager_secret.recaptcha.id
  secret_string = "to-be-updated-by-script"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# --- npm-packaged Lambda functions ------------------------------------------
#
# Lambda source is consumed from @vln-devsecops/contact-form-lambda on GitHub
# Packages (published from node-contact-form) rather than vendored here, so
# version bumps flow through Dependabot PRs on lambda-build/package.json. The
# null_resource downloads the package at apply time; archive_file then zips
# the installed output. Contract tests mock the archive provider so they
# don't require a live npm install.
#
# To install locally before running terraform validate/test:
#   npm install --prefix modules/aws/contact_form/lambda-build
#
# The build pipeline (esbuild) produces two self-contained CJS bundles at
# dist/submit/handler.js and dist/admin/handler.js, each with all
# dependencies (including the shared/ helpers) inlined. dist/ also contains a
# package.json marking the directory as "type": "commonjs" so Node loads the
# .js files as CJS regardless of the source package's ESM type setting. The
# zip includes the full dist/ tree; handler references use the subdirectory
# prefix: "<subdir>/handler.handler".

resource "null_resource" "lambda_package" {
  # always_run (not a package.json content hash): a trigger keyed only on
  # package.json's content means Terraform skips re-running this
  # provisioner whenever the trigger value matches what's already in
  # state - correct for a persistent developer machine where
  # lambda-build/node_modules survives between applies, but wrong for a
  # genuinely ephemeral CI runner. A retried apply after a partial
  # failure (or any apply on a fresh runner after a prior successful one)
  # starts from a clean filesystem with no node_modules at all, yet state
  # still says "already installed" - archive_file then fails trying to
  # read a directory that was only ever real on the *previous* runner's
  # disk. Re-running npm install on every apply is cheap (a few seconds,
  # --ignore-scripts) and the downstream archive_file's content hash only
  # changes if the installed package's actual content changes, so this
  # doesn't cause spurious Lambda redeployments - just a cosmetic
  # "will be replaced" line on this resource in every plan.
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "npm install --prefix ${path.module}/lambda-build --ignore-scripts"
  }
}

data "archive_file" "lambda_package" {
  depends_on  = [null_resource.lambda_package]
  type        = "zip"
  source_dir  = "${path.module}/lambda-build/node_modules/@vln-devsecops/contact-form-lambda/dist"
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

# --- Submit Lambda (public; no app-level auth, reCAPTCHA-gated) -------------

resource "aws_iam_role" "submit" {
  name               = "${var.app_name}-${var.deployment_environment}-contact-form-submit"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "submit_logging" {
  role       = aws_iam_role.submit.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "submit" {
  name = "${var.app_name}-${var.deployment_environment}-contact-form-submit"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [module.table.table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.recaptcha.arn]
      },
      # DynamoDB requires the caller to hold KMS permissions on the table's
      # own key -- a table-arn grant alone fails at runtime with a
      # kms:Decrypt AccessDeniedException on first invocation, not at plan
      # time. aws_kms_key.this also encrypts the reCAPTCHA secret above.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [module.table.kms_key_arn, aws_kms_key.this.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "submit_permissions" {
  role       = aws_iam_role.submit.name
  policy_arn = aws_iam_policy.submit.arn
}

resource "aws_lambda_function" "submit" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name    = "${var.app_name}-${var.deployment_environment}-contact-form-submit"
  role             = aws_iam_role.submit.arn
  handler          = "submit/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = var.submit_timeout
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CONTACT_FORM_TABLE_NAME = module.table.table_name
      RECAPTCHA_SECRET_ARN    = aws_secretsmanager_secret.recaptcha.arn
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.submit_logging]
}

resource "aws_lambda_function_url" "submit" {
  # checkov:skip=CKV_AWS_258:Public, unauthenticated submission endpoint by design -- this is the contact form's public entry point; reCAPTCHA v3 gates it at the application layer instead
  function_name      = aws_lambda_function.submit.function_name
  authorization_type = "NONE"

  dynamic "cors" {
    for_each = var.submit_cors != null ? [var.submit_cors] : []

    content {
      allow_credentials = cors.value.allow_credentials
      allow_headers     = cors.value.allow_headers
      allow_methods     = cors.value.allow_methods
      allow_origins     = cors.value.allow_origins
      expose_headers    = cors.value.expose_headers
      max_age           = cors.value.max_age
    }
  }
}

# --- Admin Lambda (AWS_IAM-authorized; the entire access-control boundary) ---
#
# No app-level auth code at all -- IAM auth on the Function URL itself is the
# whole boundary, closing the "route forgot its auth check" defect class by
# construction (there's no route-level choice left to get wrong).

resource "aws_iam_role" "admin" {
  name               = "${var.app_name}-${var.deployment_environment}-contact-form-admin"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "admin_logging" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "admin" {
  name = "${var.app_name}-${var.deployment_environment}-contact-form-admin"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:Query", "dynamodb:DeleteItem"]
        Resource = [
          module.table.table_arn,
          "${module.table.table_arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [module.table.kms_key_arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "admin_permissions" {
  role       = aws_iam_role.admin.name
  policy_arn = aws_iam_policy.admin.arn
}

resource "aws_lambda_function" "admin" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name    = "${var.app_name}-${var.deployment_environment}-contact-form-admin"
  role             = aws_iam_role.admin.arn
  handler          = "admin/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = var.admin_timeout
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CONTACT_FORM_TABLE_NAME = module.table.table_name
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.admin_logging]
}

resource "aws_lambda_function_url" "admin" {
  function_name      = aws_lambda_function.admin.function_name
  authorization_type = "AWS_IAM"
}

# AWS_IAM auth on a Function URL only restricts *who* AWS will accept a
# SigV4-signed request from -- it does not itself grant anyone permission to
# call it. Each principal that should be able to poll/manage submissions
# needs an explicit lambda:InvokeFunctionUrl grant. Granting it here (a
# resource policy on the function) rather than requiring callers to hold
# their own identity-based grant keeps this module the single source of
# truth for who can reach the admin API.
resource "aws_lambda_permission" "admin_invoke" {
  for_each = toset(var.admin_allowed_principal_arns)

  statement_id           = "AllowInvokeFunctionUrl${md5(each.value)}"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.admin.function_name
  principal              = each.value
  function_url_auth_type = "AWS_IAM"
}
