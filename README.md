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
shared-services/            VPC, subnets, security groups (deploy first, destroy last)
rancher-manager/             single-node RKE2 + Rancher (mandatory)
rancher-cloud-credential/    IAM user+key for Rancher's EC2 node driver + EKS driver
observability/               docs + product install script (no .tf - see below)
security/                     docs only (no .tf - see below)
```

OpenTofu's job stops at "Rancher Manager is running." Everything downstream
- RGS Observability's cluster, the `user-apps` cluster for the RGS Security
demo, and EKS - is created **from Rancher itself**, using the Cloud
Credential `rancher-cloud-credential` outputs. `observability/` and
`security/` have no Terraform resources of their own anymore; they're docs
(and, for Observability, the product Helm-install script) describing that
Rancher-driven flow. See each module's README.md.

## Prerequisites

- **OpenTofu >= 1.5.0** (`brew install opentofu` on macOS)
- **AWS CLI** configured with valid credentials
- **Route53 Public Hosted Zone** for your domain
- **RGS Carbide Portal** account/credentials
- SSH key pair for EC2 instances

## Quick Start

```bash
mkdir -p ~/Developer/Projects; cd $_
# Archive an existing checkout instead of clobbering it
[ -d "rgs-demo-aws" ] && { i=1; while [ -d "rgs-demo-aws-$(date +%F)-$(printf '%02d' $i)" ]; do ((i++)); done; mv rgs-demo-aws "rgs-demo-aws-$(date +%F)-$(printf '%02d' $i)"; }
git clone https://github.com/jradtke-rgs/rgs-demo-aws.git; cd rgs-demo-aws

# Copy in a pre-populated ("hydrated") tfvars kept one level up, outside the
# repo, with real values already filled in. If you don't have one yet, start
# from the repo's own terraform.tfvars.example instead.
cp ../terraform.tfvars.example-rgs-demo-aws terraform.tfvars
cat terraform.tfvars

Scripts/rgsctl build

# Countdown while Rancher finishes bootstrapping (RKE2 + Helm installs take a while)
countdown_seconds=600
while [ "$countdown_seconds" -ge 0 ]; do
    printf "\rTime remaining: %3d seconds \033[0K" "$countdown_seconds"
    countdown_seconds=$((countdown_seconds - 1))
    sleep 1
done
```

And.. the fun:

```
EXAMPLES:
    # Deploy AWS-side infrastructure for all modules, in order
    Scripts/rgsctl build

    # Verify AWS creds can see the Route53 zone in terraform.tfvars
    Scripts/rgsctl checkdns

    # Display OpenTofu outputs (URLs/IPs) from every module
    Scripts/rgsctl output

    # Retrieve rancher-manager's kubeconfig
    Scripts/rgsctl getkube

    # Find AWS resources tagged/named for this environment but not tracked
    # in any module's tofu state (add --delete to remove what's found)
    Scripts/rgsctl orphans

    # Destroy all infrastructure (reverse order, with confirmation prompt)
    Scripts/rgsctl destroy

    # Show help
    Scripts/rgsctl help
```

`rgsctl build` only stands up the AWS-side infrastructure - see **Manual
Steps** below for what's left once it finishes.

## Manual Steps

After `rgsctl build` (shared-services + rancher-manager +
rancher-cloud-credential), everything else happens **in Rancher's UI**:

1. **Cluster Management → Cloud Credentials → Create → Amazon**, using
   `rancher-cloud-credential`'s `access_key_id`/`secret_access_key` outputs.
2. **Cluster Management → Create → Custom** (EC2 node driver) for the
   Observability and `user-apps` clusters, and **Create → Amazon EKS** for
   the EKS cluster - all using that same Cloud Credential. See
   `rancher-cloud-credential/README.md`, `observability/README.md`, and
   `security/README.md`.
3. Once each cluster shows `Active`: `observability/install-rgs-observability.sh`
   installs RGS Observability (confirmed working end-to-end). RGS Security's
   chart source is still unconfirmed (see `ProjectSpec.md`) - `helm install`
   it by hand once you know the chart.

DNS for Observability/`user-apps` is also manual now, since OpenTofu doesn't
know their node IPs ahead of time - create a Route53 A record for
`hostname_observability`/`hostname_userapps` (from `terraform.tfvars`)
pointing at the node once it exists, if you want clean hostnames.

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
- The Quick Start's archive-before-clone pattern means a fresh checkout's
  local state is legitimately empty while previously-deployed resources are
  still live and tracked in a sibling `rgs-demo-aws-YYYY-MM-DD-NN/` archive.
  `rgsctl orphans` accounts for this by scanning sibling `rgs-demo-aws*`
  directories too - but if you delete an old archive directory without
  running `rgsctl destroy` in it first, its resources become real,
  untracked orphans in AWS.
- Several details are flagged `TODO`/unverified in code and READMEs pending
  real Rancher UI/Carbide Portal access - see `rancher-manager/README.md` and
  `rancher-cloud-credential/README.md`.

**NOTE:** This is ONLY intended to run as a demo/lab. Trade-offs have been
made to minimize cost which make this approach unacceptable for production
use-cases.
