# 0001. Folder-per-Environment and Where the Promotion Gate Attaches

* Status: accepted
* Date: 2026-08-03
* Deciders: Yahia Tarek (YahiaEng)
* Tier: short-form

## Context

This repo is the GitOps source of truth ArgoCD watches. It needs a layout
that supports promoting the same manifests through dev, stg, and prod
without branch drift, and a gating design that lets a human approve
higher-risk promotions without breaking ArgoCD's own reconciliation model.

## Decision

Environments are **folders**, not branches: `envs/dev/`, `envs/stg/`,
`envs/prod/`, all living on `main`, the only branch this repo protects. A
promotion is a commit that changes what a folder contains, not a merge
between long-lived environment branches — the estate-wide trunk-based/
folder-per-environment decision (`athena-docs` ADR-0004) is enacted here
concretely. `dev` promotes automatically (no gate); `stg` and `prod` are
gated.

The gate attaches to the **promotion-commit job** — the CI job that writes
to `envs/stg/` or `envs/prod/` is bound to the corresponding GitHub
Environment and pauses for a `team-platform` reviewer's approval before
that write happens — not to ArgoCD itself. ArgoCD's own auto-sync stays ON
in every environment, with no environment-level pause built into ArgoCD's
configuration. This is a deliberate design choice, not an oversight: gating
ArgoCD's sync would also block the drift-revert demonstration Phase 3
depends on (proving ArgoCD reverts a manual, out-of-band change back to
what git says), which needs auto-sync active everywhere at all times to be
meaningful.

## Consequences

* A reviewer approving a stg/prod promotion is approving *what commit gets
  written to the folder*, not approving *whether ArgoCD is allowed to
  sync it* — once the commit lands, sync is immediate and automatic, same
  as dev.
* The promotion workflow prints the manifest diff in its run summary,
  because the approver's decision needs to be about content, not blind
  trust in the job that produced it.
* The same Environment-gating pattern (bind the job that performs the
  risky write to a GitHub Environment, not the downstream reconciler) is
  reused for `terraform apply` jobs on `athena-infra` in Phase 2 — this ADR
  establishes the pattern once rather than re-deciding it per repo.
* Because this repo carries no CI pipeline of its own beyond the seed lint
  workflow, and its bot commit path (Phase 3) must stay fast, no merge
  queue is configured here (see `athena-app` ADR-0001 for the contrasting
  decision and why).
