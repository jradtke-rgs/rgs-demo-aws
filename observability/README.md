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

## Installing RGS Observability

Once the cluster shows `Active` in Rancher, run `install-rgs-observability.sh`
on the node (over SSH, as root) - confirmed working end-to-end 2026-08-05:

```bash
ssh -i ~/.ssh/rgs-demo-aws.pem ec2-user@$(cd observability && tofu output -raw public_ip) \
  'sudo RGS_OBSERVABILITY_LICENSE="<from Carbide Portal>" \
   RGS_OBSERVABILITY_ADMIN_PASSWORD="<generate one - see script header>" \
   RGS_RANCHER_URL="https://rancher.<subdomain>.<root_domain>" \
   RGS_OBSERVABILITY_BASE_URL="https://observability.<subdomain>.<root_domain>" \
   RGS_OBSERVABILITY_HOSTNAME="observability.<subdomain>.<root_domain>" \
   RGS_CARBIDE_REGISTRY="registry.ranchercarbide.dev" \
   bash -s' < observability/install-rgs-observability.sh
```

This is a real, multi-component product (Elasticsearch, Kafka, Zookeeper,
HBase, ClickHouse, VictoriaMetrics, plus the StackState API/UI/etc.) - not
a single container. Several non-obvious things had to be worked out live
against a real deployment; all are handled by the script, but worth knowing
about if you're debugging a variation of this:

- **RKE2 has no default StorageClass** (unlike K3s's bundled
  `local-path-provisioner`) - every StatefulSet's PVC stays `Pending`
  forever without one. The script installs Rancher's `local-path-provisioner`
  and sets it as default.
- **Chart version matters**: pinned to `2.10.2`, not latest (`2.10.3`).
  `2.10.3` was published the day before this was tested and referenced image
  tags Carbide's registry mirror hadn't caught up to yet - pulls failed with
  `403 Forbidden` (Harbor returns 403, not 404, for a nonexistent tag, same
  as its 401-vs-"real auth failure" ambiguity - always check the registry's
  own `/v2/<repo>/tags/list` before concluding it's a credentials/entitlement
  problem). Re-verify next time - Carbide's mirror will have caught up
  further by then, and a newer chart version may work.
- **`registries.yaml` gets wiped on every node reboot/plan reconcile**:
  Rancher's system-agent re-applies its machine plan (which doesn't know
  about our out-of-band registry config) any time it reconciles, including
  after a `tofu apply` that resizes/restarts the instance. If you see
  `401 ... failed to fetch anonymous token` again after any node restart,
  re-check `/etc/rancher/rke2/registries.yaml` isn't 0 bytes before assuming
  the credentials broke - re-stage it and `systemctl restart rke2-server` if so.
- **Sizing**: `observability_instance_type` defaults to `m5.4xlarge` (16
  vCPU/64GB) - confirmed live minimum for the `10-nonha` profile once the
  *entire* stack schedules together (hit `Insufficient cpu` at ~95%
  allocated on a `t3.2xlarge` otherwise). A burstable T-family instance is
  also the wrong class here regardless of size - this is a sustained
  multi-service backend, and the scheduler's admission check is based on
  declared resource requests, not actual usage/burst credits, so bursting
  doesn't help it schedule more.

## Note

`user-data.sh` only pre-stages Carbide registry auth
(`/etc/rancher/rke2/registries.yaml`) - it does not install RKE2. Rancher's
custom-cluster registration command installs RKE2/the system-agent itself
when you run it on the node.
