# rancher-cloud-credential

Creates the one AWS credential Rancher needs to provision everything
downstream of itself - its **EC2 node driver** (used to create the
Observability and user-apps custom/RKE2 clusters) and its **EKS driver**.
One shared credential covers both, per this session's decision - simpler
for a demo than splitting per-driver.

Rancher's Cloud Credential UI only supports static AWS access key/secret
for both driver types - there's no assumable-role option - so this module
creates a scoped IAM user + access key rather than a role. Since it's a
plain Terraform resource, `rgsctl destroy` removes the user/key
automatically - no separate manual credential cleanup step after the demo.

```bash
cd rancher-cloud-credential
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
tofu output access_key_id
tofu output -raw secret_access_key
```

## Manual steps (Rancher UI)

1. Log in to Rancher (`rancher-manager` module's `rancher_url` output).
2. **Cluster Management → Cloud Credentials → Create → Amazon**, paste in
   the `access_key_id`/`secret_access_key` outputs above.
3. To create the Observability or user-apps cluster: **Cluster Management →
   Create → Custom** (or your RKE2 node-driver option of choice), select
   this Cloud Credential, and configure the node.
4. To create the EKS cluster: **Cluster Management → Create → Amazon EKS**,
   select the same Cloud Credential, pick the VPC/subnets from the
   `shared-services` module output, and configure the node group.
5. Wait for each cluster to reach `Active`, then grab its kubeconfig from
   the Rancher UI.

## TODO / unverified

- The IAM policy in `main.tf` is a reasonable starting point (EC2 node
  driver + EKS driver permission sets merged into one) but not verified
  against Rancher's official minimum-IAM-policy documentation for either
  driver - tighten once you've actually created a node/cluster through the
  UI and can see what it complains is missing.
- Once this flow is proven manually, convert it to `rancher2_cluster_v2` (+
  `eks_config_v2` for EKS specifically) via the `rancher2` Terraform
  provider.
