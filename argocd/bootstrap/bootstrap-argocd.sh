#!/usr/bin/env bash
# bootstrap-argocd.sh — one-shot, idempotent ArgoCD hub-and-spoke bootstrap
# (Plan 03-01, Task 2; D-32).
#
# Installs ArgoCD on the platform cluster ONLY (CD-01 hub-and-spoke — the
# app cluster never runs its own ArgoCD components, asserted live by this
# task's acceptance criteria), registers the app cluster as a remote
# destination via a declarative Secret (ArgoCD's own documented mechanism —
# argocd.argoproj.io/secret-type: cluster), and applies the dev root
# Application. After this one-shot run, "Argo manages Argo" (D-32):
# ArgoCD's own config is thereafter synced from this repo's argocd/apps/dev
# directory (which includes this script's own root Application, applied
# once here and self-managed from git after that), not re-applied by this
# script on every run.
#
# Safe to run twice: every step is idempotent (helm upgrade --install,
# kubectl apply, SA/RBAC/Secret recreation-safe).
#
# RENDER PIPELINE: scripts/render-env.sh is THE canonical implementation
# (Plan 03-08, Task 1) — one overlay directory per deployable unit, per env
# (Plan 03-04, Task 3), each unit selected via `helm template --show-only`
# and folded through its overlay into envs/<env>/<unit>/all.yaml. Humans
# run `scripts/render-env.sh <env> [unit]`; CI runs the same script from
# .github/workflows/render.yml. The command sequence formerly duplicated in
# this header lives only in that script now, so a rendered file can never
# differ depending on who produced it.
#
# ArgoCD chart pin: argo/argo-cd chart 10.2.2 (appVersion v3.4.6). DEVIATION
# from RESEARCH.md/CLAUDE.md's "pin to 3.5.0 directly" recommendation
# (Rule 1 — bug/blocker, found live at execution): ArgoCD app v3.5.0 GA'd
# TODAY (2026-08-04) per RESEARCH.md's own live GitHub API query, but the
# argo-helm CHART repo (a separate release cadence from the app itself) has
# not yet packaged a chart bundling it — `helm search repo argo/argo-cd
# --versions` tops out at chart 10.2.2 / appVersion v3.4.6, confirmed live
# against both the Helm repo index and the argo-helm GitHub releases API
# this session. This has no functional impact on D-28 (rendered manifests
# means ArgoCD never renders Helm charts itself, so the "Helm v4 bundled
# since 3.5" detail CLAUDE.md flags is moot for this estate either way).
# Re-check `helm search repo argo/argo-cd --versions | head -1` before
# reusing this script once a 3.5.x-bundling chart ships, and bump
# ARGOCD_CHART_VERSION below.
#
# Never echoes the app-cluster ServiceAccount bearer token or the ArgoCD
# initial admin password (T-03-01/T-03-04) — this script prints only the
# kubectl command a human runs to retrieve the admin password themselves.
#
# Usage: bash argocd/bootstrap/bootstrap-argocd.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

ARGOCD_CHART_REPO="https://argoproj.github.io/argo-helm"
ARGOCD_CHART_VERSION="10.2.2"
ARGOCD_NAMESPACE="argocd"
PLATFORM_CTX="k3d-platform"
APP_CTX="k3d-app"
APP_MANAGER_SA="argocd-manager"
APP_MANAGER_SA_NS="kube-system"

info()  { printf '[bootstrap-argocd] %s\n' "$1"; }
ok()    { printf '\033[32m[bootstrap-argocd] OK: %s\033[0m\n' "$1"; }
fail()  { printf '\033[31m[bootstrap-argocd] FAIL: %s\033[0m\n' "$1"; }

for ctx in "${PLATFORM_CTX}" "${APP_CTX}"; do
  if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "${ctx}"; then
    fail "kube-context '${ctx}' not found in kubeconfig"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 1. Install ArgoCD on the platform cluster ONLY (CD-01 hub-and-spoke).
# ---------------------------------------------------------------------------
info "installing ArgoCD ${ARGOCD_CHART_VERSION} on ${PLATFORM_CTX} (namespace ${ARGOCD_NAMESPACE})"
helm repo add argo "${ARGOCD_CHART_REPO}" >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --kube-context "${PLATFORM_CTX}" \
  --namespace "${ARGOCD_NAMESPACE}" \
  --create-namespace \
  --version "${ARGOCD_CHART_VERSION}" \
  --wait --timeout 5m

ok "ArgoCD helm release reconciled"

