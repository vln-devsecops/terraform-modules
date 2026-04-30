# AWS Lambda doxchange compatibility fixture

This provider-backed fixture exercises the shared Lambda module using the main `doxchange` compatibility edges:

- implicit `app_name-function_name.zip` archive lookup
- Lambda Function URL creation
- generated Secrets Manager secret
- backend-user secret access attachment
- Lambda@Edge trust
- extra S3 permissions for frontend access

The fixture is self-contained: it creates the source bucket, frontend bucket,
deployment archive object, and backend IAM user it needs before invoking the
shared Lambda module.

Run `./run.sh` from this directory with AWS credentials if you want provider-backed
verification beyond `terraform test`.
