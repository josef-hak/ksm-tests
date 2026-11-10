#!/usr/bin/env bash
set -euo pipefail

# Delete the MultiClusterServices in the order `removeMultiClusterServices:`
# gives, running each entry's checks after its delete.
#
# The default teardown goes backwards through the declaration list, which is
# dependency-safe by construction and therefore never meets the refusal: KCM
# holds a MultiClusterService back while another still depends on it, and the
# only way to see that is to ask for the wrong one first.
#
#   removeMultiClusterServices:
#     - name: certs          # asked for first, while two still depend on it
#       checks:
#         - present: true
#           forSeconds: 30
#     - name: workload       # no checks -- wait for it to go, as the default does
#     - name: certs          # it was already asked for; watch it follow
#       delete: false
#       checks:
#         - absent: true
#
# An entry may name the same MCS twice: the first asks, the second waits. With
# `delete: false` nothing is deleted and only the checks run.
#
# Called by remove_services.sh before its own loop. That loop then finds the
# objects gone and does what it always did for an already-absent MCS -- verify
# no ServiceSet outlived it -- so the ServiceSet, helm release, workload and
# ServiceTemplate checks all still run, for every MCS, exactly as before.
#
# No-op unless the scenario declares the block.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=scripts/lib/k8s.sh
source "$SCRIPTS_DIR/lib/k8s.sh"
# shellcheck source=scripts/lib/services.sh
source "$SCRIPTS_DIR/lib/services.sh"
# shellcheck source=scripts/lib/checks.sh
source "$SCRIPTS_DIR/lib/checks.sh"

require_cmd kubectl jq
require_yq

check_scenario

export KUBECONFIG="$KUBECONFIG_MGMT"
require_cluster

COUNT="$(removal_count)"
(( COUNT > 0 )) || exit 0

step "Scenario $SCENARIO: removing $COUNT MultiClusterService(s) in the order the scenario asks for"

for (( i = 0; i < COUNT; i++ )); do
    obj="$(block_object_name removeMultiClusterServices "$i")"

    if [[ "$(block_flag removeMultiClusterServices "$i" delete)" == "false" ]]; then
        log "── $obj: checks only, no delete"
    elif resource_exists MultiClusterService "$obj"; then
        step "Deleting MultiClusterService '$obj'"
        # --wait=false throughout: whether the delete completes is the thing
        # under test here, so it must not be this script that blocks on it.
        kube delete multiclusterservice "$obj" --wait=false
    else
        log "── $obj: already gone"
    fi

    if (( $(checks_count ".removeMultiClusterServices[$i]") > 0 )); then
        run_checks ".removeMultiClusterServices[$i]" "$obj" "$REMOVE_TIMEOUT"
    else
        # No checks means the plain teardown expectation: it goes away.
        wait_for_absence MultiClusterService "$obj" "" "$REMOVE_TIMEOUT" 5 \
            || die "MultiClusterService '$obj' never disappeared"
    fi
done

ok "Ordered removal behaved as the scenario expects"
