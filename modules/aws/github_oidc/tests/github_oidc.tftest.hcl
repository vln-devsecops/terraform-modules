mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/mock-role"
      name = "mock-role"
    }
  }

  mock_resource "aws_iam_role_policy" {
    defaults = {}
  }

  mock_resource "aws_iam_role_policy_attachment" {
    defaults = {}
  }
}

# ---------------------------------------------------------------------------
# Run 1 — provider and single-role defaults
# ---------------------------------------------------------------------------

run "provider_and_role_defaults_match_contract" {
  command = plan

  variables {
    roles = {
      infra_apply = {
        role_name      = "my-org-infra-apply"
        description    = "Applied by GitHub Actions on push to main"
        subject_claims = ["repo:my-org/infra:environment:production"]
      }
    }
  }

  # Provider is created by default.
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "OIDC provider should be created when create_oidc_provider is true (default)."
  }

  # Provider uses the correct GitHub issuer URL.
  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "OIDC provider URL changed unexpectedly."
  }

  # sts.amazonaws.com is always in the client_id_list.
  assert {
    condition     = contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com")
    error_message = "sts.amazonaws.com must be in the OIDC provider audience list."
  }

  # Both default thumbprints are present.
  assert {
    condition = (
      contains(aws_iam_openid_connect_provider.github[0].thumbprint_list, "6938fd4d98bab03faadb97b34396831e3780aea1") &&
      contains(aws_iam_openid_connect_provider.github[0].thumbprint_list, "1c58a3a8518e8759bf075b76b750d4f2df264fcd")
    )
    error_message = "Default GitHub OIDC thumbprints changed unexpectedly."
  }

  # Trust policy contains the specified subject claim.
  assert {
    condition     = strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "repo:my-org/infra:environment:production")
    error_message = "Role trust policy must contain the specified subject claim."
  }

  # Trust policy audience is pinned to sts.amazonaws.com via StringEquals.
  assert {
    condition = (
      strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "sts.amazonaws.com") &&
      strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "StringEquals")
    )
    error_message = "Role trust policy must pin audience to sts.amazonaws.com with StringEquals."
  }

  # Subject claims use StringLike to support wildcard patterns.
  assert {
    condition     = strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "StringLike")
    error_message = "Role trust policy must use StringLike for subject claims to support wildcard repo patterns."
  }

  # Session duration defaults to one hour.
  assert {
    condition     = aws_iam_role.this["infra_apply"].max_session_duration == 3600
    error_message = "Default max_session_duration must be 3600 seconds (one hour)."
  }

  # role_arns output contains an entry for every defined role.
  assert {
    condition     = length(output.role_arns) == 1 && contains(keys(output.role_arns), "infra_apply")
    error_message = "role_arns output must contain an entry for every role key in var.roles."
  }

  # oidc_provider_arn output is populated.
  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "oidc_provider_arn output must reflect the created provider ARN."
  }
}

# ---------------------------------------------------------------------------
# Run 2 — skipping provider creation derives ARN from account identity
# ---------------------------------------------------------------------------

run "provider_skip_derives_arn_from_caller_account_identity" {
  command = plan

  variables {
    create_oidc_provider = false
    roles = {
      ops_deploy = {
        role_name      = "my-org-ops-deploy"
        subject_claims = ["repo:my-org/operations:environment:vln-devsecops"]
      }
    }
  }

  # No provider resource is planned when the flag is false.
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "OIDC provider must not be created when create_oidc_provider is false."
  }

  # The derived ARN uses the caller account ID and the fixed issuer host.
  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "oidc_provider_arn must be derived from caller account ID when create_oidc_provider is false."
  }

  # Roles are still created against the derived provider ARN.
  assert {
    condition     = strcontains(aws_iam_role.this["ops_deploy"].assume_role_policy, "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com")
    error_message = "Role trust policy must reference the derived OIDC provider ARN when create_oidc_provider is false."
  }
}

# ---------------------------------------------------------------------------
# Run 3 — multiple roles, inline policies, managed attachments
# ---------------------------------------------------------------------------

