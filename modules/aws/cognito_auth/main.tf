data "aws_route53_zone" "this" {
  zone_id = var.route53_zone_id
}

locals {
  base_domain        = trimsuffix(data.aws_route53_zone.this.name, ".")
  hosted_ui_domain   = "${var.domain_prefix}-${local.base_domain}"
  admin_panel_domain = "${var.admin_panel_domain_prefix}-${local.base_domain}"

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

  # lambda_config is added in the Lambda slice, once aws_lambda_function.post_confirmation
  # and .pre_token_generation exist -- see tests/lambdas.tftest.hcl.

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
      var.create_admin_panel ? { admin_panel = aws_cognito_user_pool_client.admin_panel[0] } : {}
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

  server_side_encryption {
    enabled = true
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

  server_side_encryption {
    enabled = true
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
