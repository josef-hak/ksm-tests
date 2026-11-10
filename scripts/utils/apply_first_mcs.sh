#!/usr/bin/env bash
set -euo pipefail

# Apply the MultiClusterServices listed in `applyFirstMultiClusterServices:`
# before the rest of them exist, and run each one's checks.
#
# Why a scenario would want that: `dependsOn` naming an MCS that does not exist
# is a different state from one that exists and is not deployed yet, and only
# the first can be reached by creating the dependent first. KCM reports it on
# MultiClusterServiceDependencyValidation and rolls nothing out, and neither
# half of that can be asserted when everything is created in one apply.
#
# Called by deploy_mcs_group.sh, which then applies the whole manifest as it
# always has. That second apply covers these objects again and is a no-op for
# them -- which is the point: nothing downstream has to know this ran.
#
# No-op unless the scenario declares the block, so every existing scenario
# reaches the same apply it reached before.

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
is_multi_mcs || die "applyFirstMultiClusterServices needs several MultiClusterServices"

export KUBECONFIG="$KUBECONFIG_MGMT"
require_cluster
ensure_workdir

COUNT="$(apply_first_count)"
(( COUNT > 0 )) || exit 0

step "Scenario $SCENARIO: applying $COUNT MultiClusterService(s) ahead of the rest"

for (( i = 0; i < COUNT; i++ )); do
    key="$(block_name applyFirstMultiClusterServices "$i")"
    obj="$(block_object_name applyFirstMultiClusterServices "$i")"
    part="$WORKDIR/mcs-first-$i.yaml"

    MCS_IDX="$(mcs_index_of "$key")" render_mcs "$part" initial
    cat "$part"
    kube apply -f "$part"
    log "Applied $obj, its dependencies do not exist yet"

    run_checks ".applyFirstMultiClusterServices[$i]" "$obj" "$MCS_TIMEOUT"
done

ok "The MultiClusterServices applied first behaved as the scenario expects"
