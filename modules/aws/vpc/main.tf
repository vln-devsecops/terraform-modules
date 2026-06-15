locals {
  common_tags = merge(var.tags, {
    app         = var.app_name
    environment = var.deployment_environment
  })

  # Use explicitly provided AZs; fall back to the data source when none given.
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available[0].names
}

data "aws_availability_zones" "available" {
  # Only queried when availability_zones is empty; avoids a real API call in
  # contract tests that mock the provider and pass explicit AZ names.
  count = length(var.availability_zones) == 0 ? 1 : 0
  state = "available"
}

# trivy:ignore:AVD-AWS-0178
resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11:VPC flow logs caller-configurable, not wired at module level
  # checkov:skip=CKV2_AWS_12:Public subnets for runner workloads are intentional per design
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-${var.deployment_environment}-vpc"
    rg   = "networking"
  })
}

# trivy:ignore:AVD-AWS-0164
resource "aws_subnet" "public" {
  # checkov:skip=CKV_AWS_130:Public subnets intentionally auto-assign public IPs for runner and public-access workloads
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index % length(local.availability_zones)]

  # Public subnets intentionally auto-assign public IPs so that instances
  # (e.g. self-hosted runners) can reach the internet without a NAT gateway.
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-${var.deployment_environment}-public-${count.index}"
    rg   = "networking"
    tier = "public"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-${var.deployment_environment}-igw"
    rg   = "networking"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.app_name}-${var.deployment_environment}-public-rt"
    rg   = "networking"
    tier = "public"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
