# observability

Provisions the AWS node for RGS Observability's **own downstream RKE2
cluster** (deliberately separate from the `rancher-manager` node, per this
session's decision). Optional module - see `ProjectSpec.md`.

```bash
cd observability
tofu init
tofu plan  -var-file=../terraform.tfvars
tofu apply -var-file=../terraform.tfvars
```

## Registering the cluster

```bash
Scripts/rgsctl register observability observability
```

This logs into Rancher's REST API, creates the `observability` custom
cluster object, and runs the node registration command over SSH - no manual
UI clicking required. Confirmed working live against a real Rancher 2.14.3
instance (2026-08-05). See `Scripts/rgsctl`'s `register_cluster` function for
the two strict-CA-verification workarounds this needed (both required even
though this demo uses a real, publicly-trusted Let's Encrypt cert).

If you'd rather do it by hand instead: in Rancher, **Cluster Management →
Import Existing** (or **Create → Custom**), name it `observability`, copy the
generated registration command, and run it on this node (`tofu output
ssh_command`) - but you'll need to add `CATTLE_AGENT_STRICT_VERIFY=false`
before `sh -s -` in that command and set `agentEnvVars: STRICT_VERIFY=false`
on the cluster object first, or `cattle-cluster-agent` will crash-loop.

Once the cluster shows `Active` in Rancher:

`helm install` the RGS Observability chart against that cluster's kubeconfig
(grab it from the Rancher UI). Confirm the exact chart name/repo from the
Carbide Portal - flagged as case-by-case in `ProjectSpec.md` since not every
RGS product is guaranteed to be a plain Helm chart. This step is still
manual.

## Note

`user-data.sh` only pre-stages Carbide registry auth
(`/etc/rancher/rke2/registries.yaml`) - it does not install RKE2. Rancher's
custom-cluster registration command installs RKE2/the system-agent itself
when you run it on the node.
