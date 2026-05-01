module "lambda" {
  source = "../lambda"

  app_name                    = var.app_name
  deployment_environment      = var.deployment_environment
  function_name               = var.function_name
  handler_name                = var.handler_name
  runtime                     = var.runtime
  timeout                     = var.timeout
  memory_size                 = var.memory_size
  environment                 = var.environment
  kms_key_arn                 = var.kms_key_arn
  kms_key_policy_json         = var.kms_key_policy_json
  source_bucket_arn           = var.source_bucket_arn
  source_bucket_id            = var.source_bucket_id
  source_object_key           = var.source_object_key
  tracing_mode                = var.tracing_mode
  create_url                  = var.create_url
  url_authorization_type      = var.url_authorization_type
  create_secret               = var.create_secret
  backend_user_name           = var.backend_user_name
  s3_required_access          = var.s3_required_access
  additional_role_policy_arns = var.additional_role_policy_arns

  # Lambda@Edge requirements — hardcoded, not caller-configurable.
  publish = true
  assume_role_services = [
    "lambda.amazonaws.com",
    "edgelambda.amazonaws.com",
  ]
}

resource "aws_iam_policy" "edge_replication" {
  name        = "${var.app_name}_${var.function_name}_${var.deployment_environment}_lambda_edge_replication_policy"
  description = "Allows CloudFront to replicate the ${var.function_name} Lambda@Edge function."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:EnableReplication*",
          "lambda:DisableReplication*",
        ]
        Resource = "${module.lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::*:role/aws-service-role/replicator.lambda.amazonaws.com/AWSServiceRoleForLambdaReplicator"
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = "replicator.lambda.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "edge_replication" {
  role       = module.lambda.role_name
  policy_arn = aws_iam_policy.edge_replication.arn
}
