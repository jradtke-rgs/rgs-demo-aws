terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "rgs-demo"
      Component   = "security"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# This module provisions the bare AWS node for the "user-apps" downstream
# RKE2 cluster used to demo RGS Security. It does NOT install RKE2 or the
# product itself - the node is imported into Rancher as a custom cluster
# manually, then RGS Security is Helm-installed once the cluster is Active.
# See README.md for the manual steps.

data "terraform_remote_state" "shared" {
  backend = "local"

  config = {
    path = "${path.module}/../shared-services/terraform.tfstate"
  }
}

# Verified against real AWS account 013907871322 (2026-08-04)
data "aws_ami" "sl_micro" {
  most_recent = true
  owners      = ["013907871322"]

  filter {
    name   = "name"
    values = ["suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_route53_zone" "main" {
  count        = var.create_route53_record && var.route53_zone_id == "" && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  name         = "${var.subdomain}.${var.root_domain}"
  private_zone = false
}

locals {
  userapps_fqdn = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "${var.hostname_userapps}.${var.subdomain}.${var.root_domain}" : "user-apps.${var.environment}.local"
  raw_zone_id   = var.route53_zone_id != "" ? var.route53_zone_id : (var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? data.aws_route53_zone.main[0].zone_id : "")
  zone_id       = trimprefix(local.raw_zone_id, "/hostedzone/")
}

resource "aws_security_group" "security" {
  name_prefix = "${var.environment}-security-"
  description = "Security group for the user-apps downstream node (RGS Security demo)"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id

  ingress {
    description = "Kubernetes API (for Rancher agent registration)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS (user-apps ingress, once workloads are deployed)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-security-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "security" {
  name_prefix = "${var.environment}-security-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-security-role"
  }
}

resource "aws_iam_instance_profile" "security" {
  name_prefix = "${var.environment}-security-"
  role        = aws_iam_role.security.name
}

resource "aws_iam_role_policy_attachment" "security_ssm" {
  role       = aws_iam_role.security.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_key_pair" "security" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.environment}-security-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.environment}-security-key"
  }
}

resource "aws_instance" "security" {
  ami                  = var.ami_id != "" ? var.ami_id : data.aws_ami.sl_micro.id
  instance_type        = var.security_instance_type
  subnet_id            = data.terraform_remote_state.shared.outputs.public_subnet_ids[0]
  key_name             = var.ssh_public_key != "" ? aws_key_pair.security[0].key_name : null
  iam_instance_profile = aws_iam_instance_profile.security.name
  vpc_security_group_ids = [
    aws_security_group.security.id,
    data.terraform_remote_state.shared.outputs.ssh_security_group_id,
    data.terraform_remote_state.shared.outputs.internal_security_group_id
  ]

  root_block_device {
    volume_size           = var.security_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    rgs_carbide_registry = var.rgs_carbide_registry
    rgs_carbide_username = var.rgs_carbide_username
    rgs_carbide_password = var.rgs_carbide_password
  })

  tags = {
    Name = "${var.environment}-user-apps-node"
  }
}

resource "aws_eip" "security" {
  count    = var.create_eip ? 1 : 0
  instance = aws_instance.security.id
  domain   = "vpc"

  tags = {
    Name = "${var.environment}-security-eip"
  }
}

resource "aws_route53_record" "security" {
  count   = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  zone_id = local.zone_id
  name    = "${var.hostname_userapps}.${var.subdomain}.${var.root_domain}"
  type    = "A"
  ttl     = 300
  records = [var.create_eip ? aws_eip.security[0].public_ip : aws_instance.security.public_ip]
}
