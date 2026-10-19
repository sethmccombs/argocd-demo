# argocd-demo

A self-managing Argo CD installation provisioned entirely from this Git
repository (GitOps "app of apps"), with:

- **Self-management** – Argo CD reconciles its own configuration and lifecycle
  from this repo.
- **Monitoring** – Prometheus Operator (`kube-prometheus-stack`) with
  `ServiceMonitor`s, Grafana dashboards, and alert rules for Argo CD.
- **SSO** – GitHub login via the bundled Dex `github` connector.
- **Kargo delivery** – application promotion to `dev`/`east`/`west` is owned by
  Kargo; see the sibling [kargo-demo](https://github.com/sethmccombs/kargo-demo)
  repo, which uses an Argo CD `ApplicationSet` for the demo application.

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
│   └── core/                       # argocd + cert-manager + prometheus + argocd-monitoring
├── img/                            # excalidraw diagram for docs
└── argocdmanifest.sh               # helper to (re-)vendor an Argo CD release
```

### How it fits together

1. `applications/root.yaml` (app of apps) points at `applications/` and owns the
   `argocd`, `cert-manager`, `prometheus`, and `argocd-monitoring` resources.
2. The `argocd` Application points back at `argocd/`, so Argo CD installs and
   maintains **itself**.
3. The `prometheus` Application installs `kube-prometheus-stack` into the
   `monitoring` namespace. Its Argo CD `ServiceMonitor`s, Grafana dashboard, and
   alerts live in the separate `argocd-monitoring` Application so they never
   wait on Grafana health.
4. `cert-manager` is GitOps-managed here (a Kargo prerequisite); the `product`
   application's lifecycle and its `dev`/`east`/`west` `ApplicationSet` are owned
   by Kargo in the `kargo-demo` repository.

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

`root` then creates and owns `argocd`, `cert-manager`, `prometheus`, and
`argocd-monitoring`; the `argocd` Application adopts the install from step 1.
Product delivery is owned by Kargo (see `kargo-demo`).

## Access

The cluster runs on `bazzite` (KIND). Services are published on the tailnet
with `tailscale serve`:

| Service   | Tailnet URL                                 | Backend (bazzite)          |
|-----------|---------------------------------------------|----------------------------|
| Argo CD   | `https://bazzite.tailc1546e.ts.net`         | `https+insecure://localhost:30443` |
| Kargo     | `https://bazzite.tailc1546e.ts.net:8443`    | `http://localhost:31443`   |
| Grafana   | `https://bazzite.tailc1546e.ts.net:9443`    | `http://localhost:32443`   |

```bash
tailscale serve --bg --https=443 https+insecure://localhost:30443
tailscale serve --bg --https=8443 http://localhost:31443
tailscale serve --bg --https=9443 http://localhost:32443
```

Retrieve the initial admin password (used only for the first login):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

The KIND cluster is created from `argocd-kind.yaml`, which fixes the API port
at 6443 and maps the three NodePorts to the host.

## GitHub SSO setup

1. Create a GitHub **OAuth App** (Settings → Developer settings → OAuth Apps):
   - **Homepage URL:** `https://bazzite.tailc1546e.ts.net`
   - **Authorization callback URL:** `https://bazzite.tailc1546e.ts.net/api/dex/callback`
2. The client ID is in `argocd/base/argocd-cm-patch.yaml` (`dex.config`).
3. Store the client secret out of band (see bootstrap step 1) as
   `dex.github.clientSecret` on the `argocd-secret` Secret.
4. Map GitHub orgs/teams to Argo CD roles in `argocd/base/argocd-rbac-cm-patch.yaml`.
5. Dex also serves a static `kargo` OIDC client (`staticClients` in
   `argocd/base/argocd-cm-patch.yaml`) that Kargo uses for SSO. Its redirect
   URI is `https://bazzite.tailc1546e.ts.net:8443/login`.

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
- **Kargo delivery (sibling repo):** `kubectl -n argocd get applications` lists
  `kargo-product-dev`, `kargo-product-east`, `kargo-product-west` (created by the
  `kargo-product` ApplicationSet) which Kargo promotes through the pipeline in
  `kargo-demo`.
