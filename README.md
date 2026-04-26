# terraform-modules

Reusable Terraform modules for shared infrastructure patterns.

The repository branch is `main`. Modules should be consumed via version tags rather than by floating branch references.

Documentation should normally use the moving two-level tag form such as `v0.3`; patch tags such as `v0.3.0` remain the immutable release points.

## Layout

- `modules/aws/*`: AWS-specific shared modules
- `examples/aws/*`: runnable example configurations for AWS modules
- `tests/aws/*`: reserved for higher-level integration suites

## Current modules

- `modules/aws/deployment_bucket`
- `modules/aws/dynamodb`
- `modules/aws/mail`
- `modules/aws/lambda`

## Testing approach

Shared modules use a layered test model:

1. static checks on every change with `terraform fmt -check` and `terraform validate`
2. module contract tests with `terraform test`
3. executable examples under `examples/`
4. higher-level cloud integration coverage under `tests/`, added separately when the module is ready for real provider-backed verification

At the moment, `deployment_bucket` and `dynamodb` have static checks, contract tests, and executable examples in place. Their higher-level AWS integration coverage is still deferred.

`lambda` now adds both mock-provider contract coverage and a provider-backed compatibility fixture under `tests/aws/lambda/docxchange_compat` so the closest-to-production `docxchange` usage shape stays protected while the shared module evolves.
