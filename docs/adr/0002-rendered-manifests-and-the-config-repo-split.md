# 0002. Rendered Manifests and the Config-Repo Split

* Status: accepted
* Date: 2026-08-04
* Deciders: Yahia Tarek (YahiaEng)
* Tier: full-madr

## Context and Problem Statement

ArgoCD can render Helm charts itself at sync time, or it can sync plain YAML
that was rendered earlier, at commit time. The choice decides what a reviewer
actually sees in a diff, what runs in the cluster when a chart or values file
changes, and where a rendering bug surfaces (in a PR, or in production).

## Considered Options

1. **ArgoCD-side Helm rendering** — point Applications at charts/ and let the
   controller run Helm. Rejected: the diff a reviewer approves is a values
   change, not the manifests that will actually apply; a template bug
   surfaces at sync time in the cluster; and the ArgoCD-bundled Helm version
   becomes a hidden rendering dependency (the 3.4→3.5 Helm v4 bundling change
   would have been a silent renderer swap).
2. **Kustomize --enable-helm inflator** — rejected: documented-experimental,
   shells out to a Helm v3 binary specifically (CLAUDE.md's What-NOT-to-Use).
3. **Rendered manifests, committed** (chosen) — `helm template --show-only`
   per unit, piped through the env's Kustomize overlay into
   `envs/<env>/<unit>/all.yaml`; ArgoCD syncs only those files.

## Decision

Render at commit time via one canonical script (`scripts/render-env.sh`);
commit the rendered output; ArgoCD Applications point only at `envs/`.
CI enforces the invariant with a render-check (committed output must match a
fresh render byte-for-byte) rather than a render-push — a live-verified
GitHub limitation (an Integration bypass for the Actions app is silently
dropped by the ruleset API) makes CI-side pushes to protected main
impossible, so rendering rides the committing actor: humans locally, the
bot inside media-ci's handoff job.

## Consequences

* The PR diff IS the cluster diff — approval is informed, drift is legible.
* Rendering bugs fail in CI, never at sync time.
* Every pin/promotion commit carries its rendered consequence — one-commit
  revert restores both.
* Cost: contributors must run the render script (the render-check turns
  forgetting into a red PR, not a broken cluster).
