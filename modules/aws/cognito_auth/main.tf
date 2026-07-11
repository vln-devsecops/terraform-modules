data "aws_route53_zone" "this" {
  zone_id = var.route53_zone_id
}

locals {
  base_domain        = trimsuffix(data.aws_route53_zone.this.name, ".")
  hosted_ui_domain   = "${var.domain_prefix}-${local.base_domain}"
  admin_panel_domain = "${var.admin_panel_domain_prefix}-${local.base_domain}"

  # Cognito's hosted-UI CSS customization only recognizes a fixed set of
  # AWS-defined selectors (*-customizable) -- there's no way to add our own
  # prefixed class names here, unlike the ui-auth React components in
  # node-vlinder-auth, which do use normal app-controlled class names. The
  # full selector list AWS supports: background-customizable,
  # banner-customizable, idpButton-customizable, idpDescription-customizable,
  # inputField-customizable, label-customizable, legalText-customizable,
  # submitButton-customizable, textDescription-customizable,
  # errorMessage-customizable. This default only styles a placeholder subset;
  # override var.css with any/all of the above to fully restyle the page.
  default_css   = <<-CSS
    .banner-customizable { background-color: #1b3a5c; }
    .submitButton-customizable { background-color: #1b3a5c; }
    .label-customizable { font-weight: 400; }
  CSS
  effective_css = coalesce(var.css, local.default_css)

  common_tags = merge(var.tags, {
    app         = var.app_name
    environment = var.deployment_environment
  })

  short_region = replace(data.aws_region.current.region, "-", "")

  # Single-tenant mode (the default) never exposes tenant CRUD to the consumer;
  # it seeds exactly one implicit tenant so the RBAC mechanism still has a
  # tenantId to key role assignments on.
  effective_tenants = var.tenancy_mode == "multi" ? var.tenants : {
    default = { name = "Default", email_domain = null }
  }
}

# --- Identity ---------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = "${var.app_name}-${var.deployment_environment}-user-pool"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }

  auto_verified_attributes = ["email"]

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  mfa_configuration = var.mfa_configuration

  password_policy {
    minimum_length                   = var.password_policy.minimum_length
    require_lowercase                = var.password_policy.require_lowercase
    require_uppercase                = var.password_policy.require_uppercase
    require_numbers                  = var.password_policy.require_numbers
    require_symbols                  = var.password_policy.require_symbols
    password_history_size            = var.password_policy.password_history_size
    temporary_password_validity_days = var.password_policy.temporary_password_validity_days
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "given_name"
    required                 = true

    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "family_name"
    required                 = true

    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  username_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_LINK"
    email_subject        = "Please verify your email address"
    email_message        = "Hello {username}, please verify your email address by clicking on the link: {####}"
  }

  dynamic "email_configuration" {
    for_each = var.ses_configuration == null ? [1] : []
    content {
      email_sending_account = "COGNITO_DEFAULT"
    }
  }

  dynamic "email_configuration" {
    for_each = var.ses_configuration == null ? [] : [var.ses_configuration]
    content {
      email_sending_account = "DEVELOPER"
      configuration_set     = email_configuration.value.configuration_set_name
      source_arn            = email_configuration.value.source_arn
      from_email_address    = email_configuration.value.from_email_address
    }
  }

  lambda_config {
    post_confirmation = aws_lambda_function.post_confirmation.arn
    pre_token_generation_config {
      lambda_arn     = aws_lambda_function.pre_token_generation.arn
      lambda_version = "V2_0"
    }
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_domain" "this" {
  domain          = local.hosted_ui_domain
  certificate_arn = var.acm_certificate_arn
  user_pool_id    = aws_cognito_user_pool.this.id
}

resource "aws_route53_record" "hosted_ui_a" {
  name    = aws_cognito_user_pool_domain.this.domain
  type    = "A"
  zone_id = var.route53_zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cognito_user_pool_domain.this.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.this.cloudfront_distribution_zone_id
  }
}

resource "aws_route53_record" "hosted_ui_aaaa" {
  name    = aws_cognito_user_pool_domain.this.domain
  type    = "AAAA"
  zone_id = var.route53_zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cognito_user_pool_domain.this.cloudfront_distribution
    zone_id                = aws_cognito_user_pool_domain.this.cloudfront_distribution_zone_id
  }
}

