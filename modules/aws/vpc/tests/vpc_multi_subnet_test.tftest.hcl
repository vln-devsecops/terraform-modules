mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

run "vpc_multi_subnet_explicit_azs" {
  command = plan

  variables {
    app_name               = "test"
    deployment_environment = "ci"
    vpc_cidr               = "192.168.0.0/16"
    public_subnet_cidrs    = ["192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24"]
    availability_zones     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "192.168.0.0/16"
    error_message = "Custom VPC CIDR not applied."
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 subnets for 3 CIDR inputs."
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone == "us-east-1a"
    error_message = "First subnet not assigned to first explicit AZ."
  }

  assert {
    condition     = aws_subnet.public[1].availability_zone == "us-east-1b"
    error_message = "Second subnet not assigned to second explicit AZ."
  }

  assert {
    condition     = aws_subnet.public[2].availability_zone == "us-east-1c"
    error_message = "Third subnet not assigned to third explicit AZ."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 3
    error_message = "public_subnet_ids output must have 3 entries."
  }

  assert {
    condition     = length(aws_route_table_association.public) == 3
    error_message = "Expected 3 route table associations."
  }
}

run "vpc_az_round_robin" {
  command = plan

  variables {
    app_name               = "test"
    deployment_environment = "ci"
    public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    availability_zones     = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 subnets."
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone == "us-east-1a"
    error_message = "First subnet should be in first AZ."
  }

  assert {
    condition     = aws_subnet.public[1].availability_zone == "us-east-1b"
    error_message = "Second subnet should be in second AZ."
  }

  assert {
    condition     = aws_subnet.public[2].availability_zone == "us-east-1a"
    error_message = "Third subnet should wrap back to first AZ (round-robin)."
  }
}
