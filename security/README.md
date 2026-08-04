# security

Provisions the AWS node for the **`user-apps.<subdomain>.<root_domain>`**
downstream RKE2 cluster used to demo RGS Security - a separate cluster from
both `rancher-manager` and `observability`, per this session's decision.
Optional module - see `ProjectSpec.md`.

```bash
cd security
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

## Manual steps (Rancher UI)

1. In Rancher, **Cluster Management → Import Existing** (or **Create → Custom**),
   name it `user-apps`.
2. Copy the generated registration command and run it on this node
   (`tofu output ssh_command`, or via SSM Session Manager).
3. Wait for the cluster to show `Active` in Rancher.
4. `helm install` the RGS Security chart against that cluster's kubeconfig.
   Confirm the exact chart name/repo from the Carbide Portal - case-by-case,
   per `ProjectSpec.md`, since not every RGS product is guaranteed to be a
   plain Helm chart.

## Note

`user-data.sh` only pre-stages Carbide registry auth
(`/etc/rancher/rke2/registries.yaml`) - it does not install RKE2. Rancher's
custom-cluster registration command installs RKE2/the system-agent itself
when you run it on the node.
