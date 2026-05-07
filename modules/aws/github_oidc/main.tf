locals {
  oidc_issuer_url  = "https://token.actions.githubusercontent.com"
  oidc_issuer_host = "token.actions.githubusercontent.com"
  audiences        = concat(["sts.amazonaws.com"], var.additional_audiences)

  # When create_oidc_provider is false, derive the ARN from the caller's
  # account ID — the OIDC provider ARN format is deterministic and global.
  oidc_provider_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_issuer_host}"
  )

  # Flatten inline policies across all roles into a stable map keyed by
  # "{role_key}:{policy_name}" for use with for_each.
  flat_inline_policies = merge([
    for role_key, role in var.roles : {
      for policy_name, policy_doc in role.inline_policies :
      "${role_key}:${policy_name}" => {
        role_key    = role_key
        policy_name = policy_name
        policy_doc  = policy_doc
      }
    }
  ]...)

  # Flatten managed policy ARNs across all roles into a stable map.
  # The ARN is included in the key so additions/removals do not shift indices.
  flat_policy_arns = merge([
    for role_key, role in var.roles : {
      for arn in role.policy_arns :
      "${role_key}:${arn}" => {
        role_key   = role_key
        policy_arn = arn
      }
    }
  ]...)
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.oidc_issuer_url
  client_id_list  = local.audiences
  thumbprint_list = var.github_thumbprints

  tags = var.tags
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name                 = each.value.role_name
  description          = each.value.description
  max_session_duration = each.value.max_session_duration

  # Subject claims may include wildcards (e.g. "repo:org/repo:*"), so
  # StringLike is used rather than StringEquals. Audience is pinned exactly.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.oidc_issuer_host}:sub" = each.value.subject_claims
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.flat_inline_policies

  name   = each.value.policy_name
  role   = aws_iam_role.this[each.value.role_key].name
  policy = each.value.policy_doc
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = local.flat_policy_arns

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
