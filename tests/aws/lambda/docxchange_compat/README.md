# AWS Lambda docxchange compatibility fixture

This provider-backed fixture exercises the shared Lambda module using the main `docxchange` compatibility edges:

- implicit `app_name-function_name.zip` archive lookup
- Lambda Function URL creation
- generated Secrets Manager secret
- backend-user secret access attachment
- Lambda@Edge trust
- extra S3 permissions for frontend access

Run from this directory with AWS credentials and a real deployment archive already present in the source bucket if you want provider-backed verification beyond `terraform test`.
