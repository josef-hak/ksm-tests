#!/usr/bin/env bash
set -euo pipefail

# Scale the projectsveltos components KCM does not need down to zero, through a
# flux postRenderer on the provider's HelmRelease.
#
# The chart has an `enabled` flag for four components -- config/sveltos-values.yaml
# turns all four off -- and none for the rest: their Deployments in
# templates/deployment.yaml are unconditional and the replica count is a literal
# 1, so no Helm value reaches them. A kustomize patch in
# HelmRelease.spec.postRenderers does: it rewrites the manifests flux applies,
# so the Deployments are created with no replicas rather than scaled afterwards.
#
# Right after the Management, not at the end of the build: KCM creates the
# HelmRelease as it reconciles the Management, and the patch has to be in before
# flux renders. It is a race flux sometimes wins -- then the components come up
# once and the upgrade this patch triggers takes them away again.
#
# KCM keeps it: ReconcileHelmRelease assigns named fields (chartRef, values,
# interval, install, upgrade) and never touches postRenderers, so the patch
# survives every reconcile and every chart upgrade -- unlike `kubectl scale`,
# which the next helm upgrade undoes.
#
# Only Deployments the chart installs can be listed. The sveltos agent is not
# one of them: classifier-manager creates it in whichever cluster sveltos
# registers, so with classifier-manager at zero it is never placed at all.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=scripts/lib/k8s.sh
source "$SCRIPTS_DIR/lib/k8s.sh"

require_cmd kubectl

export KUBECONFIG="$KUBECONFIG_MGMT"

if [[ -z "$SVELTOS_SCALE_ZERO" ]]; then
    log "SVELTOS_SCALE_ZERO is empty -- every projectsveltos component stays up"
    exit 0
fi

step "Waiting for the projectsveltos HelmRelease"
SECONDS=0
until kube get helmrelease projectsveltos -n "$NAMESPACE" >/dev/null 2>&1; do
    (( SECONDS < HELMRELEASE_TIMEOUT )) || die \
        "HelmRelease 'projectsveltos' did not appear in ${HELMRELEASE_TIMEOUT}s. Is projectsveltos in KCM_PROVIDERS?"
    sleep 1
done
log "appeared after ${SECONDS}s"

read -ra components <<< "$SVELTOS_SCALE_ZERO"
PATCH="$ENVDIR/sveltos-postrenderer.yaml"
{
    echo "spec:"
    echo "  postRenderers:"
    echo "    - kustomize:"
    echo "        patches:"
    for name in "${components[@]}"; do
        echo "          - target:"
        echo "              kind: Deployment"
        echo "              name: $name"
        echo "            patch: |"
        echo "              - op: replace"
        echo "                path: /spec/replicas"
        echo "                value: 0"
    done
} > "$PATCH"

step "Patching the HelmRelease to render ${#components[@]} component(s) at zero replicas"
log "${components[*]}"
kube patch helmrelease projectsveltos -n "$NAMESPACE" --type merge --patch-file "$PATCH"

ok "projectsveltos will run only the components KCM needs"
