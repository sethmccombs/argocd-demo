# argocd-demo

A self-managing Argo CD installation provisioned entirely from this Git
repository (GitOps "app of apps"), with:

- **Self-management** – Argo CD reconciles its own configuration and lifecycle
  from this repo.
- **Monitoring** – Prometheus Operator (`kube-prometheus-stack`) with
  `ServiceMonitor`s, Grafana dashboards, and alert rules for Argo CD.
- **SSO** – GitHub login via the bundled Dex `github` connector.
- **Multi-environment delivery** – an `ApplicationSet` that fans a single demo
  application out across `dev`, `staging`, and `prod`.

Target environment: a single-cluster (kind / minikube) demo install.

## Repository layout

```
argocd-demo/
├── argocd/                         # Argo CD itself (synced by the argocd Application)
│   ├── v3.5.4/install.yaml         # vendored upstream install manifest
│   ├── base/                       # AppProject, SSO config, RBAC
│   └── monitoring/                 # Prometheus values, ServiceMonitors, dashboards, alerts
├── applications/                   # app-of-apps tree
│   ├── root.yaml                   # root Application -> applications/
│   ├── core/                       # argocd + prometheus + argocd-monitoring Applications
│   └── product/                    # ApplicationSet for dev/staging/prod
├── examples/product/               # the demo workload (base + env overlays)
└── argocdmanifest.sh               # helper to (re-)vendor an Argo CD release
```

### How it fits together

1. `applications/root.yaml` (app of apps) points at `applications/` and owns the
   `argocd`, `prometheus`, `argocd-monitoring`, and product `ApplicationSet`
   resources.
2. The `argocd` Application points back at `argocd/`, so Argo CD installs and
   maintains **itself**.
3. The `prometheus` Application installs `kube-prometheus-stack` into the
   `monitoring` namespace. Its Argo CD `ServiceMonitor`s, Grafana dashboard, and
   alerts live in the separate `argocd-monitoring` Application so they never
   wait on Grafana health.
4. The product `ApplicationSet` renders one Application per environment from the
   `examples/product/overlays/*` directories.

## Prerequisites

- A running single-node cluster (`kind create cluster` or `minikube start`).
- `kubectl`, `kustomize`, and the `argocd` CLI.

## Bootstrap

Bootstrap is two steps because the `core` AppProject must exist before the
Applications that reference it. After bootstrap, Argo CD keeps everything in
sync from Git (self-managing).

```bash
# 1. Install Argo CD + the core AppProject + SSO/RBAC config directly.
#    - The vendored manifest does not create the namespace, so create it first.
#    - --server-side is required: the applicationsets CRD exceeds the
#      client-side apply annotation limit (262144 bytes).
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -k argocd/

# 2. Create the SSO client secret (do NOT commit this). The login page will
#    keep working without it, but GitHub login will not until it is set.
kubectl -n argocd create secret generic argocd-secret \
  --from-literal=dex.github.clientSecret="$GITHUB_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Hand the applications/ tree over to Argo CD (app of apps).
kubectl apply -f applications/root.yaml

# 4. Watch it converge.
kubectl -n argocd get applications
```

`root` then creates and owns `argocd`, `prometheus`, and the product
`ApplicationSet`; the `argocd` Application adopts the install from step 1.

## Access

```bash
# Retrieve the initial admin password (used only for the first login).
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Port-forward the UI/API.
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open <https://localhost:8080>.

## GitHub SSO setup

1. Create a GitHub **OAuth App** (Settings → Developer settings → OAuth Apps):
   - **Homepage URL:** `https://localhost:8080`
   - **Authorization callback URL:** `https://localhost:8080/api/dex/callback`
2. Put the client ID in `argocd/base/argocd-cm.yaml` (`dex.config`).
3. Store the client secret out of band (see bootstrap step 1) as
   `dex.github.clientSecret` on the `argocd-secret` Secret.
4. Map GitHub orgs/teams to Argo CD roles in `argocd/base/argocd-rbac-cm.yaml`.

## Monitoring

The `monitoring` namespace runs `kube-prometheus-stack`. Argo CD metrics are
scraped via `ServiceMonitor`s for:

- `argocd-application-controller` (`argocd-metrics:8082`)
- `argocd-server` (`argocd-server-metrics:8083`)
- `argocd-repo-server` (`argocd-repo-server:8084`)
- `argocd-applicationset-controller` (`argocd-applicationset-controller:8080`)

Grafana dashboards and `PrometheusRule` alerts for Argo CD are deployed
alongside. Access Grafana:

```bash
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
```

This demo trims the stack for a smaller cluster: the stock Grafana dashboards,
Alertmanager, node-exporter, and kube-state-metrics are disabled, and only the
Argo CD dashboard it ships is loaded. The Argo CD `ServiceMonitor`s, dashboard,
and `PrometheusRule` alerts are deployed by the `argocd-monitoring` Application.

## Verifying the brief

- **Self-managing:** change something under `argocd/`, commit, push — Argo CD
  reports `OutOfSync` then self-heals.
- **Monitoring:** Prometheus → Status → Targets shows all four Argo CD jobs
  `UP`; the Argo CD Grafana dashboard renders; alerts appear under Alerts.
- **SSO:** the Argo CD login page shows a "Log in via GitHub" button and the
  flow authenticates against GitHub.
- **ApplicationSet:** `kubectl -n argocd get applications` lists
  `product-dev`, `product-staging`, `product-prod`.
