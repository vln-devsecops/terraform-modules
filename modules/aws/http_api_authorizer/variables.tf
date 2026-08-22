variable "name" {
  description = "Name prefix for resources this module creates (Lambda function, IAM role/policy). An '-authorizer' suffix is appended."
  type        = string
}

variable "require_jwt" {
  description = "Whether the authorizer also verifies a bearer JWT in addition to the origin-verify header. When true, jwt_issuer_url and jwt_audience are required."
  type        = bool
  default     = false
}

variable "jwt_issuer_url" {
  description = "OIDC issuer base URL to verify tokens against (JWKS is fetched from <issuer>/.well-known/jwks.json). Required when require_jwt is true."
  type        = string
  default     = null
}

variable "jwt_audience" {
  description = "Expected JWT audience (aud claim). Required when require_jwt is true."
  type        = string
  default     = null
}

variable "jwt_forward_claims" {
  description = "Claim names to copy (as strings) from a verified JWT into the authorizer context, readable downstream via event.requestContext.authorizer.lambda. Only used when require_jwt is true."
  type        = list(string)
  default     = []
}

variable "timeout" {
  description = "Timeout in seconds for the authorizer Lambda."
  type        = number
  default     = 5
}

variable "kms_key_arn" {
  description = "KMS CMK ARN used to encrypt the Lambda's environment variables (including the generated origin-verify secret). Null uses Lambda's default AWS-managed encryption."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
