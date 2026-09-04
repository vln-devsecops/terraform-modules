# --- Irreducible inputs ---------------------------------------------------
# No module in this repo can self-provision a Route 53 zone or an ACM
# certificate on a consumer's behalf, so these two remain required. Compose
# `aws/acm_certificate` (wildcard SANs supported) for a cert that covers both
# hostnames this module derives below.

variable "app_name" {
  description = "Application name prefix, used to derive resource names."
  type        = string
}

variable "deployment_environment" {
  description = "Deployment environment suffix (e.g. dev, staging, prod)."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID that will serve the auth site hostname this module derives."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 covering the auth site hostname (\"$${domain_prefix}.<zone>\"). A wildcard cert from aws/acm_certificate is a simple way to cover this and any future subdomains."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be an ACM certificate in us-east-1 (required for CloudFront)."
  }
}

# --- Branding (optional) ------------------------------------------------

variable "cloudfront_price_class" {
  description = "CloudFront price class for the auth site distribution."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "waf_web_acl_arn" {
  description = "ARN of a WAF web ACL in us-east-1 to associate with the auth site CloudFront distribution. Null (the default) disables WAF."
  type        = string
  default     = null
}

variable "auth_site_force_destroy" {
  description = "Whether to allow the auth site's S3 bucket to be force-destroyed even when non-empty. False by default -- the SPA assets are synced into the bucket by the module's deploy step rather than tracked as individual aws_s3_object resources, so terraform destroy can't empty the bucket on its own; a real deployment shouldn't have its content silently deleted. Live/ephemeral test suites should set this true."
  type        = bool
  default     = false
}

variable "user_pool_deletion_protection" {
  description = "Cognito user pool deletion protection. \"ACTIVE\" by default -- the pool holds every user credential for a deployment, and a bad plan (e.g. a rename that forces replacement) shouldn't be able to destroy every account. Set to \"INACTIVE\" for ephemeral test suites and other roots that are torn down as a matter of course."
  type        = string
  default     = "ACTIVE"

  validation {
    condition     = contains(["ACTIVE", "INACTIVE"], var.user_pool_deletion_protection)
    error_message = "user_pool_deletion_protection must be ACTIVE or INACTIVE."
  }
}

variable "role_assignments_deletion_protection_enabled" {
  description = "Whether to enable DynamoDB deletion protection on the user_role_assignments table (who has which role in which tenant). True by default -- unlike the roles/tenants catalog tables, this data isn't reproducible from Terraform config. Set false for ephemeral test suites and other roots that are torn down as a matter of course."
  type        = bool
  default     = true
}

# --- Identity (optional; sane defaults) ------------------------------------

variable "domain_prefix" {
  description = "Prefix used to derive the auth site domain: \"$${domain_prefix}.<zone-name>\"."
  type        = string
  default     = "auth"
}

variable "allow_self_signup" {
  description = "Whether users can sign themselves up via the auth site SPA. When false, only admin-created users can sign in (pool-wide setting)."
  type        = bool
  default     = true
}

variable "mfa_configuration" {
  description = "Cognito MFA configuration."
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["OFF", "OPTIONAL", "ON"], var.mfa_configuration)
    error_message = "mfa_configuration must be OFF, OPTIONAL, or ON."
  }
}

variable "password_policy" {
  description = "Password policy overrides. Defaults match doxchange's proven production configuration."
  type = object({
    minimum_length                   = optional(number, 8)
    require_lowercase                = optional(bool, true)
    require_uppercase                = optional(bool, true)
    require_numbers                  = optional(bool, true)
    require_symbols                  = optional(bool, true)
    password_history_size            = optional(number, 5)
    temporary_password_validity_days = optional(number, 7)
  })
  default = {}
}

variable "advanced_security_mode" {
  description = "Cognito advanced security / threat protection: compromised-credential checks, adaptive auth, risk-based challenges. AUDIT logs risk signals without changing sign-in UX; ENFORCED also challenges/blocks high-risk sign-ins; OFF disables it. Defaults to OFF: any non-OFF value requires the user pool's Plus feature plan (or the Lite-tier per-MAU add-on) and is billed per MAU on a tiered schedule regardless of AUDIT vs ENFORCED, so this module doesn't turn it on for you -- set to AUDIT (recommended first step) or ENFORCED once you've confirmed the cost fits your budget. See doc/auth-api-rate-limiting.md and https://aws.amazon.com/cognito/pricing/."
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["AUDIT", "ENFORCED", "OFF"], var.advanced_security_mode)
    error_message = "advanced_security_mode must be AUDIT, ENFORCED, or OFF."
  }
}

variable "auth_api_throttling" {
  description = "Per-route throttle limits applied to the public /auth/* routes (signup, password, forgot, resend, etc.) to blunt credential stuffing, user enumeration, and signup/email-send abuse. This is an aggregate cap shared across all callers of a route, not per-source-IP -- see doc/auth-api-rate-limiting.md for why waf_web_acl_arn is still recommended alongside it. burst_limit is a token-bucket capacity (a count of requests that may land instantaneously, not a per-second figure); rate_limit is the steady-state refill rate in requests per second. E.g. the defaults (burst_limit=10, rate_limit=5) allow a burst of up to 10 requests, then throttle to 5 req/s sustained, per route, aggregated across all callers."
  type = object({
    burst_limit = optional(number, 10) # token-bucket capacity (request count, not a rate)
    rate_limit  = optional(number, 5)  # steady-state refill rate, in requests/second
  })
  default = {}
}

