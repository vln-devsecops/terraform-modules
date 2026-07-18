data "aws_route53_zone" "this" {
  zone_id = var.route53_zone_id
}

locals {
  base_domain      = trimsuffix(data.aws_route53_zone.this.name, ".")
  auth_site_domain = "${var.domain_prefix}.${local.base_domain}"

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

  auth_site_bucket_name = "${var.app_name}-${var.deployment_environment}-auth-site"
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
    # Not CONFIRM_WITH_LINK: verification links target the Cognito user pool
    # domain's /confirmUser endpoint, and this module deliberately has no
    # such domain (own CloudFront auth site instead of the hosted UI). With
    # LINK and no domain, every live SignUp call is rejected with "there
    # does not exist a valid use pool domain associated with the user pool".
    # Code-based confirmation has no domain dependency; the bundled auth
    # site provides the code-entry form.
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Please verify your email address"
    email_message        = "Hello {username}, your email verification code is {####}"
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

resource "aws_cognito_user_pool_client" "auth_site" {
  count = var.create_admin_panel ? 1 : 0

  name         = "${var.app_name}-auth-site-${var.deployment_environment}"
  user_pool_id = aws_cognito_user_pool.this.id

  # The vendor-neutral auth Lambda verifies passwords server-side via
  # AdminInitiateAuth (ADMIN_USER_PASSWORD_AUTH); the browser never touches
  # Cognito. OAuth/PKCE and hosted-UI flows are unused by the SPA, so
  # allowed_oauth_flows_user_pool_client is disabled and no callback/logout URLs
  # are required.
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = false
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
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
      { for client in aws_cognito_user_pool_client.auth_site : "auth_site" => client }
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
  description             = "CMK for ${var.app_name}-${var.deployment_environment} vlinder_auth encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = merge(local.common_tags, { rg = "security" })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.app_name}-${var.deployment_environment}-vlinder-auth"
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

  # A user may hold several roles per tenant, so each (user, tenant, role) grant
  # is its own row. The range key is the composite "<tenantId>#<roleId>"
  # (attribute `tenantRole`); tenantId is retained as its own attribute for the
  # tenantId-index GSI. The Lambda writes/reads tenantRole via the
  # tenantRoleKey() helper in shared/roleAssignments.
  attributes = [
    { name = "userId", type = "S" },
    { name = "tenantRole", type = "S" },
    { name = "tenantId", type = "S" },
  ]
  hash_key  = "userId"
  range_key = "tenantRole"

  global_secondary_indices = [
    {
      name            = "tenantId-index"
      projection_type = "ALL"
      hash_key        = "tenantId"
      range_key       = "userId"
    }
  ]
}

# --- npm-packaged Lambda functions ------------------------------------------
#
# Lambda source is consumed from @vln-devsecops/auth-lambda on GitHub Packages
# (published from node-vlinder-auth) rather than vendored here, so version
# bumps flow through Dependabot PRs on lambda-build/package.json. The
# null_resource downloads the package at apply time; archive_file then zips
# the installed output. Contract tests mock the archive provider so they
# don't require a live npm install.
#
# To install locally before running terraform validate/test:
#   npm install --prefix modules/aws/vlinder_auth/lambda-build
#
# The build pipeline (esbuild) produces three self-contained CJS bundles at
# dist/post-confirmation/handler.js, dist/pre-token-generation/handler.js,
# and dist/admin-api/handler.js -- each with all dependencies (including the
# shared/ helpers) inlined. dist/ also contains a package.json marking the
# directory as "type": "commonjs" so Node loads the .js files as CJS
# regardless of the source package's ESM type setting. The zip includes the
# full dist/ tree; handler references use the subdirectory prefix:
# "<subdir>/handler.handler".

resource "null_resource" "lambda_package" {
  triggers = {
    package_json = filemd5("${path.module}/lambda-build/package.json")
  }

  provisioner "local-exec" {
    command = "npm install --prefix ${path.module}/lambda-build --ignore-scripts"
  }
}

data "archive_file" "lambda_package" {
  depends_on  = [null_resource.lambda_package]
  type        = "zip"
  source_dir  = "${path.module}/lambda-build/node_modules/@vln-devsecops/auth-lambda/dist"
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
      # CMK access for the tenants table (aws_kms_key.this) and the
      # role_assignments table (its own key) -- see the matching statement
      # on aws_iam_policy.pre_token_generation for the full rationale.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn, module.user_role_assignments.kms_key_arn]
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
  handler          = "post-confirmation/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 5
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

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
      # Every table this Lambda touches is encrypted with a customer-managed
      # CMK (roles/tenants + the Lambda's own env vars use aws_kms_key.this;
      # role_assignments has its own dedicated key), and DynamoDB requires
      # the *caller* to hold KMS permissions on the table's key -- table-arn
      # grants alone produce a runtime kms:Decrypt AccessDeniedException on
      # first invocation. GenerateDataKey is included even for read paths:
      # DynamoDB's table-level data-key caching can trigger it on the
      # caller's credentials regardless of the operation being a read.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn, module.user_role_assignments.kms_key_arn]
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
  handler          = "pre-token-generation/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 5
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

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
      # CMK access for the roles table (aws_kms_key.this) and the
      # role_assignments table (its own key) -- see the matching statement
      # on aws_iam_policy.pre_token_generation for the full rationale.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn, module.user_role_assignments.kms_key_arn]
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
  handler          = "admin-api/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 10
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

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
      authorizer_key       = "vlinder_auth"
    }
    get_user = {
      route_key            = "GET /users/{userId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "vlinder_auth"
    }
    set_user_enabled = {
      route_key            = "PATCH /users/{userId}/enabled"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "vlinder_auth"
    }
    list_roles = {
      route_key            = "GET /roles"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "vlinder_auth"
    }
    assign_role = {
      route_key            = "PUT /users/{userId}/roles/{roleId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "vlinder_auth"
    }
    revoke_role = {
      route_key            = "DELETE /users/{userId}/roles/{roleId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorizer_key       = "vlinder_auth"
    }
  } : {}
}

