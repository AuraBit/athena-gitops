# 0003. App-of-Apps Granularity and Sync Policy

* Status: accepted
* Date: 2026-08-04
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

One ArgoCD Application per environment, per deployable unit, or per service?
And should prod's sync policy differ from dev's? Granularity decides blast
radius, status legibility, and how promotion maps onto git.

## Considered Options

1. **One Application per environment** — rejected: a broken shop template
   would gate media's sync; one health status hides which unit regressed.
2. **One Application per microservice** — rejected: 13+ Applications per env
   is ApplicationSet territory (Phase 7's per-service matrix may revisit);
   today it triples ceremony with no promotion benefit, since promotion
   operates on units.
3. **One root per env + one child per deployable unit** (chosen): media,
   datastores, athena-shop under root-{dev,stg,prod}.

## Decision

App-of-apps with per-unit children; every Application in every environment —
including prod — runs `automated: { selfHeal: true, prune: true }` (D-33).
Prod's protection is the promotion gate (promote.yml + the prod GitHub
Environment's human reviewer), never a half-applied sync policy: once a
commit exists on main, it IS the desired state, and letting prod drift from
an approved main would only manufacture the exact drift class CD-02 exists
to prevent.

## Consequences

* Sync/health status reads per unit; a unit failure cannot block siblings.
* The drift-revert drill (CD-02) holds identically in all three envs.
* Prune means a deleted rendered file is a deleted resource — removal is a
  reviewed git operation like everything else.
