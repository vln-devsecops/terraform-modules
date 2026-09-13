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
  # tenantId to key role assignments on. Either way, the auth application
  # gets its own reserved tenant ("auth") so auth.<zone> reached without a
  # client_id -- the admin panel, and later a user profile -- still resolves
  # to a real tenant instead of "no tenant": even a single-tenant deployment
  # has at least two tenants, one for the adopter app and one for this one.
  consumer_tenants = var.tenancy_mode == "multi" ? var.tenants : {
    default = { name = "Default", email_domain = null, identity_providers = null }
  }
  effective_tenants = merge(local.consumer_tenants, {
    auth = { name = "Auth", email_domain = null, identity_providers = null }
  })

  auth_site_bucket_name = "${var.app_name}-${var.deployment_environment}-auth-site"

  # auth_profile resolves into the individual layer gates used throughout this
  # file. Each implies the one below it: create_admin_panel implies
  # create_public_auth_api implies create_auth_site.
  create_admin_panel     = var.auth_profile == "full"
  create_public_auth_api = contains(["full", "auth_api"], var.auth_profile)
  create_auth_site       = contains(["full", "auth_api"], var.auth_profile)
}

# --- Identity ---------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name = "${var.app_name}-${var.deployment_environment}-user-pool"

  deletion_protection = var.user_pool_deletion_protection

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

  # Threat protection (compromised-credential checks, adaptive auth). Defaults
  # to OFF -- AUDIT/ENFORCED require the Plus feature plan (or a paid Lite-tier
  # add-on) and are billed per MAU regardless of mode -- see
  # doc/auth-api-rate-limiting.md.
  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

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
    pre_sign_up       = aws_lambda_function.pre_sign_up.arn
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
  count = local.create_auth_site ? 1 : 0

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

  # Cognito's own refresh-token lifetime, made an explicit, named 30-day
  # value here rather than left at Cognito's undocumented-in-this-codebase
  # default -- matches aws_lambda_function.auth_api's
  # REFRESH_TOKEN_TTL_SECONDS (2,592,000 seconds = 30 days) below so the two
  # move in lockstep.
  refresh_token_validity = 30
  token_validity_units {
    refresh_token = "days"
  }

  # Native rotation-with-reuse-detection: each REFRESH_TOKEN_AUTH call
  # returns a new refresh token and invalidates the old one, and replaying an
  # already-rotated-away token revokes the whole token family. 60 seconds is
  # the maximum grace period AWS allows. node-vlinder-auth's
  # doc/rationale.md already mandates that front-end clients single-flight
  # concurrent refreshes specifically to avoid tripping reuse detection, so
  # this grace period isn't covering that case -- it's for an ordinary
  # client-side retry after a lost/timed-out response to a rotation that
  # *did* commit at Cognito. Without a grace period, that legitimate retry
  # would look identical to a stolen-refresh-token replay and revoke the
  # whole family.
  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 60
  }
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

# Schema (tenantId hash key, sk range key, emailDomain + clientId GSIs) stays
# stable across tenancy_mode switches so toggling the mode later doesn't force
# a table replacement. One item type per sk prefix:
#   - "PROFILE"          -- the tenant record itself (name, legacy emailDomain
#                            used only by the signup-time tenant lookup below).
#   - "CLIENT#<clientId>" -- client_id -> tenant_id registry entry, looked up
#                            via the clientId-index (the tenant isn't known
#                            yet when this lookup happens, hence the GSI).
#   - "DOMAIN#<domain>"   -- (email_domain, tenant_id) -> identity provider
#                            pin. Looked up by GetItem on the primary key
#                            since the tenant is already known by then (from
#                            client_id) -- no GSI needed.
resource "aws_dynamodb_table" "tenants" {
  name         = "ddb-${var.app_name}-${var.deployment_environment}-${local.short_region}-auth-tenants"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenantId"
  range_key    = "sk"

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "emailDomain"
    type = "S"
  }

  attribute {
    name = "clientId"
    type = "S"
  }

  global_secondary_index {
    name            = "emailDomain-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "emailDomain"
      key_type       = "HASH"
    }
  }

  global_secondary_index {
    name            = "clientId-index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "clientId"
      key_type       = "HASH"
    }
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
  range_key  = aws_dynamodb_table.tenants.range_key

  item = jsonencode(merge(
    {
      tenantId = { S = each.key }
      sk       = { S = "PROFILE" }
      name     = { S = each.value.name }
    },
    each.value.email_domain == null ? {} : {
      emailDomain = { S = each.value.email_domain }
    }
  ))
}

# The client_id -> tenant_id registry: every consumer client belongs to a
# tenant ("default" in single-tenant mode, since var.tenants/tenant_id are
# meaningless there), plus the auth application's own client below.
resource "aws_dynamodb_table_item" "tenant_clients" {
  for_each = aws_cognito_user_pool_client.consumer

  table_name = aws_dynamodb_table.tenants.name
  hash_key   = aws_dynamodb_table.tenants.hash_key
  range_key  = aws_dynamodb_table.tenants.range_key

  item = jsonencode({
    tenantId = { S = var.tenancy_mode == "multi" ? var.clients[each.key].tenant_id : "default" }
    sk       = { S = "CLIENT#${each.value.id}" }
    clientId = { S = each.value.id }
    # The RP handoff's /authorize endpoint (node-vlinder-auth's
    # resolveClientRedirectUris) rejects any redirect_uri not in this exact
    # list -- the open-redirect guard. Reuses the same callback_urls this
    # client's own Cognito app client already declares, rather than a
    # second, potentially-drifting allowlist.
    redirectUris = { L = [for url in var.clients[each.key].callback_urls : { S = url }] }
  })
}

# auth.<zone> reached without a client_id (the admin panel, and later a user
# profile) resolves to the auth application's own tenant, not "no tenant" --
# this registers its Cognito client under that reserved tenant id so the
# same client_id -> tenant_id lookup path covers it too, even though
# resolveTenantIdForClient's real fast path is "no client_id at all".
resource "aws_dynamodb_table_item" "auth_site_tenant_client" {
  count = local.create_auth_site ? 1 : 0

  table_name = aws_dynamodb_table.tenants.name
  hash_key   = aws_dynamodb_table.tenants.hash_key
  range_key  = aws_dynamodb_table.tenants.range_key

  item = jsonencode({
    tenantId = { S = "auth" }
    sk       = { S = "CLIENT#${aws_cognito_user_pool_client.auth_site[0].id}" }
    clientId = { S = aws_cognito_user_pool_client.auth_site[0].id }
  })
}

