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
provision AWS-side infrastructure via OpenTofu. Downstream custom-cluster
*registration* for observability/security is now automated (`rgsctl register
<module> <cluster-name>` - REST API + SSH, no Terraform `rancher2` provider
involved, confirmed live 2026-08-05). Still manual: the EKS driver setup
(`eks-cluster/README.md`) and the actual RGS product Helm installs, since the
real Carbide Portal chart source isn't confirmed yet.

## Common Commands

```bash
Scripts/rgsctl checkdns   # preflight: verify AWS creds can see the Route53 zone in terraform.tfvars
Scripts/rgsctl build      # deploy shared-services, rancher-manager, eks-cluster, observability, security in order (runs checkdns first)
Scripts/rgsctl output     # show outputs from every module
Scripts/rgsctl getkube    # grab rancher-manager's kubeconfig (only module with one until manual import happens)
Scripts/rgsctl register observability observability   # register the bare node as a downstream cluster
Scripts/rgsctl register security user-apps             # same, for the Security demo cluster
Scripts/rgsctl orphans [--delete]   # find/remove AWS resources not tracked in any module's tofu state
Scripts/rgsctl destroy    # tear down in reverse order, with confirmation prompt
```

`checkdns` treats read access to the hosted zone as a proxy for write access
(no IAM policy simulation, no create/delete probe record) - if the zone is
visible under these credentials, we assume it's also writable.

`orphans` compares AWS resources tagged/named `${environment}-*` against
resource IDs pulled live from `tofu show -json` - **not a hardcoded list**.
Critically, it scans every sibling `${repo_dir}*` directory too (e.g.
`rgs-demo-aws-2026-08-05-04`), not just the current checkout: this repo's
own Quick Start archives an existing checkout (`mv` to a dated dir) before
cloning fresh rather than destroying it first, so a brand-new clone's local
state is legitimately empty while previously-deployed resources are still
live and tracked in that archived sibling. Confirmed live 2026-08-05: without
the sibling scan, `orphans` misreported an entire live deployment (5 EC2
instances, EIPs, security groups, IAM roles) as orphaned because its real
state was sitting in `rgs-demo-aws-2026-08-05-04`, not the fresh checkout.
**Caveat**: if an old archived checkout is deleted without running `rgsctl
destroy` in it first, its resources become genuinely untracked orphans that
no tool can distinguish from currently-live ones by state alone.

Or manually, per module: `tofu init && tofu plan -var-file=../terraform.tfvars && tofu apply -var-file=../terraform.tfvars`

## Configuration

Single unified `terraform.tfvars` at the repo root (gitignored), referenced
by every module via `-var-file=../terraform.tfvars`. `common-vars.tf` is
symlinked into each module directory - edit the root copy, not the symlink.

No `~/.config`-based credential loading - AWS creds come from the normal AWS
CLI credential chain, Carbide Portal creds and the Observability license key
live in `terraform.tfvars`.

## Confirmed Live Against a Real Deployment (2026-08-05)

- **SL-Micro AMI filter**: confirmed via a real `aws ec2 describe-images`
  call against owner `013907871322`: `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`.
  Re-verify if it stops matching.
