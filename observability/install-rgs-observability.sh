#!/bin/bash
#
# Installs RGS Observability (the public suse-observability chart, images
# sourced from the Carbide Secured Registry) onto an already-registered
# observability cluster. Run this ON THE NODE (over SSH), as root - it's a
# product-install step, not OpenTofu/user-data, since it needs to run after
# `rgsctl register observability observability` has gotten the cluster to
# Active in Rancher.
#
# Confirmed working end-to-end 2026-08-05. Known gotchas baked in below -
# see observability/README.md for the full writeup of each one.
#
# Required environment variables (do not hardcode real values here - this
# file is committed to git):
#   RGS_OBSERVABILITY_LICENSE        - Carbide Portal license key
#   RGS_OBSERVABILITY_ADMIN_PASSWORD - admin password to set (chart requires
#                                       one explicitly; there is no true
#                                       auto-generate despite common-vars.tf's
#                                       var description - generate one
#                                       yourself, e.g. `openssl rand -base64
#                                       18 | tr -d '/+=' | head -c 24`)
#   RGS_RANCHER_URL                  - e.g. https://rancher.<subdomain>.<root_domain>
#   RGS_OBSERVABILITY_BASE_URL       - e.g. https://observability.<subdomain>.<root_domain>
#   RGS_OBSERVABILITY_HOSTNAME       - just the FQDN, e.g. observability.<subdomain>.<root_domain>
#   RGS_CARBIDE_REGISTRY             - registry.ranchercarbide.dev (rgs_carbide_registry in terraform.tfvars)
#
# Usage:
#   ssh -i ~/.ssh/rgs-demo-aws.pem ec2-user@<observability-public-ip> \
#     'sudo RGS_OBSERVABILITY_LICENSE=... RGS_OBSERVABILITY_ADMIN_PASSWORD=... \
#      RGS_RANCHER_URL=... RGS_OBSERVABILITY_BASE_URL=... \
#      RGS_OBSERVABILITY_HOSTNAME=... RGS_CARBIDE_REGISTRY=... bash -s' \
#     < observability/install-rgs-observability.sh
set -e

for v in RGS_OBSERVABILITY_LICENSE RGS_OBSERVABILITY_ADMIN_PASSWORD RGS_RANCHER_URL RGS_OBSERVABILITY_BASE_URL RGS_OBSERVABILITY_HOSTNAME RGS_CARBIDE_REGISTRY; do
  if [ -z "${!v}" ]; then
    echo "ERROR: required environment variable $v is not set" >&2
    exit 1
  fi
done

# Same HOME/PATH fix as user-data.sh's cloud-init issue, but for a different
# reason here: running via `ssh ... sudo bash -s` goes through sudo's
# secure_path, which doesn't include /usr/local/bin on this SL-Micro image
# (unlike cloud-init, which runs as literal root with no sudo involved).
export HOME=/root
cd /root
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=/usr/local/bin:$PATH:/var/lib/rancher/rke2/bin

echo "=== Installing Helm ==="
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "=== Installing cert-manager ==="
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager || true
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.21.1 \
  --wait
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

echo "=== Creating Let's Encrypt ClusterIssuers ==="
cat <<ISSUER_EOF | kubectl apply -f -
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL:-admin@example.com}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - dns01:
        route53:
          region: ${AWS_REGION:-us-east-2}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL:-admin@example.com}
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
    - dns01:
        route53:
          region: ${AWS_REGION:-us-east-2}
ISSUER_EOF

for issuer in letsencrypt-staging letsencrypt-production; do
    timeout=60
    while [ $timeout -gt 0 ]; do
        status=$(kubectl get clusterissuer $issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        [ "$status" = "True" ] && { echo "$issuer ready"; break; }
        sleep 2
        ((timeout--))
    done
done

# RKE2 does not bundle a default StorageClass (unlike K3s's local-path-
# provisioner) - without one, every StatefulSet's PVC (Elasticsearch, Kafka,
# ClickHouse, HBase, Zookeeper, ...) stays Pending forever. Confirmed live
# 2026-08-05: this silently blocked the entire stack until diagnosed.
echo "=== Installing local-path-provisioner (RKE2 has no default StorageClass) ==="
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl wait --for=condition=available --timeout=120s deployment/local-path-provisioner -n local-path-storage
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "=== Installing RGS Observability ==="
# Pinned to chart 2.10.2, NOT latest (2.10.3) - confirmed live 2026-08-05
# that 2.10.3 (published the day before this session) referenced image
# tags (elasticsearch:8.19.16-so9, workload-observer:...-1023-release,
# stackpacks: a specific July 29 build, stackgraph-hbase:2.5-8.3.2) that
# Carbide's registry mirror hadn't caught up to yet (confirmed via the
# registry's own /v2/<repo>/tags/list - Harbor returns 403, not 404, for a
# nonexistent tag, so don't read a 403 here as an entitlement problem
# without checking the tag list first). 2.10.2's pinned tags were all
# already mirrored. Re-verify next time this is run - Carbide's mirror will
# have caught up further by then, and a newer chart version may work fine.
helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update

helm upgrade --install \
  --namespace suse-observability \
  --create-namespace \
  --version 2.10.2 \
  --set global.suseObservability.license="${RGS_OBSERVABILITY_LICENSE}" \
  --set global.suseObservability.rancherUrl="${RGS_RANCHER_URL}" \
  --set global.suseObservability.baseUrl="${RGS_OBSERVABILITY_BASE_URL}" \
  --set global.suseObservability.sizing.profile="10-nonha" \
  --set global.suseObservability.adminPassword="${RGS_OBSERVABILITY_ADMIN_PASSWORD}" \
  --set global.imageRegistry="${RGS_CARBIDE_REGISTRY}" \
  --timeout 25m \
  --wait \
  suse-observability \
  suse-observability/suse-observability

echo "=== Creating Ingress ==="
cat <<INGRESS_EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: suse-observability-ingress
  namespace: suse-observability
spec:
  tls:
    - hosts:
        - ${RGS_OBSERVABILITY_HOSTNAME}
      secretName: tls-observability-ingress
  rules:
    - host: ${RGS_OBSERVABILITY_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: suse-observability-router
                port:
                  number: 8080
INGRESS_EOF

echo "=== Creating Let's Encrypt Certificate ==="
cat <<CERT_EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: observability-tls
  namespace: suse-observability
spec:
  secretName: tls-observability-ingress
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  commonName: ${RGS_OBSERVABILITY_HOSTNAME}
  dnsNames:
  - ${RGS_OBSERVABILITY_HOSTNAME}
CERT_EOF

echo "=== Done. Pod status: ==="
kubectl get pods -n suse-observability
echo "Login at https://${RGS_OBSERVABILITY_HOSTNAME} with username 'admin' and the password you set in RGS_OBSERVABILITY_ADMIN_PASSWORD."
