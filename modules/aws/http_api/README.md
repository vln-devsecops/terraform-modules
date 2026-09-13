# aws/http_api

Creates an AWS API Gateway HTTP API (v2) with Lambda proxy integrations, optional JWT authorizers, optional Lambda (REQUEST) authorizer, optional IAM (SigV4) authorization, optional CloudWatch access logging, and optional custom domain with Route 53 alias.

Routes are declared as a map; each route creates an integration, a route resource, and a Lambda permission. JWT authorizers are declared separately and referenced by key from individual routes; the Lambda authorizer (if any) is a single, API-wide object referenced via `authorization_type = "CUSTOM"`.

## Route authorization

Each route is authorized independently through the optional `authorization_type` field:

| `authorization_type` | Meaning |
| --- | --- |
| unset (default) | Derived from `authorizer_key`: `JWT` when an authorizer is referenced, `NONE` otherwise. |
| `NONE` | Public route. `authorizer_key` must not be set. |
| `AWS_IAM` | Caller must present SigV4-signed requests; access is granted by IAM policy on the `execute-api:Invoke` action. `authorizer_key` must not be set. |
| `JWT` | Validated by the referenced JWT authorizer; `authorizer_key` is required. |
| `CUSTOM` | Validated by the Lambda REQUEST authorizer configured via `lambda_authorizer` (which must be set). |

This lets a single API mix a public route with an owner-only IAM-signed route:

```hcl
routes = {
  submit = {
    route_key            = "POST /submit"
    lambda_function_arn  = aws_lambda_function.submit.arn
    lambda_function_name = aws_lambda_function.submit.function_name
  }
  admin = {
    route_key            = "GET /admin"
    lambda_function_arn  = aws_lambda_function.admin.arn
    lambda_function_name = aws_lambda_function.admin.function_name
    authorization_type   = "AWS_IAM"
  }
}
```

Note the value is `AWS_IAM`, matching the API Gateway v2 route attribute, not `IAM`.

### Lambda authorizer (`CUSTOM`)

`lambda_authorizer` wires a single Lambda REQUEST authorizer to the API; any route with `authorization_type = "CUSTOM"` invokes it (`enable_simple_responses = true`, payload format 2.0). Unlike `jwt_authorizers`, there's only ever one -- the authorizer Lambda itself decides what to check.

```hcl
lambda_authorizer = {
  authorizer_uri            = module.authorizer.authorizer_uri
  authorizer_function_name  = module.authorizer.authorizer_function_name
  identity_sources          = ["$request.header.X-Origin-Verify"]
}

routes = {
  guarded = {
    route_key            = "GET /guarded"
    lambda_function_arn  = aws_lambda_function.guarded.arn
    lambda_function_name = aws_lambda_function.guarded.function_name
    authorization_type   = "CUSTOM"
  }
}
```

`modules/aws/http_api_authorizer` provides a ready-made authorizer (a shared origin-verify header, optionally also JWT verification) whose outputs plug directly into `authorizer_uri`/`authorizer_function_name` above -- see that module's README. Any other Lambda REQUEST authorizer works too.

## Inputs

| Name | Description | Type |
| --- | --- | --- |
| `name` | Name of the HTTP API. | `string` |
| `description` | Description of the HTTP API. | `string` |
| `cors_configuration` | CORS configuration for the API. | `object(...)` |
| `routes` | Map of routes to create. Each key is a logical route identifier; see [Route authorization](#route-authorization). Each route may also optionally set `throttling_burst_limit` (token-bucket capacity, a request count) and `throttling_rate_limit` (steady-state limit in requests/second) to throttle that route. | `map(object(...))` |
| `jwt_authorizers` | Map of JWT authorizers. Key is referenced by routes via `authorizer_key`. | `map(object(...))` |
| `lambda_authorizer` | Single Lambda REQUEST authorizer; see [Lambda authorizer](#lambda-authorizer-custom). | `object(...)` |
| `stage_name` | API Gateway stage name. | `string` |
| `auto_deploy` | Whether to auto-deploy changes to the stage. | `bool` |
| `create_access_log_group` | Whether to create a CloudWatch log group for access logs. | `bool` |
| `access_log_format` | Access log format string. Only used when `create_access_log_group` is true. | `string` |
| `access_log_retention_days` | CloudWatch log retention days for access logs. | `number` |
| `custom_domain_name` | Custom domain name for the API. Set to null to skip custom domain resources. | `string` |
| `custom_domain_certificate_arn` | ACM certificate ARN for the custom domain. Required when `custom_domain_name` is set. | `string` |
| `route53_zone_id` | Route 53 zone ID for the custom domain alias record. Required when `custom_domain_name` is set. | `string` |
| `api_mapping_key` | API mapping key (path prefix) when `custom_domain_name` is set. Empty string maps to root. | `string` |
| `tags` | Tags to apply to created resources. | `map(string)` |

## Outputs

| Name | Description |
| --- | --- |
| `api_id` | API Gateway HTTP API ID. |
| `api_endpoint` | Default API endpoint (invoke URL without stage). |
| `execution_arn` | Execution ARN for use in Lambda permissions. |
| `stage_name` | Deployed stage name. |
| `invoke_url` | Full invocation URL including stage. |
| `custom_domain_name` | Custom domain name, if configured. |
| `domain_name_target` | Target domain name of the custom domain's API Gateway endpoint (for Route 53 alias). |
| `domain_name_hosted_zone_id` | Hosted zone ID of the custom domain's API Gateway endpoint (for Route 53 alias). |

## Example

```hcl
module "forms_api" {
  source = "git::https://github.com/vln-devsecops/terraform-modules.git//modules/aws/http_api?ref=v0.5"

  name = "books-forms"

  cors_configuration = {
    allow_origins = ["https://books.landheer-cieslak.com"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  jwt_authorizers = {
    coppice = {
      issuer_url = "https://auth.example.com"
      audience   = ["books.landheer-cieslak.com"]
    }
  }

  routes = {
    contact = {
      route_key            = "POST /contact"
      lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:contact"
      lambda_function_name = "contact"
    }
    newsletter = {
      route_key            = "POST /newsletter"
      lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:newsletter"
      lambda_function_name = "newsletter"
      authorizer_key       = "coppice"
    }
    admin = {
      route_key            = "GET /admin"
      lambda_function_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:admin"
      lambda_function_name = "admin"
      authorization_type   = "AWS_IAM"
    }
  }

  custom_domain_name            = "api.example.com"
  custom_domain_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/example"
  route53_zone_id               = "Z2RPCDW04V8134"

  tags = {
    project    = "books"
    managed_by = "terraform"
  }
}
```

The repository branch should remain `main`, while module consumers should normally prefer the moving two-level tag form such as `v0.5`. That moving tag should only advance after the relevant pipelines have passed on the target commit.