# ---------------------------------------------------------------------------
# 2. Mint a long-lived ServiceAccount token on the APP cluster for ArgoCD's
#    cluster-admin access (ArgoCD's own documented registration mechanism).
#    A plain `kubectl create token` is short-lived by design and unsuitable
#    for a persistent cluster-secret; the annotated-Secret form is what
#    produces a non-expiring token here.
# ---------------------------------------------------------------------------
info "provisioning ${APP_MANAGER_SA} ServiceAccount + cluster-admin binding on ${APP_CTX}"
kubectl --context "${APP_CTX}" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_MANAGER_SA}
  namespace: ${APP_MANAGER_SA_NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${APP_MANAGER_SA}-cluster-admin
subjects:
  - kind: ServiceAccount
    name: ${APP_MANAGER_SA}
    namespace: ${APP_MANAGER_SA_NS}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: ${APP_MANAGER_SA}-token
  namespace: ${APP_MANAGER_SA_NS}
  annotations:
    kubernetes.io/service-account.name: ${APP_MANAGER_SA}
type: kubernetes.io/service-account-token
EOF

info "waiting for the ServiceAccount token to be populated (Kubernetes fills this in asynchronously)"
APP_TOKEN=""
for _ in $(seq 1 30); do
  APP_TOKEN="$(kubectl --context "${APP_CTX}" -n "${APP_MANAGER_SA_NS}" get secret "${APP_MANAGER_SA}-token" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  [ -n "${APP_TOKEN}" ] && break
  sleep 2
done
if [ -z "${APP_TOKEN}" ]; then
  fail "app-cluster ServiceAccount token never populated — check \`kubectl --context ${APP_CTX} -n ${APP_MANAGER_SA_NS} describe secret ${APP_MANAGER_SA}-token\`"
  exit 1
fi

APP_CA="$(kubectl --context "${APP_CTX}" -n "${APP_MANAGER_SA_NS}" get secret "${APP_MANAGER_SA}-token" -o jsonpath='{.data.ca\.crt}' 2>/dev/null)"
if [ -z "${APP_CA}" ]; then
  fail "app-cluster CA data missing from ${APP_MANAGER_SA}-token"
  exit 1
fi
ok "app-cluster ServiceAccount token + CA retrieved (never printed)"

# ---------------------------------------------------------------------------
# 3. Resolve the app cluster's authoritative in-network server URL.
#
# DEVIATION (Rule 1 — bug, found live at execution): Task 1's own probe used
# the k3d-app-serverlb container's IP (its docker-network reachability test
# only needs network-level TCP+TLS-handshake success, and a 401 response
# proves that regardless of which cert SAN is presented). ArgoCD's cluster
# registration is stricter — it validates the app cluster's real serving
# certificate against the caData this script reads from the app cluster's
# own ServiceAccount token Secret, and that certificate's SAN list does NOT
# include the serverlb's address: `k3d-app-serverlb` is a pure TCP-passthrough
# nginx proxy (confirmed live, estate/athena-infra/clusters — no TLS
# termination happens there), so the k3s apiserver process never has a
# reason to include the serverlb's own IP in its serving cert's SAN list.
# The address that IS in that SAN list is the k3s SERVER NODE's own IP
# (k3d-app-server-0), proven live: `kubectl -n argocd get application
# media-dev -o yaml` initially reported `x509: certificate is valid for
# 0.0.0.0, 10.43.0.1, 127.0.0.1, 172.18.0.2, 172.18.0.6, ::1, not
# 172.18.0.3` (the serverlb IP) before this fix.
#
# Never hard-coded: docker assigns this address at container-creation time.
# ---------------------------------------------------------------------------
APP_SERVER_NODE_IP="$(docker inspect k3d-app-server-0 --format '{{(index .NetworkSettings.Networks "k3d-app").IPAddress}}' 2>/dev/null)" || APP_SERVER_NODE_IP=""
if [ -z "${APP_SERVER_NODE_IP}" ]; then
  fail "could not resolve k3d-app-server-0's IP on the k3d-app network — has estate/athena-infra/scripts/apply-coredns-custom.sh (Task 1) been run yet?"
  exit 1
fi
APP_CLUSTER_SERVER="https://${APP_SERVER_NODE_IP}:6443"
info "app cluster server URL (registered as ArgoCD's remote destination): ${APP_CLUSTER_SERVER}"

# ---------------------------------------------------------------------------
# 4. Register the app cluster with ArgoCD via the declarative cluster
#    Secret template. Substitution happens entirely in a shell variable —
#    the substituted content is piped straight into `kubectl apply`,  never
#    written to a file or printed.
# ---------------------------------------------------------------------------
info "registering app cluster with ArgoCD (${PLATFORM_CTX}, namespace ${ARGOCD_NAMESPACE})"
sed \
  -e "s#__APP_CLUSTER_SERVER__#${APP_CLUSTER_SERVER}#" \
  -e "s#__APP_CLUSTER_TOKEN__#${APP_TOKEN}#" \
  -e "s#__APP_CLUSTER_CA__#${APP_CA}#" \
  "${SCRIPT_DIR}/app-cluster-secret.yaml" \
  | kubectl --context "${PLATFORM_CTX}" apply -f - >/dev/null
ok "app-cluster-secret applied (cluster registered as a remote destination)"

# ---------------------------------------------------------------------------
# 5. Apply the dev root Application (app-of-apps). From here on, "Argo
#    manages Argo" (D-32): this Application's own source path
#    (argocd/apps/dev) includes root.yaml itself, so ArgoCD's own
#    self-managed sync keeps it in sync with git going forward — this
#    script applies it exactly once to bootstrap that loop, never again on
#    a re-run (kubectl apply is idempotent regardless).
# ---------------------------------------------------------------------------
info "applying root-dev Application"
kubectl --context "${PLATFORM_CTX}" -n "${ARGOCD_NAMESPACE}" apply -f "${REPO_ROOT}/argocd/apps/dev/root.yaml"
ok "root-dev Application applied"

info "bootstrap complete. Next steps for a human:"
info "  - Retrieve the ArgoCD initial admin password (never printed by this script):"
info "      kubectl --context ${PLATFORM_CTX} -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
info "  - Check Application health: kubectl --context ${PLATFORM_CTX} -n ${ARGOCD_NAMESPACE} get applications"
ok "bootstrap-argocd.sh complete"