variable "clients" {
  description = "Map of app clients this module should create for the consumer's own frontend(s), keyed by a logical name. The admin panel's own client is always created separately and does not need an entry here. Empty by default -- add entries once you know your app's callback/logout URLs."
  type = map(object({
    generate_secret      = optional(bool, false)
    callback_urls        = list(string)
    logout_urls          = list(string)
    allowed_oauth_scopes = optional(list(string), ["openid", "email", "profile"])
  }))
  default = {}
}

variable "groups" {
  description = "Optional Cognito groups to create, keyed by group name. Coarse and cosmetic relative to the DynamoDB-backed privilege system below -- present mainly for consumers who want a cognito:groups claim as an additional coarse signal."
  type = map(object({
    description = optional(string, "")
    precedence  = optional(number, 10)
  }))
  default = {}
}

variable "baseline_groups" {
  description = "Names of groups (must be keys of var.groups) every newly-confirmed user is added to."
  type        = list(string)
  default     = []
}

variable "create_identity_pool" {
  description = "Whether to create a Cognito identity pool for temporary AWS credential vending. Off by default -- this component's primary integration mode is OIDC/JWT, not direct AWS SDK access from clients."
  type        = bool
  default     = false
}

variable "identity_pool_authenticated_role_policy_arns" {
  description = "IAM policy ARNs to attach to the identity pool's authenticated role. Only used when create_identity_pool is true."
  type        = list(string)
  default     = []
}

variable "ses_configuration" {
  description = "SES identity to send verification/invite emails through (branded from-address, better deliverability). Required whenever auth_profile provisions the public auth API (\"full\" or \"auth_api\") -- auth_api generates and emails its own signup/password-reset codes via SES, with no zero-config fallback the way COGNITO_DEFAULT was for Cognito's own built-in email. Ignored (and may be left null) in the \"identity_only\" profile, where Cognito's own built-in email service (COGNITO_DEFAULT) still backs the separate, unused-by-default email-change re-verification flow."
  type = object({
    configuration_set_name = string
    source_arn             = string
    from_email_address     = string
  })
  default = null
}

check "ses_configuration_required_for_public_auth_api" {
  assert {
    condition     = !local.create_public_auth_api || var.ses_configuration != null
    error_message = "ses_configuration must be set whenever auth_profile provisions the public auth API (\"full\" or \"auth_api\")."
  }
}

variable "verification_code_ttl_seconds" {
  description = "How long a generated signup/password-reset verification code remains valid, in seconds. Also becomes the DynamoDB table's TTL for that row, so an expired code is eventually reaped rather than kept around indefinitely."
  type        = number
  default     = 600
}

variable "verification_code_max_attempts" {
  description = "How many incorrect verification-code submissions are allowed before the code is locked out and a new one must be requested."
  type        = number
  default     = 5
}

# --- RBAC and tenancy (optional; single-tenant default) --------------------

variable "tenancy_mode" {
  description = "\"single\" (default): exactly one implicit tenant, no tenant CRUD, no tenant switcher in the admin panel. \"multi\": real tenant records and tenant-scoped role assignment."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "multi"], var.tenancy_mode)
    error_message = "tenancy_mode must be \"single\" or \"multi\"."
  }
}

variable "tenants" {
  description = "Tenant catalog, keyed by tenantId. Only meaningful when tenancy_mode is \"multi\" -- ignored in \"single\" mode, where a single implicit \"default\" tenant is used instead. email_domain drives the post-confirmation trigger's tenant-resolution lookup."
  type = map(object({
    name         = string
    email_domain = optional(string)
  }))
  default = {}
}

variable "roles" {
  description = "Role catalog, keyed by role name: the app-defined vocabulary mapping a role to the privileges it grants and whether it's tenant-scoped or global (cross-tenant, super-admin-style). Defaults to a minimal member/admin catalog so this module works with zero custom roles; override to define your own vocabulary."
  type = map(object({
    privileges   = list(string)
    tenant_scope = optional(string, "tenant")
  }))
  default = {
    member = {
      privileges   = []
      tenant_scope = "tenant"
    }
    admin = {
      privileges   = ["admin:users:read:own", "admin:users:write:own", "admin:roles:read"]
      tenant_scope = "tenant"
    }
  }

  validation {
    condition     = alltrue([for role in values(var.roles) : contains(["tenant", "global"], role.tenant_scope)])
    error_message = "Every role's tenant_scope must be \"tenant\" or \"global\"."
  }
}

variable "default_role_id" {
  description = "Role (must be a key of var.roles) every newly-confirmed user is assigned."
  type        = string
  default     = "member"

  validation {
    condition     = contains(keys(var.roles), var.default_role_id)
    error_message = "default_role_id must be a key of var.roles."
  }
}

# --- Auth profile (optional layers; full by default) ------------------------

variable "auth_profile" {
  description = "Which optional layers of the module to provision, from most to least:\n  \"full\" (default): public auth API + bundled admin API/panel + the auth-site CloudFront/S3/SPA shell serving both.\n  \"auth_api\": public auth API (login/session backend) + the auth-site shell serving just the login SPA at \"/\" -- no admin API/panel; bring your own admin UI against the RBAC table and Cognito Admin APIs.\n  \"identity_only\": Cognito user pool + RBAC/tenancy only -- no auth API, no admin API, no CloudFront/S3/SPA shell. Bring your own everything."
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "auth_api", "identity_only"], var.auth_profile)
    error_message = "auth_profile must be \"full\", \"auth_api\", or \"identity_only\"."
  }
}

# --- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to created resources."
  type        = map(string)
  default     = {}
}
