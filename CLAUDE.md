# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

OpenTofu infrastructure-as-code for an RGS (Rancher Government Solutions)
product demo in AWS. Modeled on [suse-demo-aws](https://github.com/cloudxabide/suse-demo-aws)
but adapted for RGS/Carbide specifics: SL-Micro instead of SLES, RKE2 instead
of K3s, Carbide Secured Registry auth instead of SUSEConnect/SCC, and a
downstream-cluster story (EKS via the Rancher EKS driver, plus separate
Observability and Security downstream clusters) that the reference repo never
needed. Full spec and decision log: `ProjectSpec.md`.

## Architecture

1. **shared-services/** - VPC, subnets, security groups. Deploy first, destroy last.
2. **rancher-manager/** - single-node RKE2 + Rancher (mandatory).
3. **eks-cluster/** - AWS IAM plumbing for the Rancher EKS driver. No EC2 instance.
4. **observability/** - bare EC2 node for RGS Observability's own downstream RKE2 cluster.
5. **security/** - bare EC2 node for the `user-apps` downstream RKE2 cluster (RGS Security demo).

All product modules depend on `shared-services/terraform.tfstate` via
`terraform_remote_state`. Never modify `shared-services` after other modules
are deployed.

**v1 scope boundary**: `eks-cluster`, `observability`, and `security` only
provision AWS-side infrastructure. The Rancher-side wiring (EKS driver setup,
custom cluster import, product Helm installs) is a documented manual step per
module's README.md - this was a deliberate choice to avoid guessing at
untested `rancher2`-provider resource shapes. Convert to full automation only
after validating the manual flow against a real Rancher instance.

## Common Commands

```bash
Scripts/rgsctl build      # deploy shared-services, rancher-manager, eks-cluster, observability, security in order
Scripts/rgsctl output     # show outputs from every module
Scripts/rgsctl getkube    # grab rancher-manager's kubeconfig (only module with one until manual import happens)
Scripts/rgsctl destroy    # tear down in reverse order, with confirmation prompt
```

Or manually, per module: `tofu init && tofu plan -var-file=../terraform.tfvars && tofu apply -var-file=../terraform.tfvars`

## Configuration

Single unified `terraform.tfvars` at the repo root (gitignored), referenced
by every module via `-var-file=../terraform.tfvars`. `common-vars.tf` is
symlinked into each module directory - edit the root copy, not the symlink.

No `~/.config`-based credential loading - AWS creds come from the normal AWS
CLI credential chain, Carbide Portal creds and the Observability license key
live in `terraform.tfvars`.

## Known Unverified Items (do not treat as settled)

- **SL-Micro AMI filter**: confirmed via a real `aws ec2 describe-images`
  call against owner `013907871322` on 2026-08-04:
  `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`. Re-verify if it stops matching.
- **SL-Micro immutability**: `user-data.sh` scripts avoid `zypper install`
  entirely (SL-Micro is transactional/read-only) and only write static
  binaries into `/usr/local/bin`. Unverified on a real instance - if that
  path turns out read-only too, switch to `transactional-update pkg install`
  + reboot.
- **Rancher image source**: default install uses the public
  `rancher-stable/rancher` Helm chart. `rgs_carbide_rancher_image` /
  `rgs_carbide_rancher_chart` vars exist to override with Carbide-hosted
  images/chart once that path is confirmed from the Carbide Portal.
- **EKS driver credential mechanism**: `eks-cluster/main.tf` creates an IAM
  role, but Rancher's EKS Cloud Credential form may expect a static AWS
  access key/secret instead. Confirm once you have Rancher UI access.

## Registry / Airgap

Hauler and Harbor were evaluated and deliberately excluded from v1: this demo
runs fully internet-connected in AWS, and Hauler is purpose-built for
airgapped asset transfer (per Carbide's own docs, it's "recommended," not
required, for connected environments). Nodes authenticate directly to the
Carbide Secured Registry (`rgcrprod.azurecr.us`) via `registries.yaml`.