# The (email_domain, tenant_id) -> identity provider pins: a tenant's domain
# owner can lock their users to a corporate IdP. Keyed by (tenantId, domain)
# rather than a global domain GSI, since the tenant is already resolved (via
# client_id) by the time this is looked up -- see resolveIdentityProviderForDomain.
locals {
  # Lowercased here to match resolveIdentityProviderForDomain's own
  # `email.split('@')[1]?.toLowerCase()` -- the DOMAIN# key must agree with
  # what the lookup actually queries, or a mixed-case domain in var.tenants
  # (e.g. "Acme.com") would silently never match and fall through to the
  # tenant's defaults instead of enforcing the pinned IdP.
  tenant_domain_providers = merge([
    for tenant_id, tenant in local.effective_tenants : {
      for domain, provider_id in coalesce(tenant.identity_providers, {}) :
      "${tenant_id}#${lower(domain)}" => { tenant_id = tenant_id, domain = lower(domain), provider_id = provider_id }
    }
  ]...)
}

resource "aws_dynamodb_table_item" "tenant_domain_providers" {
  for_each = local.tenant_domain_providers

  table_name = aws_dynamodb_table.tenants.name
  hash_key   = aws_dynamodb_table.tenants.hash_key
  range_key  = aws_dynamodb_table.tenants.range_key

  item = jsonencode({
    tenantId           = { S = each.value.tenant_id }
    sk                 = { S = "DOMAIN#${each.value.domain}" }
    domain             = { S = each.value.domain }
    identityProviderId = { S = each.value.provider_id }
  })
}

# The sensitive access-control table (who has which role in which tenant)
# composes the shared aws/dynamodb module for its dedicated-CMK encryption,
# unlike the two reference-data tables above.
module "user_role_assignments" {
  source = "../dynamodb"

