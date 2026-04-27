mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/dynamodb"
      key_id = "dynamodb"
    }
  }
}

run "table_name_and_tags_match_contract" {
  command = plan

  variables {
    app_name                = "sampleapp"
    deployment_environment  = "dev"
    short_deployment_region = "useast1"
    function                = "events"
    hash_key                = "pk"
    range_key               = "sk"
    kms_key_policy_json     = jsonencode({ Version = "2012-10-17", Statement = [] })
    attributes = [
      {
        name = "pk"
        type = "S"
      },
      {
        name = "sk"
        type = "S"
      },
    ]
    global_secondary_indices = []
    local_secondary_indices  = []
  }

  assert {
    condition     = output.table_name == "ddb-sampleapp-dev-useast1-events"
    error_message = "Table naming contract changed unexpectedly."
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "Billing mode changed unexpectedly."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags.app == "sampleapp" && aws_dynamodb_table.this.tags.environment == "dev" && aws_dynamodb_table.this.tags.function == "events"
    error_message = "Table tags changed unexpectedly."
  }

  assert {
    condition = alltrue([
      for pitr in aws_dynamodb_table.this.point_in_time_recovery :
      pitr.enabled
    ])
    error_message = "Point-in-time recovery should stay enabled by default."
  }

  assert {
    condition = alltrue([
      for sse in aws_dynamodb_table.this.server_side_encryption :
      sse.enabled
    ]) && aws_kms_key.this[0].enable_key_rotation == true && output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/dynamodb"
    error_message = "DynamoDB encryption defaults changed unexpectedly."
  }
}

run "optional_iam_user_attachments_are_created" {
  command = plan

  variables {
    app_name                = "sampleapp"
    deployment_environment  = "dev"
    short_deployment_region = "useast1"
    function                = "events"
    hash_key                = "pk"
    range_key               = "sk"
    kms_key_policy_json     = jsonencode({ Version = "2012-10-17", Statement = [] })
    rw_user_name            = "sample-rw"
    ro_user_name            = "sample-ro"
    attributes = [
      {
        name = "pk"
        type = "S"
      },
      {
        name = "sk"
        type = "S"
      },
    ]
    global_secondary_indices = []
    local_secondary_indices  = []
  }

  assert {
    condition     = aws_iam_user_policy_attachment.this_rw[0].user == "sample-rw"
    error_message = "Read-write IAM user attachment was not created as expected."
  }

  assert {
    condition     = aws_iam_user_policy_attachment.this_ro[0].user == "sample-ro"
    error_message = "Read-only IAM user attachment was not created as expected."
  }

  assert {
    condition     = aws_iam_policy.this_ro[0].name == "iampolicy-ddb-sampleapp-dev-events-ro"
    error_message = "Read-only IAM policy naming changed unexpectedly."
  }
}