module "admin_api" {
  count  = var.create_admin_panel ? 1 : 0
  source = "../http_api"

  name = "${var.app_name}-${var.deployment_environment}-admin-api"

  jwt_authorizers = {
    vlinder_auth = {
      issuer_url = local.admin_api_issuer_url
      audience   = aws_cognito_user_pool_client.auth_site[*].id
    }
  }

  routes = local.admin_api_routes

  tags = local.common_tags
}

# --- Vendor-neutral auth API (public; the branded login's first-party backend)
#
# Step 1 of the vendor-neutral migration (see node-vlinder-auth/doc/
# vendor-neutral-auth.md): the auth Lambda serves the identifier-first login
# flow under /api/v1/auth (the SPA's only auth backend). The
# SPA does not consume it yet. Federation, the BFF /authorize+/token handoff,
# and the rest of the endpoint set land in later increments.

# Signing key for the identify/AS session JWS (HS256). Held only in the auth
# Lambda's environment, which is encrypted with this module's CMK. Rotating it
# invalidates in-flight sessions, which is acceptable (short-lived).
resource "random_password" "auth_session_signing_key" {
  count = var.create_admin_panel ? 1 : 0

  length  = 64
  special = false
}

resource "aws_iam_role" "auth_api" {
  count = var.create_admin_panel ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-auth-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "auth_api_logging" {
  count = var.create_admin_panel ? 1 : 0

  role       = aws_iam_role.auth_api[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "auth_api" {
  count = var.create_admin_panel ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-auth-api"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Login (server-side password verification).
          "cognito-idp:AdminInitiateAuth",
          # Self-service registration + recovery, wrapped server-side so the SPA
          # speaks only /api/v1/auth. These are Cognito's user-facing operations;
          # signed SDK calls from the Lambda are subject to IAM.
          "cognito-idp:SignUp",
          "cognito-idp:ConfirmSignUp",
          "cognito-idp:ResendConfirmationCode",
          "cognito-idp:ForgotPassword",
          "cognito-idp:ConfirmForgotPassword",
        ]
        Resource = [aws_cognito_user_pool.this.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "auth_api_permissions" {
  count = var.create_admin_panel ? 1 : 0

  role       = aws_iam_role.auth_api[0].name
  policy_arn = aws_iam_policy.auth_api[0].arn
}

resource "aws_lambda_function" "auth_api" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  count = var.create_admin_panel ? 1 : 0

  function_name    = "${var.app_name}-${var.deployment_environment}-auth-api"
  role             = aws_iam_role.auth_api[0].arn
  handler          = "auth-api/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 10
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      USER_POOL_ID        = aws_cognito_user_pool.this.id
      AUTH_CLIENT_ID      = one(aws_cognito_user_pool_client.auth_site[*].id)
      SESSION_SIGNING_KEY = one(random_password.auth_session_signing_key[*].result)
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.auth_api_logging]
}

locals {
  # Public routes (no JWT authorizer -- this is how a token is obtained). The
  # CloudFront /api/v1/auth* behavior strips the /api/v1 prefix, so the API
  # Gateway sees /auth/*.
  auth_api_routes = var.create_admin_panel ? {
    identify = {
      route_key            = "POST /auth/identify"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    password = {
      route_key            = "POST /auth/password"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    signup = {
      route_key            = "POST /auth/signup"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    confirm = {
      route_key            = "POST /auth/confirm"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    resend = {
      route_key            = "POST /auth/resend"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    forgot = {
      route_key            = "POST /auth/forgot"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
    reset = {
      route_key            = "POST /auth/reset"
      lambda_function_arn  = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name = one(aws_lambda_function.auth_api[*].function_name)
    }
  } : {}
}

module "auth_api" {
  count  = var.create_admin_panel ? 1 : 0
  source = "../http_api"

  name = "${var.app_name}-${var.deployment_environment}-auth-api"

  routes = local.auth_api_routes

  tags = local.common_tags
}

# --- Auth site hosting -------------------------------------------------------
#
# A single CloudFront distribution at auth.<zone> replaces both the Cognito
# hosted-UI custom domain and the former separate admin subdomain:
#
#   Default behavior   → S3 origin (OAC): serves the auth + admin SPA.
#                        A CloudFront Function rewrites extensionless paths to
#                        /index.html so client-side routing (React Router) works.
#                        Admin screens live at /admin (client-side route-guarded
#                        on the caller's JWT permissions claim), not a separate
#                        hostname -- no separate CloudFront distribution needed.
#
#   /api/v1/auth* behavior → Custom origin: the public auth HTTP API (the
#                        vendor-neutral login + self-service backend; the auth
#                        Lambda owns all Cognito interaction). TTL 0, never
#                        cached. Cookies forwarded (the in-flight identify
#                        session). Ordered before /api/v1/* so auth requests
#                        never fall through to the admin API. A CloudFront
#                        Function strips /api/v1 before forwarding.
#
#   /api/v1/* behavior → Custom origin: the admin HTTP API (JWT-protected),
#                        TTL 0, never cached. Forwards Authorization +
#                        Content-Type. A CloudFront Function strips /api/v1
#                        before forwarding. Only provisioned when
#                        create_admin_panel is true.
#
# Branding: the SPA reads its theme at runtime from ui-auth's theme.ts
# mechanism (which uses CSS custom properties). The former logo_base64 / css
# variables (which fed Cognito's hosted-UI) are removed -- override theme
# directly in the SPA's own configuration instead.
#
# The actual SPA build (dist/) is a deploy-pipeline concern, not managed by
# Terraform. The auth_site_bucket_name output lets a pipeline target the
# correct bucket. A placeholder index.html is created on first apply so the
# distribution is immediately testable.

# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "auth_site" {
  # checkov:skip=CKV_AWS_18:Access logging optional; caller provides log bucket when needed
  # checkov:skip=CKV_AWS_21:Versioning not required for OAC-protected public content
  # checkov:skip=CKV_AWS_144:Cross-region replication not required for OAC-protected public content
  # checkov:skip=CKV_AWS_145:KMS encryption not required for OAC-protected public content
  # checkov:skip=CKV2_AWS_61:S3 deletion protection by policy for OAC-protected public bucket
  # checkov:skip=CKV2_AWS_62:Event notifications not required for OAC-protected public content
  bucket        = local.auth_site_bucket_name
  force_destroy = var.auth_site_force_destroy
  tags          = merge(local.common_tags, { rg = "storage" })
}

resource "aws_s3_bucket_public_access_block" "auth_site" {
  bucket = aws_s3_bucket.auth_site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "auth_site_placeholder_index" {
  bucket       = aws_s3_bucket.auth_site.id
  key          = "index.html"
  content      = <<-HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${local.auth_site_domain}</title>
        <style>body{font-family:system-ui,sans-serif;margin:2rem}</style>
      </head>
      <body>
        <h1>Auth site placeholder</h1>
        <p>Deploy the auth SPA to this bucket to replace this page.</p>
      </body>
    </html>
  HTML
  content_type = "text/html; charset=utf-8"

  lifecycle {
    ignore_changes = [content, content_type, cache_control]
  }
}

resource "aws_cloudfront_origin_access_control" "auth_site" {
  name                              = "${replace(local.auth_site_domain, ".", "-")}-oac"
  description                       = "Origin access control for ${local.auth_site_domain} SPA"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_viewer_request" {
  name    = "${replace(local.auth_site_domain, ".", "-")}-spa-vr"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "SPA route rewriting for ${local.auth_site_domain}"
  code    = file("${path.module}/templates/spa_viewer_request.js")
}

resource "aws_cloudfront_function" "admin_api_rewrite" {
  count = var.create_admin_panel ? 1 : 0

  name    = "${replace(local.auth_site_domain, ".", "-")}-admin-api-vr"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Strips /api/v1 prefix before forwarding to admin HTTP API for ${local.auth_site_domain}"
  code    = file("${path.module}/templates/admin_api_rewrite.js")
}

resource "aws_cloudfront_function" "auth_api_rewrite" {
  count = var.create_admin_panel ? 1 : 0

  name    = "${replace(local.auth_site_domain, ".", "-")}-auth-api-vr"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Strips /api/v1 prefix before forwarding to auth HTTP API for ${local.auth_site_domain}"
  code    = file("${path.module}/templates/auth_api_rewrite.js")
}

data "aws_iam_policy_document" "auth_site_cloudfront_read" {
  version = "2012-10-17"

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.auth_site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.auth_site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "auth_site" {
  bucket = aws_s3_bucket.auth_site.id
  policy = data.aws_iam_policy_document.auth_site_cloudfront_read.json
}

# trivy:ignore:AVD-AWS-0011
resource "aws_cloudfront_distribution" "auth_site" {
  # checkov:skip=CKV_AWS_310:Single-origin SPA does not need origin failover
  # checkov:skip=CKV_AWS_374:Geo restriction intentionally disabled
  # checkov:skip=CKV2_AWS_32:Response headers policy caller-configurable
  # checkov:skip=CKV2_AWS_47:No EC2 in this module
  # checkov:skip=CKV_AWS_68:WAF is caller-configurable via var.waf_web_acl_arn; not enforced at module level
  # checkov:skip=CKV_AWS_86:CloudFront access logging is caller-configurable; not enforced at module level
  enabled             = true
  aliases             = [local.auth_site_domain]
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = var.cloudfront_price_class
  web_acl_id          = var.waf_web_acl_arn

  # Default origin: S3 bucket serving the auth + admin SPA
  origin {
    domain_name              = aws_s3_bucket.auth_site.bucket_regional_domain_name
    origin_id                = "AuthSiteS3"
    origin_access_control_id = aws_cloudfront_origin_access_control.auth_site.id
  }

  # Admin API origin: the admin SPA calls this same-origin via /api/v1
  dynamic "origin" {
    for_each = var.create_admin_panel ? [one(module.admin_api[*].invoke_url)] : []
    content {
      domain_name = regex("https://([^/]+)", origin.value)[0]
      origin_id   = "AdminApi"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Auth API origin: the login SPA calls this same-origin via /api/v1/auth
  dynamic "origin" {
    for_each = var.create_admin_panel ? [one(module.auth_api[*].invoke_url)] : []
    content {
      domain_name = regex("https://([^/]+)", origin.value)[0]
      origin_id   = "AuthApi"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default behavior: SPA static assets from S3
  default_cache_behavior {
    target_origin_id       = "AuthSiteS3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_viewer_request.arn
    }
  }

  # /api/v1/auth* behavior: proxy to the public auth HTTP API (login flow).
  # Ordered BEFORE /api/v1/* so auth requests never fall through to the admin
  # API. Cookies are forwarded both ways -- the flow reads/sets the HttpOnly
  # identify/AS session cookies.
  dynamic "ordered_cache_behavior" {
    for_each = var.create_admin_panel ? [one(aws_cloudfront_function.auth_api_rewrite[*].arn)] : []
    content {
      path_pattern           = "/api/v1/auth*"
      target_origin_id       = "AuthApi"
      viewer_protocol_policy = "https-only"
      compress               = false

      allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods  = ["GET", "HEAD"]

      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Content-Type"]
        cookies {
          forward = "all"
        }
      }

      min_ttl     = 0
      default_ttl = 0
      max_ttl     = 0

      function_association {
        event_type   = "viewer-request"
        function_arn = ordered_cache_behavior.value
      }
    }
  }

  # /api/v1/* behavior: proxy to the admin HTTP API (JWT-protected)
  dynamic "ordered_cache_behavior" {
    for_each = var.create_admin_panel ? [one(aws_cloudfront_function.admin_api_rewrite[*].arn)] : []
    content {
      path_pattern           = "/api/v1/*"
      target_origin_id       = "AdminApi"
      viewer_protocol_policy = "https-only"
      compress               = false

      allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods  = ["GET", "HEAD"]

      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Content-Type"]
        cookies {
          forward = "none"
        }
      }

      min_ttl     = 0
      default_ttl = 0
      max_ttl     = 0

      function_association {
        event_type   = "viewer-request"
        function_arn = ordered_cache_behavior.value
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = merge(local.common_tags, { rg = "compute" })
}

resource "aws_route53_record" "auth_site_a" {
  zone_id = var.route53_zone_id
  name    = local.auth_site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.auth_site.domain_name
    zone_id                = aws_cloudfront_distribution.auth_site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_site_aaaa" {
  zone_id = var.route53_zone_id
  name    = local.auth_site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.auth_site.domain_name
    zone_id                = aws_cloudfront_distribution.auth_site.hosted_zone_id
    evaluate_target_health = false
  }
}
