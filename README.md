# RGS Demo AWS

## Purpose

OpenTofu infrastructure-as-code to stand up a demo environment for Rancher
Government Solutions (RGS) products in AWS: a single-node Rancher Manager
(RKE2 on SL-Micro), with optional RGS Security and RGS Observability demoed
on their own downstream clusters. Goal: give potential RGS customers a
simple way to see the product functionality in action, while also giving
them a working understanding of how to implement RGS solutions themselves.

Structured after [suse-demo-aws](https://github.com/cloudxabide/suse-demo-aws),
adapted for RGS/Carbide specifics. See `ProjectSpec.md` for the full spec and
decision log.

## Products In-Scope

- **Rancher Manager** (mandatory) - single-node RKE2 + Rancher
- **EKS downstream cluster** - provisioned from Rancher via the RGS EKS driver
- **RGS Observability** (optional) - its own downstream RKE2 cluster
- **RGS Security** (optional) - demoed on a `user-apps` downstream RKE2 cluster
- **Let's Encrypt** - certificate automation via cert-manager

## Architecture

```
shared-services/     VPC, subnets, security groups (deploy first, destroy last)
rancher-manager/      single-node RKE2 + Rancher (mandatory)
eks-cluster/          IAM plumbing for the Rancher EKS driver
observability/        bare node for its own downstream RKE2 cluster
security/             bare node for the "user-apps" downstream RKE2 cluster (Security demo)
```

All product modules depend on `shared-services`' tfstate via
`terraform_remote_state`. `eks-cluster`, `observability`, and `security` only
provision AWS-side infrastructure in v1 - the Rancher-side wiring (EKS driver
setup, custom cluster import, product Helm installs) is a documented manual
step per module (see each module's README.md), since it's new territory with
no proven automation to build against yet.

## Prerequisites

- **OpenTofu >= 1.5.0** (`brew install opentofu` on macOS)
- **AWS CLI** configured with valid credentials
- **Route53 Public Hosted Zone** for your domain
- **RGS Carbide Portal** account/credentials
- SSH key pair for EC2 instances

## Quick Start

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with real values (AWS, Carbide, domain, SSH key)

Scripts/rgsctl checkdns   # verify your AWS creds can see the Route53 zone in terraform.tfvars
Scripts/rgsctl build      # deploy AWS-side infra for all modules, in order (runs checkdns first)
Scripts/rgsctl output     # show URLs/IPs from every module
Scripts/rgsctl getkube    # grab rancher-manager's kubeconfig
Scripts/rgsctl destroy    # tear it all down (reverse order)
```

## Manual Steps

This is intentionally **not** fully automated - after `rgsctl build`:

1. Log in to Rancher at the `rancher_url` output from `rancher-manager`.
2. Follow `eks-cluster/README.md` to wire up an AWS Cloud Credential and
   create the downstream EKS cluster via the Rancher EKS driver.
3. Follow `observability/README.md` and `security/README.md` to import each
   node as a custom cluster and Helm-install the corresponding RGS product.

## Credentials

No secrets live in the repo or under `~/.config` - everything (AWS creds via
the AWS CLI's normal credential chain, Carbide Portal registry
username/password, the RGS Observability license) goes into the gitignored
root `terraform.tfvars`. See `terraform.tfvars.example` for the full list.

## Notes and Caveats

- Domain used for this demo: `rgs-demo-aws.kubernerdes.com`.
- Single AZ by default, no NAT Gateway - cost-conscious for a demo, not
  production-hardened.
- Registry access uses direct Carbide Portal auth (`registries.yaml`) - no
  Hauler/Harbor mirroring for v1, since this demo is fully internet-connected
  and Hauler's value is specifically airgap asset transfer.
- Several details are flagged `TODO`/unverified in code and READMEs pending
  real Carbide Portal access - see `rancher-manager/README.md` and
  `eks-cluster/README.md`.

**NOTE:** This is ONLY intended to run as a demo/lab. Trade-offs have been
made to minimize cost which make this approach unacceptable for production
use-cases.