resource "aws_cognito_user_pool_ui_customization" "this" {
  client_id    = "ALL"
  user_pool_id = aws_cognito_user_pool_domain.this.user_pool_id
  css          = local.effective_css
  image_file   = var.logo_base64
}

resource "aws_cognito_user_pool_client" "consumer" {
  for_each = var.clients

  name         = "${var.app_name}-${each.key}-${var.deployment_environment}"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = each.value.generate_secret
  callback_urls                        = each.value.callback_urls
  logout_urls                          = each.value.logout_urls
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = each.value.allowed_oauth_scopes
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user_pool_client" "admin_panel" {
  count = var.create_admin_panel ? 1 : 0

  name         = "${var.app_name}-admin-panel-${var.deployment_environment}"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  callback_urls                        = ["https://${local.admin_panel_domain}/"]
  logout_urls                          = ["https://${local.admin_panel_domain}/"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user_group" "this" {
  for_each = var.groups

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
  description  = each.value.description
  precedence   = each.value.precedence
}

# --- Optional identity pool (AWS credential vending; off by default) -------

resource "aws_cognito_identity_pool" "this" {
  count = var.create_identity_pool ? 1 : 0

  identity_pool_name               = "${var.app_name}_${var.deployment_environment}_identity_pool"
  allow_unauthenticated_identities = false

  dynamic "cognito_identity_providers" {
    for_each = merge(
      { for key, client in aws_cognito_user_pool_client.consumer : key => client },
      { for client in aws_cognito_user_pool_client.admin_panel : "admin_panel" => client }
    )
    content {
      client_id               = cognito_identity_providers.value.id
      provider_name           = "cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
      server_side_token_check = false
    }
  }

  tags = local.common_tags
}

data "aws_region" "current" {}

resource "aws_iam_role" "identity_pool_authenticated" {
  count = var.create_identity_pool ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-identity-pool-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.this[0].id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "identity_pool_authenticated" {
  for_each = var.create_identity_pool ? toset(var.identity_pool_authenticated_role_policy_arns) : toset([])

  role       = aws_iam_role.identity_pool_authenticated[0].name
  policy_arn = each.value
}

resource "aws_cognito_identity_pool_roles_attachment" "this" {
  count = var.create_identity_pool ? 1 : 0

  identity_pool_id = aws_cognito_identity_pool.this[0].id

  roles = {
    authenticated = aws_iam_role.identity_pool_authenticated[0].arn
  }
}

# --- Shared encryption key --------------------------------------------------
#
# One CMK for everything this module directly encrypts (the two native
# reference-data tables below, plus all three Lambda functions' environment
# variables) -- the sensitive user_role_assignments table gets its own CMK
# via the composed aws/dynamodb module, which creates a dedicated key by
# default.

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
  description             = "CMK for ${var.app_name}-${var.deployment_environment} cognito_auth encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = merge(local.common_tags, { rg = "security" })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.app_name}-${var.deployment_environment}-cognito-auth"
  target_key_id = aws_kms_key.this.key_id
}

# --- RBAC and tenancy -------------------------------------------------------
#
# Role is kept separate from privileges: `roles` is a Terraform-seeded catalog
# (not runtime-editable, keeping the admin API light), and only the resolved
# *privileges* -- never a role name -- land in the issued JWT (see the
# pre-token-generation Lambda below). A role's tenant_scope of "global" is
# what makes it a super-admin-style role; "tenant" is an ordinary tenant-
# scoped role (including a tenant admin). Both are the same mechanism.

resource "aws_dynamodb_table" "roles" {
  name         = "ddb-${var.app_name}-${var.deployment_environment}-${local.short_region}-auth-roles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "roleId"

  attribute {
    name = "roleId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table_item" "roles" {
  for_each = var.roles

  table_name = aws_dynamodb_table.roles.name
  hash_key   = aws_dynamodb_table.roles.hash_key

  item = jsonencode({
    roleId      = { S = each.key }
    privileges  = { L = [for privilege in each.value.privileges : { S = privilege }] }
    tenantScope = { S = each.value.tenant_scope }
  })
}

# Schema (tenantId hash key + emailDomain GSI) stays stable across tenancy_mode
# switches so toggling the mode later doesn't force a table replacement.
resource "aws_dynamodb_table" "tenants" {
  name         = "ddb-${var.app_name}-${var.deployment_environment}-${local.short_region}-auth-tenants"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenantId"

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "emailDomain"
    type = "S"
  }

  global_secondary_index {
    name            = "emailDomain-index"
    hash_key        = "emailDomain"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }

  tags = local.common_tags
}

resource "aws_dynamodb_table_item" "tenants" {
  for_each = local.effective_tenants

  table_name = aws_dynamodb_table.tenants.name
  hash_key   = aws_dynamodb_table.tenants.hash_key

  item = jsonencode(merge(
    {
      tenantId = { S = each.key }
      name     = { S = each.value.name }
    },
    each.value.email_domain == null ? {} : {
      emailDomain = { S = each.value.email_domain }
    }
  ))
}

# The sensitive access-control table (who has which role in which tenant)
# composes the shared aws/dynamodb module for its dedicated-CMK encryption,
# unlike the two reference-data tables above.
module "user_role_assignments" {
  source = "../dynamodb"

  app_name                = var.app_name
  deployment_environment  = var.deployment_environment
  function                = "auth-role-assignments"
  short_deployment_region = local.short_region

  attributes = [
    { name = "userId", type = "S" },
    { name = "tenantId", type = "S" },
  ]
  hash_key  = "userId"
  range_key = "tenantId"

  global_secondary_indices = [
    {
      name            = "tenantId-index"
      projection_type = "ALL"
      hash_key        = "tenantId"
      range_key       = "userId"
    }
  ]
}

# --- Vendored Lambda functions ----------------------------------------------
#
# Deliberately not composed via aws/lambda: that module expects a pre-built
# artifact already uploaded to an S3 deployment bucket (falling back to a
# placeholder "echo" function otherwise), a convention built for app code
# deployed independently of infra changes. This module's Lambda source is
# vendored/committed alongside the module itself (see lambda-src/README.md),
# so zipping it directly via archive_file keeps the module self-contained on
# the very first apply -- no bucket, no upload step, no ARN to pass in.

data "archive_file" "post_confirmation" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/post-confirmation"
  output_path = "${path.module}/.terraform/post-confirmation.zip"
}

data "archive_file" "pre_token_generation" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/pre-token-generation"
  output_path = "${path.module}/.terraform/pre-token-generation.zip"
}