- **SL-Micro's `/` is read-only, but `/root`/`/var`/`/usr/local` are separate
  writable btrfs subvolumes** - the `/usr/local` write concern flagged
  earlier was a non-issue (RKE2's installer correctly falls back to `/opt`
  when needed, and Helm's `/usr/local/bin` install worked fine). The *real*
  bug: cloud-init runs `user-data.sh` with `$HOME` unset, so Helm resolves
  config/cache dirs as relative paths against cwd `/` - which *is* read-only
  - causing `mkdir .config: read-only file system` right at `helm repo add`.
  Fixed in all three `user-data.sh` scripts with `export HOME=/root; cd /root`
  near the top.
- **`rancher_version`/`cert_manager_version` version-skew**: defaults were
  ~2 years stale and incompatible with `rke2_version`'s "latest stable"
  default (chart `kubeVersion` ceiling exceeded). Bumped to current releases
  compatible with RKE2 1.35.x - see the coupling comments in `common-vars.tf`.
- **Downstream cluster registration requires bypassing strict CA verification
  twice, even with a real public Let's Encrypt cert** (not just self-signed
  setups):
  1. `system-agent-install.sh` hardcodes `STRICT_VERIFY=true` internally and
     fatals without a `--ca-checksum` unless the caller sets
     `CATTLE_AGENT_STRICT_VERIFY=false` in its environment.
  2. The in-cluster `cattle-cluster-agent` deployment independently defaults
     to strict verification and `CrashLoopBackOff`s looking for a CA cert
     file that only gets populated when `--ca-checksum` was used at
     registration. Fixed by setting `agentEnvVars: STRICT_VERIFY=false` on
     the `provisioning.cattle.io.cluster` object at creation time.
  Both fixes are implemented in `Scripts/rgsctl`'s `register_cluster`
  function (`rgsctl register <module> <cluster-name>`).
- **Carbide Secured Registry hostname was wrong**: an earlier default
  (`rgcrprod.azurecr.us`, an Azure Container Registry hostname) came from
  web research done before real Carbide Portal access existed, and was
  simply incorrect. The real hostname is `registry.ranchercarbide.dev`
  (itself Harbor-backed - confirmed via its `/v2/` auth challenge:
  `service="harbor-registry"`). Corrected in `rgs_carbide_registry`'s
  default. Harbor returns `401`/`403` ambiguously for both "wrong
  credentials"/"forbidden" and "this host/repo/tag doesn't exist" - don't
  conclude a credentials or entitlement problem without first checking the
  registry's own `/v2/_catalog` and `/v2/<repo>/tags/list` (no special
  permission needed beyond the same pull creds).
- **RGS Observability install, end-to-end**: `observability/install-rgs-observability.sh`
  installs the public `charts.rancher.com/server-charts/prime/suse-observability`
  chart (**pinned to `2.10.2`, not latest** - see the script's own comments
  for why: the latest chart at test time referenced image tags Carbide's
  mirror hadn't synced yet), with images sourced from Carbide via
  `global.imageRegistry`. Also required: installing `local-path-provisioner`
  (RKE2 has no default StorageClass, unlike K3s) and re-staging
  `registries.yaml` after any node reboot (Rancher's system-agent wipes it
  on every plan reconcile). Confirmed reachable end-to-end over HTTPS
  2026-08-05. `observability_instance_type` bumped to `m5.4xlarge` (16
  vCPU/64GB, non-burstable) - a `t3.2xlarge` hit `Insufficient cpu` once the
  full stack scheduled together.

## Still Unverified

- **Rancher image source**: default install uses the public
  `rancher-stable/rancher` Helm chart. `rgs_carbide_rancher_image` /
  `rgs_carbide_rancher_chart` vars exist to override with Carbide-hosted
  images/chart once that path is confirmed from the Carbide Portal.
- **EKS driver credential mechanism**: `eks-cluster/main.tf` creates an IAM
  role, but Rancher's EKS Cloud Credential form may expect a static AWS
  access key/secret instead. Confirm once you have Rancher UI access.
- **RGS Security chart source**: still not confirmed - `security/` hosts a
  separate demo cluster (`user-apps`) for the Security product specifically,
  which is a different install than Observability's. `rgsctl register`
  gets that cluster to `Active`, but the product install itself is TBD.

## Registry / Airgap

Hauler and Harbor were evaluated and deliberately excluded from v1: this demo
runs fully internet-connected in AWS, and Hauler is purpose-built for
airgapped asset transfer (per Carbide's own docs, it's "recommended," not
required, for connected environments). Nodes authenticate directly to the
Carbide Secured Registry (`registry.ranchercarbide.dev`) via `registries.yaml`.
