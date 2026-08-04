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

## Known unknowns (flagged in code, need validation against real Carbide Portal access)

- **SL-Micro AMI filter**: `main.tf` uses `suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64`
  from owner account `013907871322` - confirmed against a real `aws ec2
  describe-images` call, but re-verify if RGS specifies a different image.
- **Rancher image source**: by default this installs the public
  `rancher-stable/rancher` Helm chart, which pulls Rancher's default (non-
  Carbide) images. `rgs_carbide_rancher_image` and `rgs_carbide_rancher_chart`
  are reserved variables to override this once you confirm the actual Carbide
  image/chart path from the Portal - see the `TODO` in `user-data.sh`.
- **SL-Micro immutability**: SL-Micro is a transactional, mostly read-only OS.
  `user-data.sh` avoids `zypper install` entirely and only writes static
  binaries (RKE2, Helm) into `/usr/local/bin`, which should be writable at
  runtime - verify this on a real instance; if not, switch to
  `transactional-update pkg install ...` + reboot.

## Outputs

`rancher_url`, `ssh_command`, and `iam_role_arn` (useful later when wiring up
AWS Cloud Credentials / node registration for downstream clusters).
