# envs/stg

Targets: cluster `k3d-app` (context `k3d-app`), namespace `stg`.

Promotion into this folder is **gated**: the workflow job that writes to this
folder is bound to the `stg` GitHub Environment and pauses for a required
reviewer (team-platform) before it commits (D-04). ArgoCD's auto-sync stays
ON regardless — the gate is on the commit that changes what ArgoCD sees, not
on ArgoCD's own reconciliation.
