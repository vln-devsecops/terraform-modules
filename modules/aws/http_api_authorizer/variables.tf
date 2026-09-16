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

# Left null (the default), the aws_iam_policy.kms/aws_iam_role_policy_attachment.kms
# count below infers "create the grant" from kms_key_arn's nullness -- the
# original, pre-this-variable behavior, which is correct for any caller
# whose kms_key_arn is a statically-known value (the common case).
#
# That inference breaks, though, when count/for_each has to evaluate it: it
# requires kms_key_arn's nullness to be knowable at plan time, but a
# caller-supplied kms_key_arn is sometimes itself a same-apply-computed
# value -- e.g. vlinder_auth's two callers of this module pass
# aws_kms_key.this.arn, a CMK created in the same module instance in the
# same apply, which is "(known after apply)" on a from-scratch deployment.
# Terraform can't evaluate `!= null` against that, so count itself becomes
# unknown and Terraform hard-errors with "Invalid count argument ...
# depends on resource attributes that cannot be determined until apply".
#
# Explicitly setting create_kms_policy to true or false sidesteps this: a
# literal true/false is knowable at plan time regardless of whether
# kms_key_arn itself is, so a caller in vlinder_auth's position (unknown
# kms_key_arn, but the caller knows statically it wants the grant) can opt
# in with create_kms_policy = true. A caller who leaves it null AND passes
# an unknown kms_key_arn still hits the original error -- not a regression,
# just the pre-existing bug for anyone who doesn't opt in.
variable "create_kms_policy" {
  description = "Whether to create the IAM policy/attachment granting this Lambda's role kms:Decrypt on kms_key_arn. Null (default) infers this from kms_key_arn's nullness; set explicitly when kms_key_arn is itself unknown at plan time (see comment above)."
  type        = bool
  default     = null

  validation {
    condition     = var.create_kms_policy != true || var.kms_key_arn != null
    error_message = "create_kms_policy requires a non-null kms_key_arn."
  }
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
