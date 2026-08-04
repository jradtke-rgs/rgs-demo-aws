# shared-services

Foundation infrastructure shared by every other module: VPC, Internet Gateway,
public subnet(s), and security groups (SSH/HTTP/HTTPS/internal).

Deploy this first and destroy it last — every other module reads its outputs
via `terraform_remote_state`.

```bash
cd shared-services
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

Single AZ by default (`az_count = 1`) to avoid cross-AZ data transfer cost on
a demo. No NAT Gateway — all instances get public IPs directly.
