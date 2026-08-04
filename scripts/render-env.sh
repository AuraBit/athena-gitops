#!/usr/bin/env bash
# render-env.sh — THE canonical render pipeline (Plan 03-08, Task 1; D-28/D-29).
#
# Rendering happens HERE, in this repo, at commit time — never inside ArgoCD.
# ArgoCD syncs plain YAML from envs/<env>/<unit>/all.yaml (D-28: rendered
# manifests pattern), so what runs in a cluster is exactly what a human saw
# in a diff. One canonical implementation exists so a rendered file can never
# differ depending on who produced it: humans and CI both call this script,
# and .github/workflows/render.yml is nothing but a scheduled caller of it.
#
# Usage:
#   scripts/render-env.sh <env> [unit]     # e.g. render-env.sh dev media
#
# Units are discovered from overlays/<env>: the overlay root is the media
# unit (tracer-era layout, kept), and each subdirectory holding a
# kustomization.yaml is a further unit. Each unit selects only its own
# chart templates via `helm template --show-only` so each per-unit rendered
# file (and its own ArgoCD child Application) stays independent.
#
# Determinism is a hard requirement, asserted by CI (render twice, second
# render must produce no diff): helm template is deterministic for this
# chart — no timestamps, no random values, no lookup() calls. If a future
# template introduces non-determinism, strip it here or CI will refuse it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "render-env: ERROR: $*" >&2
  echo "render-env: remediation: run 'scripts/render-env.sh <env> [unit]' from the athena-gitops repo root; envs come from overlays/<env>/ and values-<env>.yaml must exist in charts/athena/." >&2
  exit 1
}

ENV_NAME="${1:-}"
ONLY_UNIT="${2:-}"
[ -n "$ENV_NAME" ] || fail "no environment given"

CHART="charts/athena"
VALUES="$CHART/values.yaml"
ENV_VALUES="$CHART/values-${ENV_NAME}.yaml"
OVERLAY_ROOT="overlays/${ENV_NAME}"
[ -f "$ENV_VALUES" ] || fail "missing $ENV_VALUES"
[ -d "$OVERLAY_ROOT" ] || fail "missing $OVERLAY_ROOT"

command -v helm >/dev/null 2>&1 || fail "helm not on PATH"
command -v kustomize >/dev/null 2>&1 || fail "kustomize not on PATH"

# unit -> (overlay dir, chart template prefix, envs output unit dir)
# The overlay root is the media unit; 'shop' renders into the
# 'athena-shop' envs directory (naming set by Plans 03-04/03-06).
unit_overlay() {
  case "$1" in
    media)      echo "$OVERLAY_ROOT" ;;
    datastores) echo "$OVERLAY_ROOT/datastores" ;;
    shop)       echo "$OVERLAY_ROOT/shop" ;;
    *) fail "unknown unit '$1'" ;;
  esac
}
unit_prefix() {
  case "$1" in
    media)      echo "media" ;;
    datastores) echo "datastores" ;;
    shop)       echo "shop" ;;
  esac
}
unit_outdir() {
  case "$1" in
    media)      echo "envs/${ENV_NAME}/media" ;;
    datastores) echo "envs/${ENV_NAME}/datastores" ;;
    shop)       echo "envs/${ENV_NAME}/athena-shop" ;;
  esac
}

discover_units() {
  # Root kustomization = media unit; subdirs with kustomization.yaml = more units.
  [ -f "$OVERLAY_ROOT/kustomization.yaml" ] && echo "media"
  for d in "$OVERLAY_ROOT"/*/; do
    [ -f "${d}kustomization.yaml" ] || continue
    basename "$d"
  done
}

render_unit() {
  local unit="$1"
  local overlay prefix outdir tmpl out err
  overlay="$(unit_overlay "$unit")"
  prefix="$(unit_prefix "$unit")"
  outdir="$(unit_outdir "$unit")"

  # One helm invocation PER template, not one per unit: helm errors with
  # "could not find template" when a --show-only target renders EMPTY
  # (e.g. prod's `{{- if .Values.shop.loadgenerator.enabled }}` guard with
  # the flag off). The file demonstrably exists — we globbed it — so that
  # specific failure means "conditionally empty this env" and is skipped;
  # any other helm failure still fails loudly.
  : > "$overlay/rendered-input.yaml"
  local found=0
  for tmpl in "$CHART"/templates/"$prefix"-*.yaml; do
    [ -e "$tmpl" ] || fail "no chart templates match ${prefix}-*.yaml for unit '$unit'"
    found=1
    if out="$(helm template athena "$CHART" -f "$VALUES" -f "$ENV_VALUES" \
        --show-only "templates/$(basename "$tmpl")" 2>&1)"; then
      printf '%s\n' "$out" >> "$overlay/rendered-input.yaml"
    else
      if printf '%s' "$out" | grep -q "could not find template"; then
        echo "render-env: note: $(basename "$tmpl") renders empty for '$ENV_NAME' (conditional off) — skipped"
      else
        printf '%s\n' "$out" >&2
        fail "helm template failed for env '$ENV_NAME' unit '$unit' template '$(basename "$tmpl")'"
      fi
    fi
  done
  [ "$found" -eq 1 ] || fail "no chart templates match ${prefix}-*.yaml for unit '$unit'"

  mkdir -p "$outdir"
  kustomize build "$overlay" > "$outdir/all.yaml" \
    || fail "kustomize build failed for env '$ENV_NAME' unit '$unit'"
  echo "render-env: rendered $ENV_NAME/$unit -> $outdir/all.yaml"
}

if [ -n "$ONLY_UNIT" ]; then
  render_unit "$ONLY_UNIT"
else
  UNITS="$(discover_units)"
  [ -n "$UNITS" ] || fail "no units discovered under $OVERLAY_ROOT"
  for u in $UNITS; do
    render_unit "$u"
  done
fi
