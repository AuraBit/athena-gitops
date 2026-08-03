<p align="center">
  <img src="docs/assets/athena-logo.svg" alt="Athena logo" width="130">
</p>

<h1 align="center">athena-gitops</h1>

<p align="center">
  GitOps manifests for the <a href="https://github.com/AuraBit">Athena estate</a>. ArgoCD applies what lands here. Nothing else does.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/ArgoCD-declarative%20CD-EF7B4D?logo=argo&logoColor=white" alt="ArgoCD">
  <img src="https://img.shields.io/badge/promotion-folder--per--env-326CE5" alt="folder-per-environment">
</p>

---

This is the deployment source of truth for Athena, an open replica of a
production-grade DevOps estate that runs entirely on a laptop. CI on
[`athena-app`](https://github.com/AuraBit/athena-app) commits image tags
**into** this repo; ArgoCD is the only thing that **applies out of** it.
Nothing here is ever `kubectl apply`'d by hand or by a CI job directly.

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
  diffing branches. The full reasoning is in
  [this repo's ADR-0001](docs/adr/0001-folder-per-environment-and-the-promotion-gate.md).
- **Promotion is gated at the commit, not at reconciliation.** The workflow
  job that writes to `envs/stg` or `envs/prod` is bound to the corresponding
  GitHub Environment and pauses for a required-reviewer approval before it
  commits; `envs/dev` promotes automatically. ArgoCD's auto-sync stays **on**
  everywhere — so drift still gets reverted the way GitOps promises, and the
  human gate sits where it belongs, on the change entering `main`.

## Directory map

```
athena-gitops/
  envs/
    dev/    # k3d-app / namespace dev — auto-promoted
    stg/    # k3d-app / namespace stg — gated on the "stg" GitHub Environment
    prod/   # k3d-app / namespace prod — gated on the "prod" GitHub Environment
  docs/adr/ # decisions governing this repo specifically
```

## What's here today

The environment folders, the lint workflow that guards them, and the ADR
recording the promotion model. ArgoCD Application manifests and the actual
promotion workflow are the next things to land, once the app repo has images
worth promoting.

The rest of the estate: [`athena-infra`](https://github.com/AuraBit/athena-infra)
(clusters, DNS/TLS, LocalStack, governance-as-code) and
[`athena-docs`](https://github.com/AuraBit/athena-docs) (estate-wide ADRs,
diagrams, study notes).

## License

[MIT](LICENSE)
