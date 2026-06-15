locals {
  kms_key_arn         = coalesce(var.kms_key_arn, aws_kms_key.this[0].arn)
  kms_key_policy_json = var.kms_key_policy_json != null ? var.kms_key_policy_json : data.aws_iam_policy_document.kms.json
  common_tags = {
    app         = var.app_name
    environment = var.deployment_environment
    rg          = "security"
    function    = var.function
  }
}

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
  count = var.kms_key_arn == null ? 1 : 0

  description             = "CMK for ddb-${var.app_name}-${var.deployment_environment}-${var.function}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = local.kms_key_policy_json
  tags                    = local.common_tags
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/ddb-${var.app_name}-${var.deployment_environment}-${var.function}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_dynamodb_table" "this" {
  name         = "ddb-${var.app_name}-${var.deployment_environment}-${var.short_deployment_region}-${var.function}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  range_key    = var.range_key

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indices
    content {
      name               = global_secondary_index.value.name
      projection_type    = global_secondary_index.value.projection_type
      hash_key           = global_secondary_index.value.hash_key
      range_key          = global_secondary_index.value.range_key
      write_capacity     = global_secondary_index.value.write_capacity
      read_capacity      = global_secondary_index.value.read_capacity
      non_key_attributes = global_secondary_index.value.non_key_attributes
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indices
    content {
      name               = local_secondary_index.value.name
      projection_type    = local_secondary_index.value.projection_type
      range_key          = local_secondary_index.value.range_key
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  dynamic "attribute" {
    for_each = {
      for attr in var.attributes : attr.name => attr
      if(
        contains([for lsi in var.local_secondary_indices : lsi.range_key], attr.name) ||
        contains([for gsi in var.global_secondary_indices : gsi.hash_key], attr.name) ||
        contains([for gsi in var.global_secondary_indices : gsi.range_key], attr.name) ||
        attr.name == var.hash_key ||
        attr.name == var.range_key
      )
    }
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  tags = {
    app         = var.app_name
    environment = var.deployment_environment
    rg          = "data"
    function    = var.function
  }
}

resource "aws_iam_policy" "this_rw" {
  name        = "iampolicy-ddb-${var.app_name}-${var.deployment_environment}-${var.function}-rw"
  description = "IAM policy for read-write access to the ddb-${var.app_name}-${var.deployment_environment}-${var.function} DynamoDB table"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.this.arn,
          "${aws_dynamodb_table.this.arn}/index/*",
          "${aws_dynamodb_table.this.arn}/stream/*",
        ]
      },
    ]
  })

  tags = {
    app         = var.app_name
    environment = var.deployment_environment
    rg          = "security"
    function    = var.function
  }
}

resource "aws_iam_user_policy_attachment" "this_rw" {
  count      = var.rw_user_name != null ? 1 : 0
  user       = var.rw_user_name
  policy_arn = aws_iam_policy.this_rw.arn
}

resource "aws_iam_policy" "this_ro" {
  count       = var.ro_user_name != null ? 1 : 0
  name        = "iampolicy-ddb-${var.app_name}-${var.deployment_environment}-${var.function}-ro"
  description = "IAM policy for read-only access to the ddb-${var.app_name}-${var.deployment_environment}-${var.function} DynamoDB table"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:ListTables",
          "dynamodb:Query",
          "dynamodb:Scan",
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.this.arn,
          "${aws_dynamodb_table.this.arn}/index/*",
          "${aws_dynamodb_table.this.arn}/stream/*",
        ]
      },
    ]
  })

  tags = {
    app         = var.app_name
    environment = var.deployment_environment
    rg          = "security"
    function    = var.function
  }
}

resource "aws_iam_user_policy_attachment" "this_ro" {
  count      = var.ro_user_name != null ? 1 : 0
  user       = var.ro_user_name
  policy_arn = aws_iam_policy.this_ro[0].arn
}
