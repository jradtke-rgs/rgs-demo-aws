#!/bin/bash
set -e

# cloud-init runs this script with $HOME unset. Helm (and other XDG-aware
# tools) then resolve their config/cache dirs as *relative* paths (e.g.
# ".config/helm") instead of "$HOME/.config/helm". On SL-Micro the cwd during
# cloud-init is "/", which is a read-only btrfs snapshot - so those relative
# mkdirs fail with "read-only file system" before Helm ever runs. Confirmed
# on a real instance 2026-08-05. Setting HOME explicitly fixes this; /root is
# its own writable btrfs subvolume on SL-Micro (unlike bare "/").
export HOME=/root
cd /root

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting SL-Micro RKE2 + Rancher setup..."
echo "Running as: $(whoami)"
echo "Started at: $(date)"

# NOTE: SL-Micro (SUSE Linux Enterprise Micro) is a transactional, largely
# read-only OS - /usr is served from an immutable btrfs snapshot and package
# changes normally require `transactional-update` + a reboot to take effect.
# This script deliberately avoids `zypper install` for anything and only
# writes static binaries into /usr/local/bin, which is writable at runtime.
# VERIFY THIS on a real instance before relying on it - if /usr/local turns
# out to be read-only too, swap the binary installs below for
# `transactional-update pkg install ...` + reboot instead.

#######################################
# Get instance metadata
#######################################
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

#######################################
# Configure Carbide Secured Registry auth for containerd
#######################################
# The Carbide Secured Registry (registry.ranchercarbide.dev) is the acquisition point
# for RGS-hardened images. This demo is fully internet-connected, so RKE2's
# embedded containerd authenticates to it directly via registries.yaml - no
# Hauler/Harbor mirroring step needed.
echo "Configuring RKE2 containerd registry auth for ${rgs_carbide_registry}..."
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

#######################################
# Install RKE2 (server)
#######################################
echo "Installing RKE2..."
%{ if rke2_version != "" ~}
export INSTALL_RKE2_VERSION="${rke2_version}"
echo "Installing RKE2 version: ${rke2_version}"
%{ else ~}
echo "Installing latest stable RKE2 version"
%{ endif ~}

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -

# RKE2 server config (TLS SANs, kubeconfig permissions)
cat <<CONFIG_EOF > /etc/rancher/rke2/config.yaml
tls-san:
  - "${hostname}"
  - "$PUBLIC_IP"
  - "$PRIVATE_IP"
write-kubeconfig-mode: "0644"
CONFIG_EOF

systemctl enable rke2-server.service
systemctl start rke2-server.service

# Wait for RKE2 service to be active
echo "Waiting for RKE2 service to be active..."
until systemctl is-active --quiet rke2-server; do
  echo "RKE2 service not yet active..."
  sleep 5
done

# Put RKE2's bundled kubectl/crictl on PATH and set up kubeconfig
mkdir -p /root/.kube /home/ec2-user/.kube
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
ln -sf /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chmod 600 /root/.kube/config
cat << EOF | tee -a /root/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=\$PATH:/var/lib/rancher/rke2/bin
alias kge='clear; kubectl get events --sort-by=.lastTimestamp'
alias kgea='clear; kubectl get events -A --sort-by=.lastTimestamp'
set -o vi
EOF
cp /etc/rancher/rke2/rke2.yaml /home/ec2-user/.kube/config
cat << EOF | tee -a /home/ec2-user/.bashrc
export KUBECONFIG=~/.kube/config
export PATH=\$PATH:/var/lib/rancher/rke2/bin
alias kge='clear; kubectl get events --sort-by=.lastTimestamp'
alias kgea='clear; kubectl get events -A --sort-by=.lastTimestamp'
set -o vi
PS1="\u@\h - ${hostname_short} - \w \$ "
EOF
chown -R ec2-user /home/ec2-user/.kube

