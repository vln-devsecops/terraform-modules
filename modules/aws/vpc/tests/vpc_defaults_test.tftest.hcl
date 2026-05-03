mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

run "vpc_defaults_match_contract" {
  command = plan

  variables {
    app_name               = "test"
    deployment_environment = "ci"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "Default VPC CIDR changed unexpectedly."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true && aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS defaults changed unexpectedly."
  }

  assert {
    condition     = length(aws_subnet.public) == 1
    error_message = "Expected exactly one subnet with default inputs."
  }

  assert {
    condition     = aws_subnet.public[0].cidr_block == "10.0.1.0/24"
    error_message = "Default public subnet CIDR changed unexpectedly."
  }

  assert {
    condition     = aws_subnet.public[0].map_public_ip_on_launch == true
    error_message = "Public subnets must auto-assign public IPs."
  }

  assert {
    condition     = output.vpc_cidr == "10.0.0.0/16"
    error_message = "vpc_cidr output changed unexpectedly."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 1
    error_message = "public_subnet_ids output length changed unexpectedly."
  }
}

run "vpc_tags_applied" {
  command = plan

  variables {
    app_name               = "myapp"
    deployment_environment = "staging"
    tags = {
      owner = "team-platform"
    }
  }

  assert {
    condition     = aws_vpc.this.tags["app"] == "myapp"
    error_message = "app tag not set correctly on VPC."
  }

  assert {
    condition     = aws_vpc.this.tags["environment"] == "staging"
    error_message = "environment tag not set correctly on VPC."
  }

  assert {
    condition     = aws_vpc.this.tags["owner"] == "team-platform"
    error_message = "Additional tags not merged onto VPC."
  }
}
