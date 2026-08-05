#!/bin/bash
set -e

# cloud-init runs with $HOME unset, which makes XDG-aware tools (Helm, etc.)
# resolve config dirs as relative paths against cwd "/" - a read-only btrfs
# snapshot on SL-Micro. Set HOME/cwd to the writable /root subvolume before
# anything that might need it (e.g. once product Helm installs land here).
export HOME=/root
cd /root

exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Preparing bare node for Rancher custom-cluster import (user-apps / Security demo)..."
echo "Started at: $(date)"

# This node is intentionally left otherwise bare: Rancher's custom-cluster
# registration command (grabbed from the Rancher UI once rancher-manager is
# up) installs RKE2/the system-agent itself. We only pre-stage the Carbide
# registry auth so containerd can pull RGS-hardened images once RKE2 exists.
mkdir -p /etc/rancher/rke2
%{ if rgs_carbide_username != "" && rgs_carbide_password != "" ~}
cat <<REGISTRIES_EOF > /etc/rancher/rke2/registries.yaml
configs:
  "${rgs_carbide_registry}":
    auth:
      username: "${rgs_carbide_username}"
      password: "${rgs_carbide_password}"
REGISTRIES_EOF
chmod 600 /etc/rancher/rke2/registries.yaml
%{ else ~}
echo "No Carbide Portal credentials provided - skipping registries.yaml (public images only)"
%{ endif ~}

echo "Node ready. Import it into Rancher as a custom cluster - see README.md."