data "archive_file" "admin_api" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src/admin-api"
  output_path = "${path.module}/.terraform/admin-api.zip"
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

resource "aws_iam_role" "post_confirmation" {
  name               = "${var.app_name}-${var.deployment_environment}-post-confirmation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "post_confirmation_logging" {
  role       = aws_iam_role.post_confirmation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "post_confirmation" {
  name = "${var.app_name}-${var.deployment_environment}-post-confirmation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = ["${aws_dynamodb_table.tenants.arn}/index/emailDomain-index"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [module.user_role_assignments.table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["cognito-idp:AdminAddUserToGroup"]
        Resource = [aws_cognito_user_pool.this.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "post_confirmation_permissions" {
  role       = aws_iam_role.post_confirmation.name
  policy_arn = aws_iam_policy.post_confirmation.arn
}

resource "aws_lambda_function" "post_confirmation" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name    = "${var.app_name}-${var.deployment_environment}-post-confirmation"
  role             = aws_iam_role.post_confirmation.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 5
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.post_confirmation.output_path
  source_code_hash = data.archive_file.post_confirmation.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      # No USER_POOL_ID here: Cognito always includes userPoolId on the
      # trigger event itself, and requiring it via env var would create an
      # unresolvable circular dependency (this pool's lambda_config needs
      # this function's ARN; this function would need the pool's ID).
      TENANCY_MODE                = var.tenancy_mode
      DEFAULT_TENANT_ID           = "default"
      DEFAULT_ROLE_ID             = var.default_role_id
      TENANTS_TABLE_NAME          = aws_dynamodb_table.tenants.name
      ROLE_ASSIGNMENTS_TABLE_NAME = module.user_role_assignments.table_name
      BASELINE_GROUPS             = join(",", var.baseline_groups)
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.post_confirmation_logging]
}

resource "aws_lambda_permission" "post_confirmation" {
  statement_id  = "AllowCognitoInvokePostConfirmation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

resource "aws_iam_role" "pre_token_generation" {
  name               = "${var.app_name}-${var.deployment_environment}-pre-token-generation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "pre_token_generation_logging" {
  role       = aws_iam_role.pre_token_generation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "pre_token_generation" {
  name = "${var.app_name}-${var.deployment_environment}-pre-token-generation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = [module.user_role_assignments.table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = [aws_dynamodb_table.roles.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "pre_token_generation_permissions" {
  role       = aws_iam_role.pre_token_generation.name
  policy_arn = aws_iam_policy.pre_token_generation.arn
}

resource "aws_lambda_function" "pre_token_generation" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  function_name    = "${var.app_name}-${var.deployment_environment}-pre-token-generation"
  role             = aws_iam_role.pre_token_generation.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 5
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.pre_token_generation.output_path
  source_code_hash = data.archive_file.pre_token_generation.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ROLE_ASSIGNMENTS_TABLE_NAME = module.user_role_assignments.table_name
      ROLES_TABLE_NAME            = aws_dynamodb_table.roles.name
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.pre_token_generation_logging]
}

resource "aws_lambda_permission" "pre_token_generation" {
  statement_id  = "AllowCognitoInvokePreTokenGeneration"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_token_generation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

resource "aws_iam_role" "admin_api" {
  count = var.create_admin_panel ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-admin-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "admin_api_logging" {
  count = var.create_admin_panel ? 1 : 0

  role       = aws_iam_role.admin_api[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "admin_api" {
  count = var.create_admin_panel ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-admin-api"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [
          module.user_role_assignments.table_arn,
          "${module.user_role_assignments.table_arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Scan"]
        Resource = [aws_dynamodb_table.roles.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
        ]
        Resource = [aws_cognito_user_pool.this.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "admin_api_permissions" {
  count = var.create_admin_panel ? 1 : 0

  role       = aws_iam_role.admin_api[0].name
  policy_arn = aws_iam_policy.admin_api[0].arn
}

resource "aws_lambda_function" "admin_api" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  count = var.create_admin_panel ? 1 : 0

  function_name    = "${var.app_name}-${var.deployment_environment}-admin-api"
  role             = aws_iam_role.admin_api[0].arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 10
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.admin_api.output_path
  source_code_hash = data.archive_file.admin_api.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ROLE_ASSIGNMENTS_TABLE_NAME = module.user_role_assignments.table_name
      ROLES_TABLE_NAME            = aws_dynamodb_table.roles.name
      USER_POOL_ID                = aws_cognito_user_pool.this.id
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.admin_api_logging]
}

# --- Admin API (bundled, HTTP API + JWT authorizer on this module's own pool) ---

locals {
  admin_api_issuer_url = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"

  # Guarded on create_admin_panel as a whole, not just its consumer: Terraform
  # evaluates a local's expression whenever anything in the configuration
  # references it, regardless of whether that reference sits inside a
  # count = 0 block -- so aws_lambda_function.admin_api[0] must never appear
  # in this local's expression unless the admin API actually exists.
  admin_api_routes = var.create_admin_panel ? {
    list_users = {
      route_key            = "GET /users"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
    get_user = {
      route_key            = "GET /users/{userId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
    set_user_enabled = {
      route_key            = "PATCH /users/{userId}/enabled"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
    list_roles = {
      route_key            = "GET /roles"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
    assign_role = {
      route_key            = "PUT /users/{userId}/role"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
    revoke_role = {
      route_key            = "DELETE /users/{userId}/role"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "cognito_auth"
    }
  } : {}
}

module "admin_api" {
  count  = var.create_admin_panel ? 1 : 0
  source = "../http_api"

  name = "${var.app_name}-${var.deployment_environment}-admin-api"

  jwt_authorizers = {
    cognito_auth = {
      issuer_url = local.admin_api_issuer_url
      audience   = aws_cognito_user_pool_client.admin_panel[*].id
    }
  }

  routes = local.admin_api_routes

  tags = local.common_tags
}

# --- Admin panel hosting -----------------------------------------------------
#
# Unlike the Lambda source, the admin panel's built static assets are NOT
# vendored into this Terraform module: static_site's own bucket/CloudFront
# naming is only known after apply, so the actual `aws s3 sync dist/ ...`
# upload is a deploy-pipeline concern (same as any other static_site
# consumer), not something Terraform manages here. The admin_api_invoke_url
# and webapp_client_id outputs below exist so that pipeline can inject
# runtime config into the built SPA (a config.json read at load time, since
# Vite env vars are baked in at build time and can't know these values yet).
module "admin_panel_site" {
  count  = var.create_admin_panel ? 1 : 0
  source = "../static_site"

  site_name           = local.admin_panel_domain
  route53_zone_id     = var.route53_zone_id
  acm_certificate_arn = var.acm_certificate_arn

  tags = local.common_tags
}
