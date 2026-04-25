# terraform-modules

Reusable Terraform modules for shared infrastructure patterns.

The repository branch is `main`. Modules should be consumed via version tags rather than by floating branch references.

Documentation should normally use the moving two-level tag form such as `v0.1`; patch tags such as `v0.1.0` remain the immutable release points.

## Layout

- `modules/aws/*`: AWS-specific shared modules
- `examples/aws/*`: runnable example configurations for AWS modules
- `tests/aws/*`: reserved for higher-level integration suites

## Current modules

- `modules/aws/deployment_bucket`
