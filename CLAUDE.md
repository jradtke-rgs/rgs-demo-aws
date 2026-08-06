# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

OpenTofu infrastructure-as-code for an RGS (Rancher Government Solutions)
product demo in AWS. Modeled on [suse-demo-aws](https://github.com/cloudxabide/suse-demo-aws)
but adapted for RGS/Carbide specifics: SL-Micro instead of SLES, RKE2 instead
of K3s, Carbide Secured Registry auth instead of SUSEConnect/SCC. Full spec
and decision log: `ProjectSpec.md`.

**Architecture pivot (2026-08-06)**: OpenTofu's job stops at "Rancher
Manager is running." Everything downstream (RGS Observability's cluster,
the `user-apps` cluster for RGS Security, EKS) is created **from Rancher
itself** via its EC2 node driver and EKS driver, using a Cloud Credential
OpenTofu creates once. This replaced an earlier design where
`observability`/`security` provisioned bare EC2 instances that got imported
into Rancher via a custom `rgsctl register` SSH+REST-API script - that
worked (confirmed live) but wasn't how Rancher is meant to be used. See
"Confirmed Live" below for what's preserved from that earlier design.

## Architecture

1. **shared-services/** - VPC, subnets, security groups. Deploy first, destroy last.
2. **rancher-manager/** - single-node RKE2 + Rancher (mandatory).
3. **rancher-cloud-credential/** - IAM user + access key for Rancher's EC2
   node driver and EKS driver (one shared credential, both driver types).
   No EC2 instance.
4. **observability/** - docs + `install-rgs-observability.sh` (the product
   Helm install). No `.tf` files - the cluster itself is created from
   Rancher's UI, not OpenTofu.
5. **security/** - docs only, no `.tf` files, no product install script yet
   (RGS Security's chart source is still unconfirmed).

`rancher-manager` and `rancher-cloud-credential` depend on
`shared-services/terraform.tfstate` via `terraform_remote_state`. Never
modify `shared-services` after other modules are deployed.

**v1 scope boundary**: `rancher-cloud-credential`'s IAM policy is a
starting point covering both driver types, not verified against Rancher's
official minimum-IAM-policy docs. Once a Cloud Credential is created in
Rancher, actually creating the downstream clusters (EC2 node driver for
Observability/`user-apps`, EKS driver for EKS) is manual via the Rancher
UI - no `rancher2`-Terraform-provider automation yet, and no
API-driven script either (unlike the retired `rgsctl register`, since
that whole approach is what's being moved away from). The actual RGS
product Helm installs are likewise manual except for Observability, which
has a confirmed-working script.

## Common Commands

```bash
Scripts/rgsctl checkdns   # preflight: verify AWS creds can see the Route53 zone in terraform.tfvars
Scripts/rgsctl build      # deploy shared-services, rancher-manager, rancher-cloud-credential in order (runs checkdns first)
Scripts/rgsctl output     # show outputs from every module
Scripts/rgsctl getkube    # grab rancher-manager's kubeconfig (only module with one)
Scripts/rgsctl orphans [--delete]   # find/remove AWS resources not tracked in any module's tofu state
Scripts/rgsctl destroy    # tear down in reverse order, with confirmation prompt
```

Everything downstream of `build` (creating the Observability/`user-apps`/EKS
clusters, and their product installs) happens in the Rancher UI now - see
`rancher-cloud-credential/README.md`.

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
- **[Superseded 2026-08-06, kept for context] Downstream cluster registration
  requires bypassing strict CA verification twice, even with a real public
  Let's Encrypt cert** (not just self-signed setups) - this was discovered
  while building the now-retired `rgsctl register` bare-node-import flow,
  and is worth knowing if you ever hit the same path manually (e.g. via
  Rancher's "Import Existing" for a node provisioned some other way):
  1. `system-agent-install.sh` hardcodes `STRICT_VERIFY=true` internally and
     fatals without a `--ca-checksum` unless the caller sets
     `CATTLE_AGENT_STRICT_VERIFY=false` in its environment.
  2. The in-cluster `cattle-cluster-agent` deployment independently defaults
     to strict verification and `CrashLoopBackOff`s looking for a CA cert
     file that only gets populated when `--ca-checksum` was used at
     registration. Fix: set `agentEnvVars: STRICT_VERIFY=false` on the
     `provisioning.cattle.io.cluster` object at creation time.
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
  (RKE2 has no default StorageClass, unlike K3s). Confirmed reachable
  end-to-end over HTTPS 2026-08-05. Sizing: `m5.4xlarge` (16 vCPU/64GB,
  non-burstable) confirmed as the real minimum via Rancher's node-template
  config - a `t3.2xlarge` hit `Insufficient cpu` once the full stack
  scheduled together. (At the time, this ran on a bare node we provisioned
  ourselves, which needed out-of-band `registries.yaml` staging that
  Rancher's system-agent kept wiping on every reboot/plan reconcile - that
  whole problem is why `rancher-manager` now configures Carbide as
  Rancher's `system-default-registry` instead, per the pivot above.)

## Still Unverified

- **Rancher image source**: default install uses the public
  `rancher-stable/rancher` Helm chart. `rgs_carbide_rancher_image` /
  `rgs_carbide_rancher_chart` vars exist to override with Carbide-hosted
  images/chart once that path is confirmed from the Carbide Portal.
- **`rancher-cloud-credential`'s IAM policy**: covers both the EC2 node
  driver and EKS driver permission sets as a reasonable starting point, but
  not verified against Rancher's official minimum-IAM-policy docs for
  either - tighten once you've actually created a node/cluster through the
  UI and can see what it complains is missing.
- **`system-default-registry` automation** (`rancher-manager/user-data.sh`):
  patches the Setting + creates a Private Registry credentials Secret right
  after Rancher's install succeeds, but not yet confirmed live that a
  subsequently-provisioned downstream node actually inherits working
  Carbide auth from it. Deliberately non-fatal if it fails - see
  `rancher-manager/README.md` for the manual UI fallback.
- **RGS Security chart source**: still not confirmed - `security/` hosts a
  separate demo cluster (`user-apps`) for the Security product specifically,
  which is a different install than Observability's. No install script
  exists yet, unlike `observability/install-rgs-observability.sh`.

## Registry / Airgap

Hauler and Harbor were evaluated and deliberately excluded from v1: this demo
runs fully internet-connected in AWS, and Hauler is purpose-built for
airgapped asset transfer (per Carbide's own docs, it's "recommended," not
required, for connected environments). Nodes authenticate directly to the
Carbide Secured Registry (`registry.ranchercarbide.dev`) via `registries.yaml`.
