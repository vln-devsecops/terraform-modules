# Provider-backed DynamoDB suite

This suite exercises `modules/aws/dynamodb` against real AWS APIs.

- fixture: `main.tf`
- entrypoint: `run.sh`
- prerequisites: working AWS credentials in the environment

The suite creates a uniquely named table, verifies the table name and KMS key
outputs, and then destroys the fixture resources.