  app_name                    = var.app_name
  deployment_environment      = var.deployment_environment
  function                    = "auth-role-assignments"
  short_deployment_region     = local.short_region
  deletion_protection_enabled = var.role_assignments_deletion_protection_enabled

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
# bumps flow through Dependabot PRs against lambda-build/package-lock.json.
# The null_resource installs the package at apply time via `npm ci`, which
# installs exactly the resolved tree recorded in package-lock.json regardless
# of the semver range in package.json -- that lockfile, not the range, is what
# pins the build. archive_file then zips the installed output. Contract tests
# mock the archive provider so they don't require a live npm install.
#
# To install locally before running terraform validate/test:
#   npm ci --prefix modules/aws/vlinder_auth/lambda-build
#
# The build pipeline (esbuild) produces five self-contained CJS bundles at
# dist/pre-sign-up/handler.js, dist/post-confirmation/handler.js,
# dist/pre-token-generation/handler.js, dist/admin-api/handler.js, and
# dist/auth-api/handler.js -- each with all dependencies (including the
# shared/ helpers) inlined. dist/ also contains a
# package.json marking the directory as "type": "commonjs" so Node loads the
# .js files as CJS regardless of the source package's ESM type setting. The
# zip includes the full dist/ tree; handler references use the subdirectory
# prefix:
# "<subdir>/handler.handler".

resource "null_resource" "lambda_package" {
  # install_present guards against a fresh checkout against existing remote
  # state: the lockfile hash alone is unchanged there (it's the same file
  # that produced the state), so without this the provisioner would never
  # run and archive_file would zip a missing or stale local install. This is
  # eventually consistent rather than exact -- the first apply after a fresh
  # `npm ci` records the pre-install "missing" value, so the next plan (now
  # seeing the installed tree) diffs once more and reinstalls a second,
  # redundant time before settling on "present" -- an acceptable cost for a
  # cheap, idempotent `npm ci --ignore-scripts`.
  triggers = {
    package_json    = filemd5("${path.module}/lambda-build/package.json")
    package_lock    = filemd5("${path.module}/lambda-build/package-lock.json")
    install_present = fileexists("${path.module}/lambda-build/node_modules/@vln-devsecops/auth-lambda/dist/post-confirmation/handler.js") ? "present" : "missing"
  }

  provisioner "local-exec" {
    command = "npm ci --prefix ${path.module}/lambda-build --ignore-scripts"
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

resource "aws_iam_role" "pre_sign_up" {
  name               = "${var.app_name}-${var.deployment_environment}-pre-sign-up"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "pre_sign_up_logging" {
  role       = aws_iam_role.pre_sign_up.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# No other permissions: the handler unconditionally sets
# autoConfirmUser/autoVerifyEmail on the event and returns it -- it never
# touches DynamoDB, Cognito's admin API, or anything else.
resource "aws_lambda_function" "pre_sign_up" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_173:No environment block at all (this handler takes no env vars), so there's nothing for Checkov to find encrypted -- kms_key_arn below still encrypts the function's own configuration at rest, same as every other Lambda in this module
  function_name    = "${var.app_name}-${var.deployment_environment}-pre-sign-up"
  role             = aws_iam_role.pre_sign_up.arn
  handler          = "pre-sign-up/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 5
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.pre_sign_up_logging]
}

resource "aws_lambda_permission" "pre_sign_up" {
  statement_id  = "AllowCognitoInvokePreSignUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_sign_up.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
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
  count = local.create_admin_panel ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-admin-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "admin_api_logging" {
  count = local.create_admin_panel ? 1 : 0

  role       = aws_iam_role.admin_api[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "admin_api" {
  count = local.create_admin_panel ? 1 : 0

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
  count = local.create_admin_panel ? 1 : 0

  role       = aws_iam_role.admin_api[0].name
  policy_arn = aws_iam_policy.admin_api[0].arn
}

resource "aws_lambda_function" "admin_api" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  count = local.create_admin_panel ? 1 : 0

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
  admin_api_routes = local.create_admin_panel ? {
    list_users = {
      route_key            = "GET /api/v1/users"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
    get_user = {
      route_key            = "GET /api/v1/users/{userId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
    set_user_enabled = {
      route_key            = "PATCH /api/v1/users/{userId}/enabled"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
    list_roles = {
      route_key            = "GET /api/v1/roles"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
    assign_role = {
      route_key            = "PUT /api/v1/users/{userId}/roles/{roleId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
    revoke_role = {
      route_key            = "DELETE /api/v1/users/{userId}/roles/{roleId}"
      lambda_function_arn  = one(aws_lambda_function.admin_api[*].arn)
      lambda_function_name = one(aws_lambda_function.admin_api[*].function_name)
      authorization_type   = "CUSTOM"
    }
  } : {}
}

module "admin_api_authorizer" {
  count  = local.create_admin_panel ? 1 : 0
  source = "../http_api_authorizer"

  name        = "${var.app_name}-${var.deployment_environment}-admin-api"
  require_jwt = true

  jwt_issuer_url     = local.admin_api_issuer_url
  jwt_audience       = one(aws_cognito_user_pool_client.auth_site[*].id)
  jwt_forward_claims = ["tenants", "scope"]

  kms_key_arn = aws_kms_key.this.arn

  tags = local.common_tags
}

module "admin_api" {
  count  = local.create_admin_panel ? 1 : 0
  source = "../http_api"

  name = "${var.app_name}-${var.deployment_environment}-admin-api"

  lambda_authorizer = {
    authorizer_uri           = one(module.admin_api_authorizer[*].authorizer_uri)
    authorizer_function_name = one(module.admin_api_authorizer[*].authorizer_function_name)
    identity_sources         = ["$request.header.X-Origin-Verify", "$request.header.Authorization"]
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

# Signing key for the identify/AS session JWS (HS256), stored in Secrets
# Manager rather than generated by Terraform: a Terraform-generated value
# (random_password, or any resource attribute) is written to Terraform state
# in plaintext regardless of the `sensitive` schema flag -- that flag only
# masks CLI/log output, it does not encrypt the state file. Secrets Manager
# generates the value itself via `aws secretsmanager get-random-password` and
# it is pushed straight to `put-secret-value` inside the local-exec shell
# below; the value only ever exists in that ephemeral process, never as a
# Terraform resource attribute.
#
# Ongoing rotation is a fixed 30-day cadence, but driven by
# aws_scheduler_schedule.auth_secret_rotation invoking
# aws_lambda_function.rotate_secret below -- not by a Terraform-apply-time
# trigger -- so an adopter isn't required to redeploy just to rotate a key.
# Same immediate-overwrite semantics either way (a plain PutSecretValue, not
# a staged AWSPENDING/AWSCURRENT rollover): sessions are short-lived, and
# invalidating in-flight ones on rotation is an already-accepted tradeoff.
#
# The *initial* seed (this secret has no value at all until something puts
# one) still needs secretsmanager:GetRandomPassword and PutSecretValue on
# whoever runs the first `terraform apply` -- not a role this module
# manages, same apply-time-CLI assumption the SPA deploy step below already
# makes for `aws s3 sync` / `aws cloudfront create-invalidation`. In this
# org that's the vln-devsecops-terraform-modules-integration role (see
# infra/rg_security.tf's terraform_modules_integration_test_policy, which
# must carry secretsmanager:GetRandomPassword for this to work).
resource "aws_secretsmanager_secret" "auth_session_signing_key" {
  count = local.create_public_auth_api ? 1 : 0

  # checkov:skip=CKV2_AWS_57:Rotation is handled by aws_scheduler_schedule.auth_secret_rotation invoking rotate_secret below, not aws_secretsmanager_secret_rotation
  name       = "${var.app_name}-${var.deployment_environment}-auth-session-signing-key"
  kms_key_id = aws_kms_key.this.id

  tags = merge(local.common_tags, { rg = "security" })
}

resource "null_resource" "auth_session_signing_key_seed" {
  count = local.create_public_auth_api ? 1 : 0

  # Bootstrap only: a freshly-created secret has no value at all until
  # something puts one, so this must still run once at first apply. Ongoing
  # rotation is no longer triggered here (no time_rotating dependency) --
  # aws_scheduler_schedule.auth_secret_rotation below invokes
  # aws_lambda_function.rotate_secret on a recurring schedule instead, so
  # rotation happens automatically without requiring a redeploy.
  triggers = {
    secret_id = one(aws_secretsmanager_secret.auth_session_signing_key[*].id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      RANDOM_VALUE="$(aws secretsmanager get-random-password \
        --exclude-punctuation --password-length 64 --require-each-included-type \
        --output text --query RandomPassword)"
      aws secretsmanager put-secret-value \
        --secret-id "${one(aws_secretsmanager_secret.auth_session_signing_key[*].id)}" \
        --secret-string "$RANDOM_VALUE"
    EOT
  }

  depends_on = [aws_secretsmanager_secret.auth_session_signing_key]
}

# The RP handoff's one-time token (node-vlinder-auth's oneTimeToken.ts) is a
# dir/A256GCM JWE, not a signed JWS like the session tokens above -- it
# carries the real Cognito AuthenticationResult end to end from /password to
# /token, so it must be opaque, not merely tamper-evident. A256GCM's dir mode
# needs exactly 32 raw key bytes; --password-length 32 with
# --exclude-punctuation guarantees 32 single-byte (alphanumeric) UTF-8
# characters, so the secret's string value is exactly 32 bytes as-is, no
# decoding step needed on the Lambda side. Same seed/rotation mechanism as
# auth_session_signing_key above -- an in-flight one-time token is even less
# of a concern here, since its own TTL is 60 seconds, not the AS session's
# lifetime.
resource "aws_secretsmanager_secret" "auth_one_time_token_key" {
  count = local.create_public_auth_api ? 1 : 0

  # checkov:skip=CKV2_AWS_57:Rotation is handled by aws_scheduler_schedule.auth_secret_rotation invoking rotate_secret below, not aws_secretsmanager_secret_rotation
  name       = "${var.app_name}-${var.deployment_environment}-auth-one-time-token-key"
  kms_key_id = aws_kms_key.this.id

  tags = merge(local.common_tags, { rg = "security" })
}

resource "null_resource" "auth_one_time_token_key_seed" {
  count = local.create_public_auth_api ? 1 : 0

  # Bootstrap only -- see the matching comment on
  # null_resource.auth_session_signing_key_seed above. Ongoing rotation is
  # aws_scheduler_schedule.auth_secret_rotation below.
  triggers = {
    secret_id = one(aws_secretsmanager_secret.auth_one_time_token_key[*].id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      RANDOM_VALUE="$(aws secretsmanager get-random-password \
        --exclude-punctuation --password-length 32 --require-each-included-type \
        --output text --query RandomPassword)"
      aws secretsmanager put-secret-value \
        --secret-id "${one(aws_secretsmanager_secret.auth_one_time_token_key[*].id)}" \
        --secret-string "$RANDOM_VALUE"
    EOT
  }

  depends_on = [aws_secretsmanager_secret.auth_one_time_token_key]
}

# The refresh token grant container (node-vlinder-auth's refreshToken.ts) is
# also a dir/A256GCM JWE wrapping a Cognito refresh token across rotations --
# see auth_one_time_token_key's identical reasoning above for why 32 raw key
# bytes and --exclude-punctuation/--password-length 32 apply unchanged here.
# Same seed/rotation mechanism as the other two secrets.
resource "aws_secretsmanager_secret" "auth_refresh_token_key" {
  count = local.create_public_auth_api ? 1 : 0

  # checkov:skip=CKV2_AWS_57:Rotation is handled by aws_scheduler_schedule.auth_secret_rotation invoking rotate_secret below, not aws_secretsmanager_secret_rotation
  name       = "${var.app_name}-${var.deployment_environment}-auth-refresh-token-key"
  kms_key_id = aws_kms_key.this.id

  tags = merge(local.common_tags, { rg = "security" })
}

resource "null_resource" "auth_refresh_token_key_seed" {
  count = local.create_public_auth_api ? 1 : 0

  # Bootstrap only -- see the matching comment on
  # null_resource.auth_session_signing_key_seed above. Ongoing rotation is
  # aws_scheduler_schedule.auth_secret_rotation below.
  triggers = {
    secret_id = one(aws_secretsmanager_secret.auth_refresh_token_key[*].id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      RANDOM_VALUE="$(aws secretsmanager get-random-password \
        --exclude-punctuation --password-length 32 --require-each-included-type \
        --output text --query RandomPassword)"
      aws secretsmanager put-secret-value \
        --secret-id "${one(aws_secretsmanager_secret.auth_refresh_token_key[*].id)}" \
        --secret-string "$RANDOM_VALUE"
    EOT
  }

  depends_on = [aws_secretsmanager_secret.auth_refresh_token_key]
}

# Rotates auth_session_signing_key and auth_one_time_token_key on a
# recurring schedule (aws_scheduler_schedule below) rather than only at
# `terraform apply` time, so an adopter isn't required to redeploy just to
# rotate a key. One Lambda handles both secrets -- which one, and what
# password length to generate, arrives as the schedule's own event input,
# not anything hardcoded here.
resource "aws_iam_role" "rotate_secret" {
  count = local.create_public_auth_api ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-rotate-secret"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rotate_secret_logging" {
  count = local.create_public_auth_api ? 1 : 0

  role       = aws_iam_role.rotate_secret[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "rotate_secret" {
  count = local.create_public_auth_api ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-rotate-secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetRandomPassword has no resource type of its own -- it isn't
        # scoped to a particular secret, only Resource = ["*"] is valid.
        Effect   = "Allow"
        Action   = ["secretsmanager:GetRandomPassword"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["secretsmanager:PutSecretValue"]
        Resource = [
          one(aws_secretsmanager_secret.auth_session_signing_key[*].arn),
          one(aws_secretsmanager_secret.auth_one_time_token_key[*].arn),
          one(aws_secretsmanager_secret.auth_refresh_token_key[*].arn),
        ]
      },
      # Writing a new value to a CMK-encrypted secret needs GenerateDataKey
      # on that CMK, the same way reading one needs Decrypt -- see the
      # matching statement on aws_iam_policy.pre_token_generation for the
      # full rationale on why DynamoDB/Secrets Manager with a
      # customer-managed key requires the *caller* to hold KMS permission.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rotate_secret_permissions" {
  count = local.create_public_auth_api ? 1 : 0

  role       = aws_iam_role.rotate_secret[0].name
  policy_arn = aws_iam_policy.rotate_secret[0].arn
}

resource "aws_lambda_function" "rotate_secret" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_173:No environment block at all (this handler takes no env vars -- which secret to rotate arrives as the schedule's event input instead), so there's nothing for Checkov to find encrypted -- kms_key_arn below still encrypts the function's own configuration at rest, same as every other Lambda in this module
  count = local.create_public_auth_api ? 1 : 0

  function_name    = "${var.app_name}-${var.deployment_environment}-rotate-secret"
  role             = aws_iam_role.rotate_secret[0].arn
  handler          = "rotate-secret/handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 10
  publish          = true
  kms_key_arn      = aws_kms_key.this.arn
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.rotate_secret_logging]
}

# EventBridge Scheduler needs its own role to assume when invoking the
# target -- distinct from the Lambda's own execution role above.
data "aws_iam_policy_document" "scheduler_assume_role" {
  count = local.create_public_auth_api ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotate_secret_scheduler" {
  count = local.create_public_auth_api ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-rotate-secret-scheduler"
  assume_role_policy = one(data.aws_iam_policy_document.scheduler_assume_role[*].json)
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "rotate_secret_scheduler" {
  count = local.create_public_auth_api ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-rotate-secret-scheduler"
  role = aws_iam_role.rotate_secret_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_function.rotate_secret[0].arn]
      },
    ]
  })
}

# Three schedules, not one rule with multiple targets: aws_scheduler_schedule
# models a single target per schedule, and each secret needs its own
# password length (64 for the session-signing key, 32 -- exactly what
# A256GCM's dir mode requires -- for the one-time-token and refresh-token
# keys) passed as distinct event input.
resource "aws_scheduler_schedule" "rotate_auth_session_signing_key" {
  # checkov:skip=CKV_AWS_297:A schedule's own stored config here is just a secret ARN and a password length, both already visible in this Terraform plan/state regardless -- not the secret value itself, which stays CMK-encrypted in Secrets Manager unaffected by this setting. Encrypting it with the module's own CMK would additionally require granting the scheduler.amazonaws.com service principal key-policy access, a real, apply-time-only-verifiable KMS grant not worth the risk for data with no confidentiality requirement.
  count = local.create_public_auth_api ? 1 : 0

  name                = "${var.app_name}-${var.deployment_environment}-rotate-session-signing-key"
  schedule_expression = "rate(30 days)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.rotate_secret[0].arn
    role_arn = aws_iam_role.rotate_secret_scheduler[0].arn
    input = jsonencode({
      secretId       = one(aws_secretsmanager_secret.auth_session_signing_key[*].id)
      passwordLength = 64
    })
  }
}

resource "aws_scheduler_schedule" "rotate_auth_one_time_token_key" {
  # checkov:skip=CKV_AWS_297:Same reasoning as rotate_auth_session_signing_key above -- stored input is a secret ARN and password length, not secret material.
  count = local.create_public_auth_api ? 1 : 0

  name                = "${var.app_name}-${var.deployment_environment}-rotate-one-time-token-key"
  schedule_expression = "rate(30 days)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.rotate_secret[0].arn
    role_arn = aws_iam_role.rotate_secret_scheduler[0].arn
    input = jsonencode({
      secretId       = one(aws_secretsmanager_secret.auth_one_time_token_key[*].id)
      passwordLength = 32
    })
  }
}

resource "aws_scheduler_schedule" "rotate_auth_refresh_token_key" {
  # checkov:skip=CKV_AWS_297:Same reasoning as rotate_auth_session_signing_key above -- stored input is a secret ARN and password length, not secret material.
  count = local.create_public_auth_api ? 1 : 0

  name                = "${var.app_name}-${var.deployment_environment}-rotate-refresh-token-key"
  schedule_expression = "rate(30 days)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.rotate_secret[0].arn
    role_arn = aws_iam_role.rotate_secret_scheduler[0].arn
    input = jsonencode({
      secretId       = one(aws_secretsmanager_secret.auth_refresh_token_key[*].id)
      passwordLength = 32
    })
  }
}

# Signup and password-reset codes, generated/verified by auth_api itself
# rather than Cognito's own email-verification mechanism (see node-vlinder-
# auth/doc/plan-auth-chrome-and-verification-codes.md). Short-TTL and
# reproducible (a fresh code can always be requested), unlike
# user_role_assignments, so deletion protection is off here rather than
# wired to its own consumer-facing variable.
module "verification_codes" {
  count  = local.create_public_auth_api ? 1 : 0
  source = "../dynamodb"

  app_name                    = var.app_name
  deployment_environment      = var.deployment_environment
  function                    = "auth-verification-codes"
  short_deployment_region     = local.short_region
  deletion_protection_enabled = false
  ttl_attribute               = "expiresAt"

  attributes = [
    { name = "email", type = "S" },
    { name = "purpose", type = "S" },
  ]
  hash_key  = "email"
  range_key = "purpose"
}

resource "aws_iam_role" "auth_api" {
  count = local.create_public_auth_api ? 1 : 0

  name               = "${var.app_name}-${var.deployment_environment}-auth-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "auth_api_logging" {
  count = local.create_public_auth_api ? 1 : 0

  role       = aws_iam_role.auth_api[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "auth_api" {
  count = local.create_public_auth_api ? 1 : 0

  name = "${var.app_name}-${var.deployment_environment}-auth-api"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Login (server-side password verification).
          "cognito-idp:AdminInitiateAuth",
          # Registration + password reset, wrapped server-side so the SPA
          # speaks only /api/v1/auth. Cognito's own code-generating/consuming
          # operations (ConfirmSignUp, ResendConfirmationCode, ForgotPassword,
          # ConfirmForgotPassword) are gone -- auth_api owns generating,
          # storing, verifying, and emailing its own codes (verification_codes
          # below) instead; PreSignUp auto-confirms every account so
          # AdminGetUser/AdminSetUserPassword are all Cognito needs to do once
          # a code checks out.
          "cognito-idp:SignUp",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminSetUserPassword",
        ]
        Resource = [aws_cognito_user_pool.this.arn]
      },
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          one(aws_secretsmanager_secret.auth_session_signing_key[*].arn),
          one(aws_secretsmanager_secret.auth_one_time_token_key[*].arn),
          one(aws_secretsmanager_secret.auth_refresh_token_key[*].arn),
        ]
      },
      {
        Effect = "Allow"
        Action = ["ses:SendEmail"]
        # try() rather than a direct reference: this whole statement only
        # matters once the lifecycle precondition below (on aws_lambda_function
        # .auth_api) is satisfied -- a direct reference would hard-error the
        # plan on a null ses_configuration before that friendlier precondition
        # message ever gets a chance to show.
        Resource = [try(var.ses_configuration.source_arn, "")]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [one(module.verification_codes[*].table_arn)]
      },
      # Tenancy resolution at /auth/identify: GetItem for the (tenantId,
      # "DOMAIN#<domain>") identity-provider pin (the tenant is already known
      # by then), Query on clientId-index to resolve client_id -> tenant_id
      # (the tenant *isn't* known yet, hence the GSI).
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = [aws_dynamodb_table.tenants.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = ["${aws_dynamodb_table.tenants.arn}/index/clientId-index"]
      },
      # This function's own environment variables are encrypted with
      # aws_kms_key.this, same as every other Lambda in this module, and it
      # also needs kms:Decrypt on the verification_codes table's own CMK
      # (DynamoDB requires the *caller* to hold KMS permissions on the
      # table's key -- see the matching statement on
      # aws_iam_policy.pre_token_generation for the full rationale) plus the
      # CMK-encrypted session-signing secret above. The tenants table shares
      # aws_kms_key.this, already covered.
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn, one(module.verification_codes[*].kms_key_arn)]
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "auth_api_permissions" {
  count = local.create_public_auth_api ? 1 : 0

  role       = aws_iam_role.auth_api[0].name
  policy_arn = aws_iam_policy.auth_api[0].arn
}

resource "aws_lambda_function" "auth_api" {
  # checkov:skip=CKV_AWS_115:Concurrent execution limit is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_116:DLQ integration is caller-configurable, not wired at module level
  # checkov:skip=CKV_AWS_117:VPC attachment is caller-configurable, not enforced at module level
  # checkov:skip=CKV_AWS_272:Code signing is caller-configurable, not enforced at module level
  count = local.create_public_auth_api ? 1 : 0

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
      USER_POOL_ID                   = aws_cognito_user_pool.this.id
      AUTH_CLIENT_ID                 = one(aws_cognito_user_pool_client.auth_site[*].id)
      TENANTS_TABLE_NAME             = aws_dynamodb_table.tenants.name
      AUTH_APP_TENANT_ID             = "auth"
      SESSION_SIGNING_KEY_SECRET_ID  = one(aws_secretsmanager_secret.auth_session_signing_key[*].arn)
      ONE_TIME_TOKEN_KEY_SECRET_ID   = one(aws_secretsmanager_secret.auth_one_time_token_key[*].arn)
      REFRESH_TOKEN_KEY_SECRET_ID    = one(aws_secretsmanager_secret.auth_refresh_token_key[*].arn)
      REFRESH_TOKEN_TTL_SECONDS      = "2592000"
      VERIFICATION_CODES_TABLE_NAME  = one(module.verification_codes[*].table_name)
      VERIFICATION_CODE_TTL_SECONDS  = tostring(var.verification_code_ttl_seconds)
      VERIFICATION_CODE_MAX_ATTEMPTS = tostring(var.verification_code_max_attempts)
      SES_FROM_ADDRESS               = try(var.ses_configuration.from_email_address, "")
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.auth_api_logging,
    null_resource.auth_session_signing_key_seed,
    null_resource.auth_one_time_token_key_seed,
    null_resource.auth_refresh_token_key_seed,
  ]

  lifecycle {
    precondition {
      condition     = var.ses_configuration != null
      error_message = "ses_configuration must be set whenever auth_profile provisions the public auth API (\"full\" or \"auth_api\") -- SES has no zero-config fallback the way COGNITO_DEFAULT was for Cognito's own built-in email."
    }
  }
}

locals {
  # Public routes (no JWT authorizer -- this is how a token is obtained). The
  # /api/v1 prefix is part of the route_key itself -- nothing strips it in
  # transit, so a future /api/v2 can be routed alongside without touching
  # this behavior or its CloudFront function.
  # throttling_burst_limit/rate_limit below are an aggregate, account-wide cap
  # shared across all callers of a route (not per-source-IP) -- see
  # doc/auth-api-rate-limiting.md for what this does and doesn't defend
  # against, and why waf_web_acl_arn is still recommended alongside it.
  auth_api_routes = local.create_public_auth_api ? {
    identify = {
      route_key              = "POST /api/v1/auth/identify"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    password = {
      route_key              = "POST /api/v1/auth/password"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    signup = {
      route_key              = "POST /api/v1/auth/signup"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    confirm = {
      route_key              = "POST /api/v1/auth/confirm"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    resend = {
      route_key              = "POST /api/v1/auth/resend"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    forgot = {
      route_key              = "POST /api/v1/auth/forgot"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
    reset = {
      route_key              = "POST /api/v1/auth/reset"
      lambda_function_arn    = one(aws_lambda_function.auth_api[*].arn)
      lambda_function_name   = one(aws_lambda_function.auth_api[*].function_name)
      throttling_burst_limit = var.auth_api_throttling.burst_limit
      throttling_rate_limit  = var.auth_api_throttling.rate_limit
      authorization_type     = "CUSTOM"
    }
  } : {}
}

module "auth_api_authorizer" {
  count  = local.create_public_auth_api ? 1 : 0
  source = "../http_api_authorizer"

  name = "${var.app_name}-${var.deployment_environment}-auth-api"

  kms_key_arn = aws_kms_key.this.arn

  tags = local.common_tags
}

module "auth_api" {
  count  = local.create_public_auth_api ? 1 : 0
  source = "../http_api"

  name = "${var.app_name}-${var.deployment_environment}-auth-api"

  lambda_authorizer = {
    authorizer_uri           = one(module.auth_api_authorizer[*].authorizer_uri)
    authorizer_function_name = one(module.auth_api_authorizer[*].authorizer_function_name)
    identity_sources         = ["$request.header.X-Origin-Verify"]
  }

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
#                        on the caller's JWT scope claim), not a separate
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
#                        before forwarding. Only provisioned in the "full"
#                        auth_profile.
#
# This whole distribution/bucket only exists for the "full" and "auth_api"
# auth_profiles (local.create_auth_site); "identity_only" provisions no site
# infra at all -- see the auth_profile variable for what each provisions.
#
# Branding: the SPA reads its theme at runtime from ui-auth's theme.ts
# mechanism (which uses CSS custom properties). The former logo_base64 / css
# variables (which fed Cognito's hosted-UI) are removed -- override theme
# directly in the SPA's own configuration instead.
#
# The SPA build is Terraform-managed, so `terraform apply` alone yields a
# working site (no separate deploy step). It is delivered the same way as the
# Lambda: the prebuilt static bundle is published to GitHub Packages as
# @vln-devsecops/auth-site (from node-vlinder-auth), pinned via
# site-build/package-lock.json, and installed at apply time by
# null_resource.auth_site_package via `npm ci` -- the lockfile, not the
# semver range in package.json, is what pins the resolved version. Terraform
# then writes the runtime config.json (the values that vary per deployment --
# the auth-site app-client id, the multi-tenant flag, and whether the admin
# API is enabled) into the installed bundle and syncs the whole thing to the
# S3 origin, invalidating CloudFront so the change takes effect. Version
# bumps flow through Dependabot PRs against site-build/package-lock.json,
# exactly like the Lambda. In the "auth_api" profile the same SPA bundle is
# still deployed (it serves the public login screens); its own config.json
# tells it there's no admin API to call, and it degrades accordingly instead
# of a separate placeholder page.

# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "auth_site" {
  # checkov:skip=CKV_AWS_18:Access logging optional; caller provides log bucket when needed
  # checkov:skip=CKV_AWS_21:Versioning not required for OAC-protected public content
  # checkov:skip=CKV_AWS_144:Cross-region replication not required for OAC-protected public content
  # checkov:skip=CKV_AWS_145:KMS encryption not required for OAC-protected public content
  # checkov:skip=CKV2_AWS_61:S3 deletion protection by policy for OAC-protected public bucket
  # checkov:skip=CKV2_AWS_62:Event notifications not required for OAC-protected public content
  count = local.create_auth_site ? 1 : 0

  bucket        = local.auth_site_bucket_name
  force_destroy = var.auth_site_force_destroy
  tags          = merge(local.common_tags, { rg = "storage" })
}

resource "aws_s3_bucket_public_access_block" "auth_site" {
  count = local.create_auth_site ? 1 : 0

  bucket = aws_s3_bucket.auth_site[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- SPA build delivery (Terraform-managed) ---------------------------------
#
# Installs the prebuilt @vln-devsecops/auth-site bundle at apply time (same
# mechanism as the Lambda: `npm ci` of a lockfile-pinned, GitHub Packages
# published artifact), writes the per-deployment config.json into it, and syncs
# it to the S3 origin. Guarded on create_auth_site -- the whole site (bucket,
# distribution, this deploy) doesn't exist in the "identity_only" profile.

locals {
  auth_site_dist_dir = "${path.module}/site-build/node_modules/@vln-devsecops/auth-site/dist"
  auth_site_config_json = jsonencode({
    userPoolClientId = one(aws_cognito_user_pool_client.auth_site[*].id)
    multiTenant      = var.tenancy_mode == "multi"
    adminEnabled     = local.create_admin_panel
  })

  # issuer/jwks_uri name Cognito's own endpoints directly -- never mirrored,
  # so key rotation is never served stale -- derived from the same
  # local.admin_api_issuer_url the admin API's JWT authorizer already
  # trusts, so there's one source of truth for "what issues our tokens".
  # authorization_endpoint/token_endpoint/end_session_endpoint are first-party
  # and stable now even though no handler answers them yet (plan.md step 6);
  # publishing the URL is independent of the endpoint existing, same as
  # identify.ts's /federation location before step 11 builds it.
  # response_types_supported/subject_types_supported/
  # id_token_signing_alg_values_supported are REQUIRED members of an OIDC
  # discovery document per OpenID Connect Discovery 1.0 -- distinct from,
  # and in addition to, the acknowledged issuer/host-mismatch deviation
  # (see doc/rationale.md and this module's README). Values reflect what
  # Cognito actually does: authorization code flow, public (not pairwise)
  # subject identifiers, RS256-signed tokens.
  auth_site_discovery_document_json = jsonencode({
    issuer                                = local.admin_api_issuer_url
    jwks_uri                              = "${local.admin_api_issuer_url}/.well-known/jwks.json"
    authorization_endpoint                = "https://${local.auth_site_domain}/api/v1/auth/authorize"
    token_endpoint                        = "https://${local.auth_site_domain}/api/v1/auth/token"
    end_session_endpoint                  = "https://${local.auth_site_domain}/api/v1/auth/logout"
    response_types_supported              = ["code"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
  })
}

resource "null_resource" "auth_site_package" {
  count = local.create_auth_site ? 1 : 0

  # install_present guards against a fresh checkout against existing remote
  # state -- see the matching comment on null_resource.lambda_package for why
  # the lockfile hash alone isn't enough, and the (self-healing, one-time
  # redundant reinstall) tradeoff this makes.
  triggers = {
    package_json    = filemd5("${path.module}/site-build/package.json")
    package_lock    = filemd5("${path.module}/site-build/package-lock.json")
    install_present = fileexists("${path.module}/site-build/node_modules/@vln-devsecops/auth-site/dist/index.html") ? "present" : "missing"
  }

  provisioner "local-exec" {
    command = "npm ci --prefix ${path.module}/site-build --ignore-scripts"
  }
}

# config.json is the only file that varies per deployment (the auth-site
# app-client id and the multi-tenant flag). Terraform writes it directly into
# the installed bundle so the sync below picks it up. Uses local_file, per the
# design intent that Terraform -- not a deploy script -- produces config.json.
resource "local_file" "auth_site_config" {
  count = local.create_auth_site ? 1 : 0

  filename = "${local.auth_site_dist_dir}/config.json"
  content  = local.auth_site_config_json

  depends_on = [null_resource.auth_site_package]
}

# The OIDC discovery document -- see doc/rationale.md's "The expected issuer
# is configuration, not a constant". Written the same way as config.json
# (Terraform, not a deploy script, produces it), into the same S3 origin, so
# the sync below picks it up automatically. local_file creates the
# .well-known/ subdirectory itself.
resource "local_file" "auth_site_discovery_document" {
  count = local.create_auth_site ? 1 : 0

  filename = "${local.auth_site_dist_dir}/.well-known/openid-configuration"
  content  = local.auth_site_discovery_document_json

  depends_on = [null_resource.auth_site_package]
}

resource "null_resource" "auth_site_deploy" {
  count = local.create_auth_site ? 1 : 0

  # Redeploy when the pinned SPA version changes (package-lock.json bump,
  # since that lockfile -- not the package.json semver range -- pins the
  # resolved version) or when the per-deployment config.json/discovery
  # document changes. Content of a given published version is immutable, so
  # filemd5 of the lockfile is a faithful proxy for "the SPA changed".
  triggers = {
    package_lock       = filemd5("${path.module}/site-build/package-lock.json")
    config             = local.auth_site_config_json
    discovery_document = local.auth_site_discovery_document_json
    bucket             = one(aws_s3_bucket.auth_site[*].id)
    distribution       = one(aws_cloudfront_distribution.auth_site[*].id)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws s3 sync "${local.auth_site_dist_dir}" "s3://${one(aws_s3_bucket.auth_site[*].id)}/" --delete
      # aws s3 sync guesses Content-Type from the file extension; the
      # discovery document is extensionless by specification (RFC 8414/OIDC
      # Discovery), so sync leaves it as binary/octet-stream. Several strict
      # OIDC client libraries validate the response's Content-Type and
      # reject a discovery document served as anything but application/json
      # -- overwrite it explicitly, same object, no content change.
      aws s3 cp "${local.auth_site_dist_dir}/.well-known/openid-configuration" \
        "s3://${one(aws_s3_bucket.auth_site[*].id)}/.well-known/openid-configuration" \
        --content-type "application/json"
      aws cloudfront create-invalidation \
        --distribution-id "${one(aws_cloudfront_distribution.auth_site[*].id)}" \
        --paths "/*"
    EOT
  }

  depends_on = [
    null_resource.auth_site_package,
    local_file.auth_site_config,
    local_file.auth_site_discovery_document,
    aws_s3_bucket_policy.auth_site,
  ]
}

resource "aws_cloudfront_origin_access_control" "auth_site" {
  count = local.create_auth_site ? 1 : 0

  name                              = "${replace(local.auth_site_domain, ".", "-")}-oac"
  description                       = "Origin access control for ${local.auth_site_domain} SPA"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_viewer_request" {
  count = local.create_auth_site ? 1 : 0

  name    = "${replace(local.auth_site_domain, ".", "-")}-spa-vr"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "SPA route rewriting for ${local.auth_site_domain}"
  code    = file("${path.module}/templates/spa_viewer_request.js")
}

# We host our own login UI rather than a hosted one precisely to control the
# experience, which makes closing off clickjacking against it our
# responsibility -- see doc/architecture.md's "Edge response headers"
# section. Only the default (SPA) behavior gets this policy; the /api/v1/*
# and /api/v1/auth* behaviors serve JSON, not framable HTML, so the same
# clickjacking concern doesn't apply to them the same way. Tracked
# separately in workspace-vlinder-auth for whether they need their own
# header posture (e.g. X-Content-Type-Options, Referrer-Policy).
resource "aws_cloudfront_response_headers_policy" "auth_site_default" {
  # checkov:skip=CKV_AWS_259:HSTS is enabled below (2-year max-age, subdomains
  #   included); this check additionally hard-requires preload=true, which
  #   this module won't force on every consumer -- submitting a domain to
  #   the browser-shipped HSTS preload list is a deliberate, hard-to-reverse
  #   operational choice for the caller's own domain, not something a
  #   reusable module should opt every deployment into by default.
  count = local.create_auth_site ? 1 : 0

  name = "${replace(local.auth_site_domain, ".", "-")}-default-headers"

  security_headers_config {
    frame_options {
      frame_option = "DENY"
      override     = true
    }

    content_security_policy {
      content_security_policy = "frame-ancestors 'none'"
      override                = true
    }

    # The distribution already forces HTTPS (viewer_protocol_policy =
    # redirect-to-https on every behavior); this pins that in the browser
    # too, closing the one-request window an active network attacker would
    # otherwise get before that redirect lands. Not preloaded -- that binds
    # the whole domain into a browser-shipped list outside our control.
    strict_transport_security {
      access_control_max_age_sec = 63072000 # 2 years, the usual HSTS floor
      include_subdomains         = true
      override                   = true
      preload                    = false
    }
  }

  # CORS-open for the OIDC discovery document (/.well-known/openid-configuration)
  # -- browser-side resource-server code must be able to fetch it cross-origin
  # to learn what issuer/keys to trust, and it carries nothing secret. A
  # CloudFront response-headers policy applies to its whole behavior, not a
  # sub-path, so this also opens CORS on the rest of the default behavior
  # (the login/admin SPA's static assets) -- all public, unauthenticated GETs
  # already, so that's not a new exposure.
  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true

    access_control_allow_origins {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD"]
    }

    access_control_allow_headers {
      items = ["*"]
    }
  }
}

resource "aws_cloudfront_function" "admin_api_rewrite" {
  count = local.create_admin_panel ? 1 : 0

  name    = "${replace(local.auth_site_domain, ".", "-")}-admin-api-vr"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Cookie-to-bearer lift and X-Origin-Verify strip for the admin HTTP API on ${local.auth_site_domain}"
  code    = file("${path.module}/templates/admin_api_rewrite.js")
}

# No auth_api_rewrite: the /api/v1/auth* routes are public and passed through
# unmodified (route_key already carries /api/v1 -- nothing strips it in
# transit), and the origin's custom_header override is what actually
# enforces X-Origin-Verify (it overwrites any viewer-supplied value of the
# same name unconditionally -- see the AuthApi origin block below), so a
# viewer-request function here would only ever be redundant defense-in-depth,
# not a real security boundary.

data "aws_iam_policy_document" "auth_site_cloudfront_read" {
  count = local.create_auth_site ? 1 : 0

  version = "2012-10-17"

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.auth_site[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.auth_site[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "auth_site" {
  count = local.create_auth_site ? 1 : 0

  bucket = aws_s3_bucket.auth_site[0].id
  policy = data.aws_iam_policy_document.auth_site_cloudfront_read[0].json
}

# trivy:ignore:AVD-AWS-0011
resource "aws_cloudfront_distribution" "auth_site" {
  # checkov:skip=CKV_AWS_310:Single-origin SPA does not need origin failover
  # checkov:skip=CKV_AWS_374:Geo restriction intentionally disabled
  # checkov:skip=CKV2_AWS_47:No EC2 in this module
  # checkov:skip=CKV_AWS_68:WAF is caller-configurable via var.waf_web_acl_arn; not enforced at module level
  # checkov:skip=CKV_AWS_86:CloudFront access logging is caller-configurable; not enforced at module level
  count = local.create_auth_site ? 1 : 0

  enabled             = true
  aliases             = [local.auth_site_domain]
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  http_version        = "http2"
  price_class         = var.cloudfront_price_class
  web_acl_id          = var.waf_web_acl_arn

  # Default origin: S3 bucket serving the auth + admin SPA
  origin {
    domain_name              = aws_s3_bucket.auth_site[0].bucket_regional_domain_name
    origin_id                = "AuthSiteS3"
    origin_access_control_id = aws_cloudfront_origin_access_control.auth_site[0].id
  }

  # Admin API origin: the admin SPA calls this same-origin via /api/v1.
  # custom_header injects the admin authorizer's shared secret on every
  # origin request -- the admin_api_rewrite CloudFront Function strips any
  # client-supplied copy of the same header first, so this is the only
  # possible source of a valid X-Origin-Verify by the time the request
  # leaves CloudFront. The admin_api_authorizer Lambda authorizer rejects
  # anything else, closing off direct execute-api access that would
  # otherwise bypass CloudFront (and any WAF attached to this distribution).
  dynamic "origin" {
    for_each = local.create_admin_panel ? [{
      invoke_url = one(module.admin_api[*].invoke_url)
      secret     = one(module.admin_api_authorizer[*].origin_verify_secret)
    }] : []
    content {
      domain_name = regex("https://([^/]+)", origin.value.invoke_url)[0]
      origin_id   = "AdminApi"

      custom_header {
        name  = "X-Origin-Verify"
        value = origin.value.secret
      }

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Auth API origin: the login SPA calls this same-origin via /api/v1/auth.
  # Same origin-verify header pattern as AdminApi above, via the separate
  # auth_api_authorizer instance (origin-check only, no JWT -- these routes
  # are intentionally public).
  dynamic "origin" {
    for_each = local.create_public_auth_api ? [{
      invoke_url = one(module.auth_api[*].invoke_url)
      secret     = one(module.auth_api_authorizer[*].origin_verify_secret)
    }] : []
    content {
      domain_name = regex("https://([^/]+)", origin.value.invoke_url)[0]
      origin_id   = "AuthApi"

      custom_header {
        name  = "X-Origin-Verify"
        value = origin.value.secret
      }

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
    target_origin_id           = "AuthSiteS3"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.auth_site_default[0].id

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
      function_arn = aws_cloudfront_function.spa_viewer_request[0].arn
    }
  }

  # /api/v1/auth* behavior: proxy to the public auth HTTP API (login flow).
  # Ordered BEFORE /api/v1/* so auth requests never fall through to the admin
  # API. Cookies are forwarded both ways -- the flow reads/sets the HttpOnly
  # identify/AS session cookies.
  dynamic "ordered_cache_behavior" {
    for_each = local.create_public_auth_api ? [true] : []
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

      # No function_association: these routes are public and passed through
      # unmodified -- see the comment above aws_cloudfront_function.admin_api_rewrite.
    }
  }

  # /api/v1/* behavior: proxy to the admin HTTP API (JWT-protected)
  dynamic "ordered_cache_behavior" {
    for_each = local.create_admin_panel ? [one(aws_cloudfront_function.admin_api_rewrite[*].arn)] : []
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
  count = local.create_auth_site ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.auth_site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.auth_site[0].domain_name
    zone_id                = aws_cloudfront_distribution.auth_site[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "auth_site_aaaa" {
  count = local.create_auth_site ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.auth_site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.auth_site[0].domain_name
    zone_id                = aws_cloudfront_distribution.auth_site[0].hosted_zone_id
    evaluate_target_health = false
  }
}
