# rancher-manager

Single-node RKE2 + Rancher Manager (mandatory module). Provisions one SL-Micro
EC2 instance, installs RKE2, and installs Rancher via Helm.

```bash
cd rancher-manager
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

## Carbide registry auth

`rgs_carbide_username`/`rgs_carbide_password` (from `terraform.tfvars`) are
written into `/etc/rancher/rke2/registries.yaml` on the node so containerd can
authenticate to the Carbide Secured Registry (`rgcrprod.azurecr.us`) directly.
No Hauler/Harbor mirroring for v1 - this demo is fully internet-connected.

## Confirmed live (2026-08-05)

- **SL-Micro AMI filter**: `main.tf` uses `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`
  from owner account `013907871322` - confirmed against a real `aws ec2
  describe-images` call, but re-verify if RGS specifies a different image.
- **SL-Micro's `/` is read-only**, but `/root`/`/var`/`/usr/local` are
  separate writable btrfs subvolumes - `/usr/local` writes are fine. The real
  bug: cloud-init runs this script with `$HOME` unset, so Helm resolved its
  config dir as a *relative* path against cwd `/`, hitting `mkdir .config:
  read-only file system` right at `helm repo add`. Fixed with `export
  HOME=/root; cd /root` near the top of the script.
- **`rancher_version`/`cert_manager_version`**: were ~2 years stale and
  incompatible with `rke2_version`'s "latest stable" default. Bumped to
  current releases - see coupling comments in `common-vars.tf`.

## Still unverified (need validation against real Carbide Portal access)

- **Rancher image source**: by default this installs the public
  `rancher-stable/rancher` Helm chart, which pulls Rancher's default (non-
  Carbide) images. `rgs_carbide_rancher_image` and `rgs_carbide_rancher_chart`
  are reserved variables to override this once you confirm the actual Carbide
  image/chart path from the Portal - see the `TODO` in `user-data.sh`.

## Outputs

`rancher_url`, `ssh_command`, and `iam_role_arn` (useful later when wiring up
AWS Cloud Credentials / node registration for downstream clusters).
