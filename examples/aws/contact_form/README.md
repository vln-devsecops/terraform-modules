# contact_form example

Provisions the `contact_form` module's DynamoDB table and both Lambda
functions (public `submit`, `AWS_IAM`-authorized `admin`), granting one
example IAM principal invoke access on the admin Function URL.

```sh
terraform init
terraform plan \
  -var admin_allowed_principal_arns='["arn:aws:iam::<account-id>:user/<you>"]' \
  -var submit_allowed_origins='["https://<your-site-domain>"]'
```

See `modules/aws/contact_form/README.md` for the post-apply reCAPTCHA secret
step.
