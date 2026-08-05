# Common variables shared across all OpenTofu modules
# This file should be symlinked into each module and referenced via -var-file=../terraform.tfvars

# AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "rgs-demo-aws"
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
  default     = "rgs-demo"
}

# Network Configuration (shared-services only)
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use (1-6). Default is 1 to minimize cross-AZ cost for a demo."
  type        = number
  default     = 1

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "The az_count must be between 1 and 6."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-2a"]
}

variable "enable_nat_gateway" {
  description = "Boolean whether to deploy NATGW (future use)"
  type        = bool
  default     = false
}

# Security Configuration
variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for better security
}

variable "allowed_web_cidr_blocks" {
  description = "CIDR blocks allowed to access web interfaces"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for better security
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access service interfaces (fallback for modules)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for instance access (shared across all instances)"
  type        = string
  default     = ""

  validation {
    condition = (
      var.ssh_public_key == "" ||
      can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ", var.ssh_public_key))
    )
    error_message = "The ssh_public_key must be a valid SSH public key starting with ssh-rsa, ssh-ed25519, or ecdsa-sha2-*."
  }
}

# Instance Configuration - Module Specific
variable "rancher_instance_type" {
  description = "EC2 instance type for Rancher Manager server"
  type        = string
  default     = "t3.large"
}

variable "observability_instance_type" {
  description = "EC2 instance type for RGS Observability downstream node"
  type        = string
  default     = "t3.large"
}

variable "security_instance_type" {
  description = "EC2 instance type for the user-apps downstream node hosting RGS Security"
  type        = string
  default     = "t3.large"
}

variable "rancher_root_volume_size" {
  description = "Root volume size in GB for Rancher Manager"
  type        = number
  default     = 100
}

variable "observability_root_volume_size" {
  description = "Root volume size in GB for the Observability downstream node"
  type        = number
  default     = 100
}

variable "security_root_volume_size" {
  description = "Root volume size in GB for the user-apps downstream node"
  type        = number
  default     = 100
}

# Elastic IP Configuration
variable "create_eip" {
  description = "Create Elastic IPs for instances (applies to product modules)"
  type        = bool
  default     = true
}

# DNS Configuration (Route53)
variable "create_route53_record" {
  description = "Create Route53 DNS records for services"
  type        = bool
  default     = false
}

variable "root_domain" {
  description = "Root domain name (e.g., kubernerdes.com)"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Environment subdomain (e.g., rgs-demo-aws)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (leave empty to auto-discover from subdomain.root_domain)"
  type        = string
  default     = ""
}

# DNS Hostnames (per product)
variable "hostname_rancher" {
  description = "Hostname for Rancher Manager service (e.g., rancher). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "rancher"
}

variable "hostname_observability" {
  description = "Hostname for the RGS Observability downstream node (e.g., observability). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "observability"
}

variable "hostname_userapps" {
  description = "Hostname for the downstream cluster hosting the RGS Security demo (e.g., user-apps). Creates hostname.subdomain.root_domain"
  type        = string
  default     = "user-apps"
}

# RGS / Carbide Portal Registration
# The Carbide Secured Registry (rgcrprod.azurecr.us) is the acquisition point for
# RGS-hardened images. It is documented as NOT intended to be the primary registry
# clusters pull from in production, but for this connected (non-airgapped) demo,
# nodes authenticate to it directly - no Hauler/Harbor mirroring for v1.
variable "rgs_carbide_registry" {
  description = "Carbide Secured Registry hostname"
  type        = string
  default     = "rgcrprod.azurecr.us"
}

variable "rgs_carbide_username" {
  description = "Carbide Portal registry username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rgs_carbide_password" {
  description = "Carbide Portal registry password/token"
  type        = string
  default     = ""
  sensitive   = true
}

# Product-Specific Versions
# NOTE: rancher_version and rke2_version are coupled - each Rancher chart
# release pins a kubeVersion ceiling (e.g. rancher-2.14.3's chart requires
# kubeVersion < 1.36.0-0). If you bump rke2_version past that ceiling,
# `helm install rancher` fails with "chart requires kubeVersion: ...". Check
# https://releases.rancher.com/server-charts/stable/index.yaml (kubeVersion
# field) before changing either default.
variable "rancher_version" {
  description = "Rancher version to install"
  type        = string
  default     = "2.14.3"
}

# NOTE: also coupled to the RKE2/Kubernetes version - cert-manager only
# supports a rolling window of Kubernetes releases (e.g. 1.21.x supports
# 1.33-1.36). Check https://cert-manager.io/docs/releases/ before changing
# either default.
variable "cert_manager_version" {
  description = "Cert-manager version to install"
  type        = string
  default     = "1.21.1"
}

variable "rke2_version" {
  description = "RKE2 version to install (e.g., v1.30.0+rke2r1). Leave empty to use latest stable release."
  type        = string
  default     = ""
}

variable "rgs_carbide_rancher_chart" {
  description = "OCI reference for a Carbide-hosted Rancher Helm chart, if/when confirmed. Leave empty to install the public rancher-stable chart with images sourced via registries.yaml."
  type        = string
  default     = ""
}

variable "rgs_carbide_rancher_image" {
  description = "Carbide registry image path for Rancher (e.g. rgcrprod.azurecr.us/rancher/rancher), if/when confirmed. Leave empty to use the chart's default (non-hardened) image."
  type        = string
  default     = ""
}

# RGS Observability Configuration
variable "rgs_observability_license" {
  description = "RGS Observability license key (required for observability module)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "rgs_observability_base_url" {
  description = "Base URL for RGS Observability (e.g., https://observability.example.com)"
  type        = string
  default     = ""
}

variable "rgs_rancher_url" {
  description = "Base URL for RGS Rancher Manager (e.g., https://rancher.example.com)"
  type        = string
  default     = ""
}

variable "rgs_observability_admin_password" {
  description = "Admin password for RGS Observability (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

# AMI Configuration (optional override)
variable "ami_id" {
  description = "AMI ID to use (leave empty to use latest SL-Micro AMI)"
  type        = string
  default     = ""
}

# Let's Encrypt Configuration
variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = ""

  validation {
    condition = (
      var.letsencrypt_email == "" ||
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.letsencrypt_email))
    )
    error_message = "The letsencrypt_email must be a valid email address when provided."
  }
}

variable "letsencrypt_environment" {
  description = "Let's Encrypt environment: 'staging' for testing, 'production' for real certificates"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.letsencrypt_environment)
    error_message = "The letsencrypt_environment must be either 'staging' or 'production'."
  }
}

variable "enable_letsencrypt" {
  description = "Enable Let's Encrypt certificate automation via cert-manager"
  type        = bool
  default     = false
}
