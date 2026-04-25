# terraform-modules

Reusable Terraform modules for shared infrastructure patterns.

The repository branch is `main`. Modules should be consumed via version tags rather than by floating branch references.

## Layout

- `modules/aws/*`: AWS-specific shared modules
- `examples/aws/*`: runnable example configurations for AWS modules
- `tests/aws/*`: reserved for higher-level integration suites

## Current modules

- `modules/aws/deployment_bucket`
