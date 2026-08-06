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
* **Downstream clusters**: three, all new territory vs. the reference repo -
  EKS (via the RGS EKS driver), RGS Observability's own cluster, and RGS
  Security's demo cluster at `user-apps.rgs-demo-aws.kubernerdes.com`.
  **Superseded 2026-08-06** - see "Architecture Pivot" below for how these
  actually get created now.
* **AMI**: SL-Micro naming confirmed via a live `aws ec2 describe-images`
  call (2026-08-04): `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`, owner
  account `013907871322`.
* Repo scaffolding lives in `shared-services/`, `rancher-manager/`,
  `rancher-cloud-credential/` (renamed from `eks-cluster/` 2026-08-06),
  `observability/`, `security/`, plus `Scripts/rgsctl` (adapted from
  `suse-demo-aws`'s `democtl`). See `CLAUDE.md` for the full breakdown.

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
* **[Superseded 2026-08-06] Downstream cluster registration was automated**
  (`rgsctl register <module> <cluster-name>`) via Rancher's REST API + SSH -
  worked (confirmed live), but replaced by the Rancher-driven approach in
  "Architecture Pivot" below. Kept for context: this is where the two
  strict-CA-verification workarounds were discovered (see `CLAUDE.md`), and
  where it was confirmed that Rancher's Cloud Credential mechanism wants
  static secrets rather than anything fancier - directly informing the
  pivot's IAM-user-+-key design.
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
  (RKE2 has no default StorageClass). Real minimum sizing: `m5.4xlarge` (16
  vCPU/64GB, non-burstable) - `t3.2xlarge` hit a real CPU scheduling ceiling
  once the full "10-nonha" stack ran together. Full writeup:
  `observability/README.md` and `CLAUDE.md`.
* RGS Security's chart source is still unconfirmed - same category of
  problem, not yet worked through.

## Architecture Pivot: Rancher-Driven Downstream Clusters (2026-08-06)

Regrouped on the overall approach after getting `rgsctl register` +
Observability's install fully working live: that approach - OpenTofu
provisions a bare EC2 instance, then a custom script imports it into
Rancher over SSH + REST API - isn't how Rancher is meant to be used.
Rancher has its own **EC2 node driver** (for custom/RKE2 clusters) and
**EKS driver**, both of which provision the downstream infrastructure
themselves once given an AWS credential.

New model: OpenTofu's job stops at "Rancher Manager is running."
Everything downstream - Observability's cluster, the `user-apps`/Security
cluster, EKS - is created **from Rancher itself**, using one shared IAM
credential (`rancher-cloud-credential`, renamed from `eks-cluster/`) that
OpenTofu creates and destroys automatically. This resolves what was
flagged as unverified when `eks-cluster/` was first scaffolded: Rancher's
node drivers only support static AWS access key/secret Cloud Credentials
in the UI, no assumable-role option - confirmed, not just likely, once
`rgsctl register` proved out that same "Rancher wants static secrets"
pattern for cluster registration tokens.

Also decided: add Carbide as Rancher's global `system-default-registry`
(`rancher-manager/user-data.sh`, automated but unverified live) - this is
what propagates Carbide auth to every node/cluster Rancher subsequently
provisions, replacing the out-of-band `registries.yaml` staging that kept
getting wiped by Rancher's own plan reconciliation.

`observability/` and `security/` lost their `.tf` files entirely (nothing
left for OpenTofu to manage there) but keep their READMEs and, for
Observability, `install-rgs-observability.sh` - that script doesn't care
how the cluster came to exist, so nothing about the confirmed-working
install needed to change. Full breakdown: `CLAUDE.md`.

Note: the older "bare EC2 + manual EC2 deployment" pattern still lives on
in the separate `suse-demo-aws` repo, by design - that repo isn't changing.
