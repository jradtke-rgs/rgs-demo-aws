# observability

RGS Observability runs on its **own downstream RKE2 cluster** (deliberately
separate from the `rancher-manager` node), provisioned **from Rancher
itself** via its EC2 node driver - not by OpenTofu. There's nothing left
for this directory's `.tf` files to manage; it's docs plus the product
install script. Optional module - see `ProjectSpec.md`.

## Creating the cluster

1. Make sure `rancher-cloud-credential` has been applied and its Cloud
   Credential added in Rancher (**Cluster Management → Cloud Credentials →
   Create → Amazon**) - see that module's README.
2. In Rancher: **Cluster Management → Create → Custom** (or your RKE2
   node-driver option), name it `observability`, select the Cloud
   Credential, and configure the node (matches what we'd previously sized
   by hand: `m5.4xlarge`/16 vCPU-64GB minimum for the `10-nonha` profile -
   see the sizing note below).
3. Wait for the cluster to reach `Active`.
4. DNS is now a manual step, since OpenTofu no longer knows the node's IP
   ahead of time: once you know it (Rancher UI or the node driver's own
   output), create a Route53 A record for
   `hostname_observability.subdomain.root_domain` (from `terraform.tfvars`)
   pointing at it, if you want the same clean hostname as before.

## Installing RGS Observability

Once the cluster shows `Active`, run `install-rgs-observability.sh` on the
node (over SSH, as root) - confirmed working end-to-end 2026-08-05:

```bash
RANCHER_URL=$(cd rancher-manager && tofu output -raw rancher_url)

ssh -i ~/.ssh/rgs-demo-aws.pem "ec2-user@<observability-node-ip>" \
  "sudo RGS_OBSERVABILITY_LICENSE='<from Carbide Portal>' \
   RGS_OBSERVABILITY_ADMIN_PASSWORD='<generate one - see script header>' \
   RGS_RANCHER_URL='${RANCHER_URL}' \
   RGS_OBSERVABILITY_BASE_URL='https://<hostname_observability>.<subdomain>.<root_domain>' \
   RGS_OBSERVABILITY_HOSTNAME='<hostname_observability>.<subdomain>.<root_domain>' \
   RGS_CARBIDE_REGISTRY='registry.ranchercarbide.dev' \
   bash -s" < observability/install-rgs-observability.sh
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
- **Why this module no longer stages `registries.yaml` itself**: the
  previous bare-node design pre-staged Carbide auth via
  `/etc/rancher/rke2/registries.yaml` in `user-data.sh` - but Rancher's
  system-agent re-applies its own machine plan on every reconcile (any
  reboot, any resize) and wiped that file every time, since the plan didn't
  know about our out-of-band config. That's exactly why `rancher-manager`
  now configures Carbide as Rancher's `system-default-registry` instead
  (see its README) - Rancher-provisioned nodes (like this one) inherit that
  centrally, and it survives reconciliation because Rancher owns re-applying
  it.
- **Sizing**: `m5.4xlarge` (16 vCPU/64GB) confirmed live as the minimum for
  the `10-nonha` profile once the *entire* stack schedules together (hit
  `Insufficient cpu` at ~95% allocated on a `t3.2xlarge` otherwise). A
  burstable T-family instance is also the wrong class here regardless of
  size - this is a sustained multi-service backend, and the scheduler's
  admission check is based on declared resource requests, not actual
  usage/burst credits, so bursting doesn't help it schedule more.
