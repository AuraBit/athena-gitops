# envs/dev

Targets: cluster `k3d-app` (context `k3d-app`), namespace `dev`.

Promotion into this folder is **automatic** — CI on `athena-app` commits new
image tags directly here on a successful build/scan of `main`. No GitHub
Environment reviewer gates this folder (D-04 gates stg/prod only; dev exists
to prove the full push -> build -> gitops-commit -> ArgoCD-sync path fast).
