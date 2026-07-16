# AWS Lambda Function URL CORS round-trip

Provider-backed fixture for the `aws/lambda` module's `cors` variable. Unlike
`modules/aws/lambda/tests/basic.tftest.hcl` (which only asserts on the
Terraform-planned shape of the `cors` block), this fixture applies a real,
publicly invokable Function URL with `cors` set and then makes real HTTP
requests against it, asserting on the actual `Access-Control-*` response
headers AWS returns:

- an `OPTIONS` preflight request, asserting AWS answers it directly (this is
  the behavior the `cors` variable exists to get, in place of hand-coding
  `OPTIONS`/CORS handling in the function itself)
- a real `GET` invocation, asserting the same CORS headers are present on an
  actual response, not just on preflight

The fixture relies on the module's built-in echo-Lambda fallback (no archive
is ever uploaded to the source bucket) - it only needs a real invokable
Function URL, not any particular handler behavior.

Run `./run.sh` from this directory with AWS credentials if you want
provider-backed verification beyond `terraform test`.
