# athena-gitops

The ArgoCD-watched GitOps manifest repository for the Athena estate
(interview-prep project — see the platform handbook, `athena-docs`, for the
full estate-level story). CI on `athena-app` commits image tags **into**
this repo; ArgoCD is the only thing that **applies out of** it. Nothing here
is ever `kubectl apply`'d by hand or by a CI job directly.

## Promotion model

Trunk-based, **only `main` is protected**, and promotion between
environments is **folder-per-environment** — `envs/dev/`, `envs/stg/`,
`envs/prod/` — not branch-per-environment.

- **Environments are folders, never branches.** `envs/dev`, `envs/stg`, and
  `envs/prod` all live on `main`; ArgoCD Applications point at each folder
  independently. Promotion between environments is a commit that changes
  what's *in* a folder, not a merge between long-lived branches.
- **Branch-per-environment was considered and rejected** as a documented
  GitOps anti-pattern: environment branches drift from each other over time,
  promotion degenerates into error-prone cherry-picking, and every
  environment branch accumulates a permanent diff against the others that
  nobody can fully explain months later. Folder-per-environment on a single
  protected branch avoids all three failure modes by construction — there is
  exactly one source of truth (`main`), and "what's running in stg" is
  always answerable by looking at one folder's current contents, not by
  diffing branches. The full reasoning, with the interview-ready "why not
  branches" answer, is recorded as an ADR in `athena-docs`.
- **Promotion gating (D-04):** the workflow job that writes to `envs/stg` or
  `envs/prod` is bound to the corresponding GitHub Environment and pauses
  for a required-reviewer approval before it commits; `envs/dev` promotes
  automatically. ArgoCD's auto-sync stays **on** everywhere — the gate is on
  the commit, not on ArgoCD's reconciliation, which preserves the drift-revert
  demo Phase 3 builds on top of this repo.

## Directory map

```
athena-gitops/
  envs/
    dev/    # k3d-app / namespace dev — auto-promoted
    stg/    # k3d-app / namespace stg — gated on the "stg" GitHub Environment
    prod/   # k3d-app / namespace prod — gated on the "prod" GitHub Environment
  docs/adr/ # decisions governing this repo specifically
```

## Status

This repository is currently a skeleton — the `envs/*` folders and
`docs/adr/` are the only structure Plan 04 seeds here. ArgoCD Application
manifests and the actual promotion workflow land in Phase 3.
