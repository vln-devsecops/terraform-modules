# Provider-backed deployment bucket suite

This suite exercises `modules/aws/deployment_bucket` against real AWS APIs.

- fixture: `main.tf`
- entrypoint: `run.sh`
- prerequisites: working AWS credentials in the environment

The suite creates a uniquely named bucket, verifies the bucket name and KMS key
outputs, and then destroys the fixture resources.
