# eks-cluster

New territory for this repo - there's no `suse-demo-aws` precedent for
provisioning EKS through Rancher's EKS driver. This module only creates the
AWS-side IAM plumbing; **the actual downstream EKS cluster is provisioned
manually via the Rancher UI for v1.**

```bash
cd eks-cluster
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
tofu output eks_driver_role_arn
```

## Manual steps (Rancher UI)

1. Log in to Rancher (`rancher-manager` module's `rancher_url` output).
2. **Cluster Management → Cloud Credentials → Create** → Amazon. Depending on
   what the Rancher EKS driver's credential form actually expects (see TODO
   below), either supply an access key/secret for an IAM user with the policy
   from this module attached, or reference the role ARN from
   `tofu output eks_driver_role_arn`.
3. **Cluster Management → Create → Amazon EKS**, select the Cloud Credential
   from step 2, pick the VPC/subnets from the `shared-services` module
   output, and configure the node group size/instance type.
4. Wait for the cluster to reach `Active`, then `tofu output` isn't
   applicable here - grab `kubeconfig` from the Rancher UI directly.

## TODO / unverified

- Confirm whether Rancher's EKS Cloud Credential form wants a static AWS
  access key/secret (most likely) or can assume `aws_iam_role.eks_driver`
  directly. If it needs static keys, add an `aws_iam_user` + `aws_iam_access_key`
  resource here instead (or in addition).
- The IAM policy in `main.tf` is a reasonable starting point but not verified
  against Rancher's official minimum-IAM-policy documentation for the EKS
  driver - tighten once you can test an actual `tofu apply` + cluster create.
- Once this flow is proven manually, convert it to `rancher2_cluster_v2` +
  `eks_config_v2` via the `rancher2` Terraform provider.
