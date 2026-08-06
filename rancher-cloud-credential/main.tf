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
      Component   = "rancher-cloud-credential"
      ManagedBy   = "opentofu"
      Owner       = var.owner
    }
  }
}

# The one AWS credential Rancher needs to provision everything downstream of
# itself: its EC2 node driver (used for the Observability and user-apps
# custom/RKE2 clusters) and its EKS driver. Rancher's Cloud Credential UI
# only supports static AWS access key/secret for both driver types - there's
# no assumable-role option - so an IAM user + access key is required, not
# just one option among several. Since this is a plain Terraform resource,
# `rgsctl destroy` removes it automatically - no separate manual credential
# cleanup step after the demo.

resource "aws_iam_user" "rancher_cloud_credential" {
  # aws_iam_user doesn't support name_prefix (unlike role/policy), only a
  # fixed name - IAM usernames only need to be unique within the account.
  name = "${var.environment}-rancher-cred"

  tags = {
    Name = "${var.environment}-rancher-cloud-credential"
  }
}

resource "aws_iam_access_key" "rancher_cloud_credential" {
  user = aws_iam_user.rancher_cloud_credential.name
}

# Starter policy covering both driver types Rancher will use this
# credential for. TODO: tighten against Rancher's official minimum-IAM-
# policy documentation once tested against a real node-template/EKS
# cluster creation in the Rancher UI - not verified live yet.
resource "aws_iam_policy" "rancher_cloud_credential" {
  name_prefix = "${var.environment}-rancher-cred-"
  description = "Permissions for Rancher's EC2 node driver and EKS driver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # EKS driver: cluster + nodegroup lifecycle
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        # EC2 node driver + EKS driver shared: describe/build node infra
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
          "ec2:DescribeVolumes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeTags",
          "ec2:CreateSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion"
        ]
        Resource = "*"
      },
      {
        # EC2 node driver: provision/tear down the actual instances + its
        # own SSH key pair per node
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:CreateKeyPair",
          "ec2:ImportKeyPair",
          "ec2:DeleteKeyPair"
        ]
        Resource = "*"
      },
      {
        # EKS driver: managed node group scaling
        Effect = "Allow"
        Action = [
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
    Name = "${var.environment}-rancher-cred-policy"
  }
}

resource "aws_iam_user_policy_attachment" "rancher_cloud_credential" {
  user       = aws_iam_user.rancher_cloud_credential.name
  policy_arn = aws_iam_policy.rancher_cloud_credential.arn
}
