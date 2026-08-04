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
      Component   = "eks-cluster"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# This module does NOT create the EKS cluster itself - per this session's
# decision, provisioning the downstream EKS cluster is done manually via the
# Rancher EKS driver (UI) for v1. It only creates the AWS-side IAM plumbing
# that the Rancher EKS Cloud Credential needs.
#
# TODO (unverified): Rancher's EKS Cloud Credential form typically expects a
# static AWS access key/secret rather than an assumable role. If that's the
# case here, create an IAM user instead and attach aws_eks_policy to it, or
# generate an access key for a user that can assume this role. Confirm the
# exact mechanism once you have Rancher UI access and revisit this module.

resource "aws_iam_role" "eks_driver" {
  name_prefix = "${var.environment}-eks-driver-"

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
    Name = "${var.environment}-eks-driver-role"
  }
}

# Starter policy covering what the Rancher EKS driver / eksctl-equivalent
# tooling typically needs (EKS cluster + nodegroup lifecycle, the EC2/IAM
# permissions to build the node group, and PassRole for node/cluster roles).
# TODO: tighten against Rancher's official minimum-IAM-policy documentation
# once you have Carbide Portal / Rancher UI access to test against.
resource "aws_iam_policy" "eks_driver" {
  name_prefix = "${var.environment}-eks-driver-"
  description = "Permissions for the Rancher EKS driver to provision a downstream EKS cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeRouteTables",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion",
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:CreateOrUpdateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "iam:GetRole",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-eks-driver-policy"
  }
}

resource "aws_iam_role_policy_attachment" "eks_driver" {
  role       = aws_iam_role.eks_driver.name
  policy_arn = aws_iam_policy.eks_driver.arn
}