run "multiple_roles_with_inline_and_managed_policies_apply_correctly" {
  command = plan

  variables {
    roles = {
      infra_plan = {
        role_name      = "my-org-infra-plan"
        subject_claims = ["repo:my-org/infra:pull_request"]
        policy_arns    = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
        inline_policies = {
          state_read = jsonencode({
            Version = "2012-10-17"
            Statement = [{
              Effect   = "Allow"
              Action   = ["s3:GetObject", "s3:ListBucket"]
              Resource = ["arn:aws:s3:::my-state-bucket", "arn:aws:s3:::my-state-bucket/*"]
            }]
          })
        }
      }
      infra_apply = {
        role_name      = "my-org-infra-apply"
        subject_claims = ["repo:my-org/infra:environment:production", "repo:my-org/infra:ref:refs/heads/main"]
        inline_policies = {
          state_write = jsonencode({
            Version = "2012-10-17"
            Statement = [{
              Effect   = "Allow"
              Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
              Resource = ["arn:aws:s3:::my-state-bucket", "arn:aws:s3:::my-state-bucket/*"]
            }]
          })
        }
        max_session_duration = 7200
      }
    }
  }

  # role_arns output has an entry for every role.
  assert {
    condition = (
      length(output.role_arns) == 2 &&
      contains(keys(output.role_arns), "infra_plan") &&
      contains(keys(output.role_arns), "infra_apply")
    )
    error_message = "role_arns must contain an entry for every role in var.roles."
  }

  # Multiple subject claims are all present in the trust policy.
  assert {
    condition = (
      strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "repo:my-org/infra:environment:production") &&
      strcontains(aws_iam_role.this["infra_apply"].assume_role_policy, "repo:my-org/infra:ref:refs/heads/main")
    )
    error_message = "All subject claims must be present in the role trust policy."
  }

  # Inline policy is created with the correct name and wired to the right role.
  assert {
    condition     = aws_iam_role_policy.inline["infra_plan:state_read"].name == "state_read"
    error_message = "Inline policy name must match the map key from inline_policies."
  }

  assert {
    condition     = aws_iam_role_policy.inline["infra_plan:state_read"].role == aws_iam_role.this["infra_plan"].name
    error_message = "Inline policy must be attached to the correct IAM role."
  }

  assert {
    condition     = aws_iam_role_policy.inline["infra_apply:state_write"].role == aws_iam_role.this["infra_apply"].name
    error_message = "Inline policy must be attached to the role that owns it, not a sibling role."
  }

  # Managed policy attachment uses the supplied ARN and targets the right role.
  assert {
    condition     = aws_iam_role_policy_attachment.managed["infra_plan:arn:aws:iam::aws:policy/ReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "Managed policy attachment must use the supplied policy ARN."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.managed["infra_plan:arn:aws:iam::aws:policy/ReadOnlyAccess"].role == aws_iam_role.this["infra_plan"].name
    error_message = "Managed policy attachment must target the role that declared the ARN."
  }

  # No managed attachment is created for a role that did not declare any ARNs.
  assert {
    condition     = length([for k in keys(aws_iam_role_policy_attachment.managed) : k if startswith(k, "infra_apply:")]) == 0
    error_message = "No managed policy attachments should be created for a role with an empty policy_arns list."
  }

  # Overriding max_session_duration is respected.
  assert {
    condition     = aws_iam_role.this["infra_apply"].max_session_duration == 7200
    error_message = "max_session_duration must be overridable per role."
  }
}

# ---------------------------------------------------------------------------
# Run 4 — edge cases: no roles and tag propagation
# ---------------------------------------------------------------------------

run "no_roles_produces_empty_output_and_tags_are_propagated" {
  command = plan

  variables {
    tags = {
      org     = "my-org"
      managed = "terraform"
    }
  }

  # No roles → no role resources and empty output map.
  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "No IAM roles should be created when var.roles is empty."
  }

  assert {
    condition     = length(output.role_arns) == 0
    error_message = "role_arns output must be empty when no roles are defined."
  }

  # Provider still created; tags are applied.
  assert {
    condition = (
      aws_iam_openid_connect_provider.github[0].tags["org"] == "my-org" &&
      aws_iam_openid_connect_provider.github[0].tags["managed"] == "terraform"
    )
    error_message = "Tags must be applied to the OIDC provider."
  }
}
