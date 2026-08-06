# Project Specifications

## Goal

Give potential RGS customers a simple way to see the product functionality in action, while also giving them a working understanding of how to implement RGS solutions themselves.

## Requirements / Constraints

* rely on bash 
* run on macOS or Linux
* use openTofu, if needed
* smallest or most cost-efficient AWS EC2 instances possible
* single AZ to safe money (since this is a Demo)
* use Rancher Government Solutions software and Carbide Portal
* breakdown software by concern or product and allow for choice which software is deployed (see table below)
* Parameterize wherever possible (i.e. variable for domain to utilize, hostname for each service/component, Let's Encrypt parameters, AWS instance size)

## User-based Requirements

* AWS auth creds and permissions
* route53 Public Hosted Zone
* Let's Encrypt Account
* Github repo (this repo)

## Software Overview

| Mandatory | Software |
|:---------:|:---------|
| Y | Rancher Manager |
| N | RGS Security |
| N | RGS Observability |

## Deliverable / Outcomes
Deploy:
- single-node Rancher Manager 
  - SL-Micro AMI
  - RKE2 (using Carbide Portal Credentials) 
  - Rancher Manager
- Downstream EKS cluster
  - Deploy from Rancher Manager, using the RGS EKS provisioning driver

## Credentials

Superseded below (see Architecture Decisions) - the `~/.config` idea was
dropped in favor of a gitignored root `terraform.tfvars`, matching
`suse-demo-aws`. AWS creds come from the normal AWS CLI credential chain;
Carbide Portal credentials and the Observability license key live in
`terraform.tfvars`.

## Notes
domain I will use: rgs-demo-aws.kubernerdes.com
use the same AZ if/when possible (no point in spending money on traffic across AZ for a demo)
optional software (RGS Security, RGS Observability) is expected to be delivered as Helm charts; handle exceptions on a case-by-case basis if a component isn't chart-based


This repo will resemble https://github.com/cloudxabide/suse-demo-aws

## Architecture Decisions (finalized after reviewing suse-demo-aws)

* **Credentials**: dropped the earlier `~/.config` idea - AWS creds come from
  the normal AWS CLI credential chain, and Carbide Portal/Observability
  license values live in a gitignored root `terraform.tfvars`, exactly like
  `suse-demo-aws`.
* **Registry access**: no Hauler/Harbor for v1. Researched both - the Carbide
  Secured Registry (`registry.ranchercarbide.dev`) explicitly documents Hauler as
  "recommended" (not required) tooling built for airgapped asset transfer.
  Since this demo is fully internet-connected, nodes authenticate to Carbide
  directly via RKE2's `registries.yaml`. Harbor (mirroring your own registry)
  is a possible future add-on, not v1.
* **Downstream clusters**: three, all new territory vs. the reference repo:
  - EKS cluster, provisioned from Rancher via the RGS EKS driver.
  - RGS Observability gets its **own** downstream RKE2 cluster.
  - RGS Security is demoed on a separate downstream RKE2 cluster at
    `user-apps.rgs-demo-aws.kubernerdes.com`.
  For v1, the AWS-side infrastructure (nodes/IAM/networking) for all three is
  scaffolded in OpenTofu, but the Rancher-side wiring (EKS driver setup,
  custom cluster import, product Helm installs) is a documented manual step -
  converting to full `rancher2`-provider automation is deferred until that
  flow is validated against a real Rancher instance.
* **AMI**: SL-Micro naming confirmed via a live `aws ec2 describe-images`
  call (2026-08-04): `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`, owner
  account `013907871322`.
* Repo scaffolding lives in `shared-services/`, `rancher-manager/`,
  `eks-cluster/`, `observability/`, `security/`, plus `Scripts/rgsctl`
  (adapted from `suse-demo-aws`'s `democtl`). See `CLAUDE.md` for the full
  breakdown and the list of still-unverified assumptions (Rancher's actual
  EKS Cloud Credential mechanism, whether the public `rancher-stable` chart
  vs. a Carbide-hosted chart should be used).

## Findings From the First Real Deployment (2026-08-05)

* **SL-Micro's `/` is read-only** (separate writable btrfs subvolumes for
  `/root`, `/var`, `/usr/local`) - cloud-init runs `user-data.sh` with `$HOME`
  unset, so Helm resolved config dirs as relative paths against cwd `/` and
  hit `mkdir .config: read-only file system`. Fixed with `export HOME=/root`
  in all three `user-data.sh` scripts.
* **`rancher_version`/`cert_manager_version` version-skew**: both defaults
  were ~2 years stale and incompatible with `rke2_version`'s "latest stable"
  default (chart `kubeVersion` ceilings exceeded). Bumped to current,
  RKE2-1.35.x-compatible releases.
* **Downstream cluster registration is now automated**
  (`rgsctl register <module> <cluster-name>`) via Rancher's REST API + SSH -
  no `rancher2` Terraform provider needed after all, and no manual UI
  clicking. Required bypassing strict CA verification in two separate places
  (the node install script and the in-cluster `cattle-cluster-agent`) even
  though this demo uses a real, publicly-trusted Let's Encrypt cert - see
  `CLAUDE.md` for the exact mechanism. Still manual: the EKS driver setup and
  the actual RGS product Helm install (chart source still unconfirmed).
* Let's Encrypt **production** has a real rate limit (5 duplicate certs per
  exact hostname per rolling 7 days) that repeated `rancher-manager` rebuilds
  can hit quickly during iteration - switch `letsencrypt_environment` to
  `staging` while actively rebuilding.
* **RGS Observability is now fully working end-to-end**, confirmed live over
  HTTPS: `observability/install-rgs-observability.sh` installs the public
  `suse-observability` chart (pinned to `2.10.2` - the then-latest `2.10.3`
  referenced image tags Carbide's registry mirror hadn't synced yet) with
  images sourced from Carbide (`registry.ranchercarbide.dev` - the earlier
  `rgcrprod.azurecr.us` default was simply wrong, found via web research
  before real Portal access existed). Also required: `local-path-provisioner`
  (RKE2 has no default StorageClass) and re-staging `registries.yaml` after
  reboots (Rancher's agent wipes it on every plan reconcile). Bumped
  `observability_instance_type` to `m5.4xlarge` (16 vCPU/64GB, non-burstable)
  - `t3.2xlarge` hit a real CPU scheduling ceiling once the full "10-nonha"
  stack ran together. Full writeup: `observability/README.md` and `CLAUDE.md`.
* RGS Security's chart source is still unconfirmed - same category of
  problem, not yet worked through.
