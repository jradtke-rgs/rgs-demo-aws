# security

RGS Security is demoed on a separate downstream RKE2 cluster, at
**`user-apps.<subdomain>.<root_domain>`**, provisioned **from Rancher
itself** via its EC2 node driver - not by OpenTofu. There's nothing left
for this directory's `.tf` files to manage; it's just this README until
the product install script exists. Optional module - see `ProjectSpec.md`.

## Creating the cluster

1. Make sure `rancher-cloud-credential` has been applied and its Cloud
   Credential added in Rancher (**Cluster Management → Cloud Credentials →
   Create → Amazon**) - see that module's README.
2. In Rancher: **Cluster Management → Create → Custom** (or your RKE2
   node-driver option), name it `user-apps`, select the Cloud Credential,
   and configure the node.
3. Wait for the cluster to reach `Active`.
4. DNS is a manual step: once you know the node's IP, create a Route53 A
   record for `hostname_userapps.subdomain.root_domain` (from
   `terraform.tfvars`) pointing at it, if you want a clean hostname.

## Installing RGS Security

Still fully manual and unconfirmed: `helm install` the RGS Security chart
against the cluster's kubeconfig once you know the exact chart name/repo
from the Carbide Portal - case-by-case, per `ProjectSpec.md`, since not
every RGS product is guaranteed to be a plain Helm chart. No install script
exists yet for this one (unlike `observability/install-rgs-observability.sh`).
