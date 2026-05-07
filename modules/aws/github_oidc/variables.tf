variable "create_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC identity provider in this account. Set to false if the provider already exists and the module should only create roles against it."
  type        = bool
  default     = true
}

variable "github_thumbprints" {
  description = "Server certificate thumbprints for the GitHub OIDC provider endpoint. Defaults cover the current GitHub certificate chain (Starfield + DigiCert roots). AWS now validates GitHub tokens using the full certificate chain, so these values are not used for cryptographic verification, but the API still requires at least one entry."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "additional_audiences" {
  description = "Additional audiences (client IDs) to register on the OIDC provider beyond the default sts.amazonaws.com. Only relevant when create_oidc_provider is true."
  type        = list(string)
  default     = []
}

variable "roles" {
  description = "Map of IAM roles to create. Each key is a stable identifier used in outputs and resource addressing; role_name is the actual IAM role name in AWS."
  type = map(object({
    role_name            = string
    description          = optional(string, "")
    subject_claims       = list(string)
    policy_arns          = optional(list(string), [])
    inline_policies      = optional(map(string), {})
    max_session_duration = optional(number, 3600)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all created resources."
  type        = map(string)
  default     = {}
}
