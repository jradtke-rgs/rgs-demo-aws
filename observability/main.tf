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
      Component   = "observability"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# This module provisions the bare AWS node for RGS Observability's own
# downstream RKE2 cluster. It does NOT install RKE2 or the product itself -
# per this session's decision, the node is imported into Rancher as a custom
# cluster manually (Rancher's registration command installs RKE2 for you),
# then RGS Observability is Helm-installed once the cluster is Active. See
# README.md for the manual steps.

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
  observability_fqdn = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? "${var.hostname_observability}.${var.subdomain}.${var.root_domain}" : "observability.${var.environment}.local"
  raw_zone_id        = var.route53_zone_id != "" ? var.route53_zone_id : (var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? data.aws_route53_zone.main[0].zone_id : "")
  zone_id            = trimprefix(local.raw_zone_id, "/hostedzone/")
}

resource "aws_security_group" "observability" {
  name_prefix = "${var.environment}-observability-"
  description = "Security group for the RGS Observability downstream node"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id

  ingress {
    description = "Kubernetes API (for Rancher agent registration)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS (Observability UI, once installed)"
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
    Name = "${var.environment}-observability-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "observability" {
  name_prefix = "${var.environment}-observability-"

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
    Name = "${var.environment}-observability-role"
  }
}

resource "aws_iam_instance_profile" "observability" {
  name_prefix = "${var.environment}-observability-"
  role        = aws_iam_role.observability.name
}

resource "aws_iam_role_policy_attachment" "observability_ssm" {
  role       = aws_iam_role.observability.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for cert-manager Route53 DNS-01 challenge, once cert-manager is
# installed on this cluster (mirrors rancher-manager's identical policy -
# each downstream cluster runs its own cert-manager, so each node's IAM role
# needs this independently).
resource "aws_iam_policy" "cert_manager_route53" {
  count       = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  name_prefix = "${var.environment}-observability-certmanager-route53-"
  description = "Allow cert-manager to manage Route53 records for DNS-01 challenge"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${local.zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-observability-certmanager-route53-policy"
  }
}

resource "aws_iam_role_policy_attachment" "observability_cert_manager_route53" {
  count      = var.enable_letsencrypt && var.create_route53_record ? 1 : 0
  role       = aws_iam_role.observability.name
  policy_arn = aws_iam_policy.cert_manager_route53[0].arn
}

resource "aws_key_pair" "observability" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "${var.environment}-observability-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.environment}-observability-key"
  }
}

resource "aws_instance" "observability" {
  ami                  = var.ami_id != "" ? var.ami_id : data.aws_ami.sl_micro.id
  instance_type        = var.observability_instance_type
  subnet_id            = data.terraform_remote_state.shared.outputs.public_subnet_ids[0]
  key_name             = var.ssh_public_key != "" ? aws_key_pair.observability[0].key_name : null
  iam_instance_profile = aws_iam_instance_profile.observability.name
  vpc_security_group_ids = [
    aws_security_group.observability.id,
    data.terraform_remote_state.shared.outputs.ssh_security_group_id,
    data.terraform_remote_state.shared.outputs.internal_security_group_id
  ]

  root_block_device {
    volume_size           = var.observability_root_volume_size
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
    Name = "${var.environment}-observability-node"
  }
}

resource "aws_eip" "observability" {
  count    = var.create_eip ? 1 : 0
  instance = aws_instance.observability.id
  domain   = "vpc"

  tags = {
    Name = "${var.environment}-observability-eip"
  }
}

resource "aws_route53_record" "observability" {
  count   = var.create_route53_record && var.subdomain != "" && var.root_domain != "" ? 1 : 0
  zone_id = local.zone_id
  name    = "${var.hostname_observability}.${var.subdomain}.${var.root_domain}"
  type    = "A"
  ttl     = 300
  records = [var.create_eip ? aws_eip.observability[0].public_ip : aws_instance.observability.public_ip]
}
