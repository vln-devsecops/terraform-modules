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
  description = "Route53 hosted zone ID that will serve the hosted-UI and admin-panel hostnames this module derives."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 covering both derived hostnames (\"$${domain_prefix}-<zone>\" and, when create_admin_panel is true, \"$${admin_panel_domain_prefix}-<zone>\"). A wildcard cert from aws/acm_certificate is the simplest way to cover both."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:", var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be an ACM certificate in us-east-1 (required for both the Cognito hosted-UI custom domain and the CloudFront-backed admin panel)."
  }
}

# --- Branding (optional; ships a Vlinder default) --------------------------

variable "logo_base64" {
  description = "Base64-encoded logo image for the hosted-UI sign-in page. Defaults to the module's built-in Vlinder logo when null."
  type        = string
  default     = null
}

variable "css" {
  description = "CSS override for the hosted-UI sign-in page. Defaults to the module's built-in Vlinder theme when null."
  type        = string
  default     = null
}

# --- Identity (optional; sane defaults) ------------------------------------

variable "domain_prefix" {
  description = "Prefix used to derive the Cognito hosted-UI custom domain: \"$${domain_prefix}-<zone-name>\"."
  type        = string
  default     = "auth"
}

variable "allow_self_signup" {
  description = "Whether users can sign themselves up via the hosted UI. When false, only admin-created users can sign in (pool-wide setting -- Cognito has no per-client signup toggle)."
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
  description = "Optional SES identity to send verification/invite emails through (branded from-address, better deliverability). When null, Cognito sends via its own built-in email service (COGNITO_DEFAULT) -- zero configuration, works immediately, lower send limits and an Amazon-owned from-address."
  type = object({
    configuration_set_name = string
    source_arn             = string
    from_email_address     = string
  })
  default = null
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

# --- Admin panel (optional; on by default) ---------------------------------

variable "create_admin_panel" {
  description = "Whether to provision the bundled admin panel (hosting, its own Cognito client, and the admin API behind it). Set false to use only identity + RBAC."
  type        = bool
  default     = true
}

variable "admin_panel_domain_prefix" {
  description = "Prefix used to derive the admin panel's hostname: \"$${admin_panel_domain_prefix}-<zone-name>\". Only used when create_admin_panel is true."
  type        = string
  default     = "admin"
}

# --- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to created resources."
  type        = map(string)
  default     = {}
}
