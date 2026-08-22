# http_api_authorizer example

Provisions a `http_api_authorizer` (origin-verify header + JWT verification) and wires it as the `lambda_authorizer` on an `http_api` HTTP API, guarding one `CUSTOM`-authorized route.

```sh
terraform init
terraform plan \
  -var jwt_issuer_url=https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_example \
  -var jwt_audience=<cognito-app-client-id> \
  -var list_users_lambda_arn=arn:aws:lambda:eu-west-1:123456789012:function:list-users \
  -var list_users_lambda_name=list-users
```

After apply, pair this with a CDN (e.g. CloudFront) whose origin points at `api_endpoint` and whose origin config sets a custom header named `X-Origin-Verify` to `origin_verify_secret` -- see `modules/aws/http_api_authorizer/README.md` for the full CloudFront wiring example.
