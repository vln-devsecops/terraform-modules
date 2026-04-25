run "mail_contract_uses_expected_defaults" {
  command = plan

  variables {
    deployment_environment = "dev"
    deployment_region      = "ca-central-1"
    domain_name            = "auth.example.com"
    domain_prefix          = "auth"
    route53_zone_id        = "Z1234567890"
  }

  assert {
    condition     = output.configuration_set_name == "ascs-auth_example_com-dev"
    error_message = "Configuration set naming contract changed unexpectedly."
  }

  assert {
    condition     = contains(tolist(aws_route53_record.mx_record.records), "1 inbound-smtp.ca-central-1.amazonaws.com")
    error_message = "Inbound MX region should default to deployment_region."
  }

  assert {
    condition     = contains(tolist(aws_route53_record.bounce_mx_record.records), "10 feedback-smtp.ca-central-1.amazonses.com")
    error_message = "Feedback MX region should default to deployment_region."
  }

  assert {
    condition     = contains(tolist(aws_route53_record.dmarc_record.records), "v=DMARC1; p=reject; rua=mailto:dmarc-reports@auth.example.com; aspf=r; adkim=r")
    error_message = "Default DMARC record changed unexpectedly."
  }
}

run "mail_contract_honors_region_and_dmarc_overrides" {
  command = plan

  variables {
    deployment_environment = "prod"
    deployment_region      = "eu-west-1"
    domain_name            = "notify.example.com"
    domain_prefix          = "notify"
    route53_zone_id        = "Z1234567890"
    ses_inbound_region     = "us-east-2"
    ses_feedback_region    = "us-east-1"
    dmarc_policy           = "quarantine"
    dmarc_report_uri       = "mailto:postmaster@example.com"
  }

  assert {
    condition     = contains(tolist(aws_route53_record.mx_record.records), "1 inbound-smtp.us-east-2.amazonaws.com")
    error_message = "Inbound MX override changed unexpectedly."
  }

  assert {
    condition     = contains(tolist(aws_route53_record.bounce_mx_record.records), "10 feedback-smtp.us-east-1.amazonses.com")
    error_message = "Feedback MX override changed unexpectedly."
  }

  assert {
    condition     = contains(tolist(aws_route53_record.dmarc_record.records), "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com; aspf=r; adkim=r")
    error_message = "DMARC override changed unexpectedly."
  }
}
