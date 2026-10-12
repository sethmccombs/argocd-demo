# AGENTS.md — argocd-demo

## Repository
Self-managing Argo CD environment (GitOps "app of apps") with Prometheus
monitoring, GitHub SSO (Dex), and an ApplicationSet for east/west regions.
Part of an Akuitiy take-home; `kargo-demo` is a sibling repo for Kargo (later).
Target: single-cluster local demo (Docker Desktop / kind).

## Git workflow (IMPORTANT — always follow)
- NEVER commit or push to `main`. `main` only changes via PR merge.
- Work on short-lived feature branches: `feat/<topic>` or `fix/<topic>`.
- Push the branch and open a PR; do not self-merge to `main`.
- Pull/rebuild off `main` before branching; keep commits small and atomic.

## Validate before committing
```bash
kustomize build argocd
kustomize build applications
kustomize build argocd/monitoring
helm template kps prometheus-community/kube-prometheus-stack \
  --version 91.9.0 -f argocd/monitoring/values/prometheus-values.yaml
```

## Layout
- `argocd/`           Argo CD install (vendored `v3.5.4`) + `base` (AppProject,
                      SSO/rbac patches) + `monitoring` (Helm values, Argo CD
                      ServiceMonitors, Grafana dashboard, PrometheusRule).
- `applications/`     App-of-apps: `root` -> `core` (argocd, prometheus,
                      argocd-monitoring) + `product` (ApplicationSet east/west).
- `examples/product/` Demo workload: base manifest + overlays per environment.
- `argocdmanifest.sh` Re-vendor the Argo CD install manifest. Always pin a
                      version; never use `stable`.

## Known constraints / gotchas
- Keep the `namespace: argocd` transformer in `argocd/kustomization.yaml`; the
  vendored `install.yaml` omits `metadata.namespace` on most resources.
- CRDs require server-side apply (`kubectl apply --server-side --force-conflicts`);
  client-side apply hits a 262144-byte annotation limit on the apps CRDs.
- prometheus-operator admission webhooks are disabled; re-enabling makes the
  Argo CD sync hang on Helm hook resources.
- Control-plane monitors (kubeEtcd/kubeScheduler/kubeControllerManager/kubeProxy/
  coreDns) are disabled — no kube-system access needed on a local cluster.
- Keep the stack trimmed on small clusters: default Grafana dashboards off,
  optional components (alertmanager/node-exporter/kube-state-metrics) off, and
  relaxed probe timeouts to avoid restart churn.
- Argo CD monitoring config is its own `argocd-monitoring` Application so it
  never blocks on Grafana health.

## Secrets / SSO
- Never commit secrets or credentials. The Dex GitHub clientSecret is injected
  out-of-band into the `argocd-secret` Secret (key `dex.github.clientSecret`).
- `argocd/base/argocd-cm-patch.yaml` holds `REPLACE_WITH_GITHUB_CLIENT_ID` and
  org placeholders; fill these in for real GitHub login.
- `.idea/`, `secrets/`, `.env`, and `*.local.yaml` are gitignored.

## Bootstrap (fresh cluster)
```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -k argocd/
kubectl -n argocd create secret generic argocd-secret \
  --from-literal=dex.github.clientSecret=dummy --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
kubectl apply -f applications/root.yaml
```