# Wait for RKE2 API server to be responsive
echo "Waiting for RKE2 API server to be ready..."
until kubectl get nodes > /dev/null 2>&1; do
  echo "RKE2 API server not yet responsive..."
  sleep 5
done

# Wait for nodes to be Ready
echo "Waiting for RKE2 node to be Ready..."
until kubectl wait --for=condition=Ready nodes --all --timeout=10s > /dev/null 2>&1; do
  echo "RKE2 node not yet ready..."
  sleep 5
done

# Wait for core RKE2 components to be running
echo "Waiting for core RKE2 components..."
until kubectl get deployment -n kube-system rke2-coredns-rke2-coredns > /dev/null 2>&1; do
  echo "CoreDNS not yet deployed..."
  sleep 5
done

kubectl wait --for=condition=available --timeout=300s deployment/rke2-coredns-rke2-coredns -n kube-system

echo "RKE2 is fully ready!"

#######################################
# Install Helm (static binary - see immutability note at top of file)
#######################################
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

#######################################
# Install cert-manager
#######################################
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v${cert_manager_version}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager || true

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v${cert_manager_version} \
  --wait

kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

#######################################
# Configure Let's Encrypt ClusterIssuer (if enabled)
#######################################
%{ if enable_letsencrypt ~}
echo "Configuring Let's Encrypt ClusterIssuer..."

cat <<'ISSUER_EOF' | kubectl apply -f -
${letsencrypt_clusterissuer}
ISSUER_EOF

echo "Using environment: ${letsencrypt_environment}"

for issuer in letsencrypt-staging letsencrypt-production; do
    timeout=60
    while [ $timeout -gt 0 ]; do
        status=$(kubectl get clusterissuer $issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$status" = "True" ]; then
            echo "ClusterIssuer $issuer is ready"
            break
        fi
        sleep 2
        ((timeout--))
    done
done
%{ endif ~}

kubectl create namespace cattle-system || true

%{ if enable_letsencrypt ~}
echo "Creating Let's Encrypt Certificate for Rancher..."

cat <<'CERT_EOF' | kubectl apply -f -
${letsencrypt_certificate}
CERT_EOF

timeout=300
while [ $timeout -gt 0 ]; do
    ready=$(kubectl get certificate rancher-tls -n cattle-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$ready" = "True" ]; then
        echo "Certificate rancher-tls issued successfully"
        break
    fi
    sleep 5
    ((timeout--))
done
%{ endif ~}

#######################################
# Install Rancher
#######################################
%{ if rgs_carbide_rancher_chart != "" ~}
# TODO: unverified - confirm this OCI reference against real Carbide Portal access
echo "Installing Rancher from Carbide-hosted chart: ${rgs_carbide_rancher_chart}"
helm install rancher "${rgs_carbide_rancher_chart}" \
  --namespace cattle-system \
  --set hostname=${hostname} \
  --set replicas=1 \
  --set bootstrapPassword=admin \
%{ if enable_letsencrypt ~}
  --set ingress.tls.source=secret \
  --set privateCA=false \
%{ endif ~}
  --wait \
  --timeout 15m
%{ else ~}
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=${hostname} \
  --set replicas=1 \
  --set bootstrapPassword=admin \
%{ if enable_letsencrypt ~}
  --set ingress.tls.source=secret \
  --set privateCA=false \
%{ endif ~}
%{ if rgs_carbide_rancher_image != "" ~}
  --set rancherImage=${rgs_carbide_rancher_image} \
%{ endif ~}
  --version ${rancher_version} \
  --wait \
  --timeout 15m
%{ endif ~}

echo "Waiting for Rancher deployment to be available..."
kubectl -n cattle-system wait --for=condition=available --timeout=600s deployment/rancher
kubectl -n cattle-system wait --for=condition=ready --timeout=600s pod -l app=rancher

echo "Rancher installation complete!"
echo "Access Rancher at: https://${hostname}"
echo "Bootstrap password: admin"
echo "Please change the password on first login"
