#!/usr/bin/env bash
# One cluster, several scenarios, one after another. No `set -e`: a scenario
# that fails must not take the rest of the run with it -- the point of a serial
# run is many verdicts from one environment.
set -uo pipefail

# Run a set of scenarios against ./kcfg_k0rdent, in order.
#
#   export SCENARIOS="101_basic 201_svcdep"   # empty = every scenario
#   ./scripts/run_scenarios.sh
#
# Each scenario removes its own services, so the next one starts from the same
# cluster state -- remove_services.sh asserts that, which is what makes sharing
# a cluster safe.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=scripts/lib/k8s.sh
source "$SCRIPTS_DIR/lib/k8s.sh"

require_yq
require_cluster

WANTED="${SCENARIOS:-}"
if [[ -z "${WANTED// /}" ]]; then
    for f in "$SCENARIOS_DIR"/*.yaml; do WANTED+=" $(basename "$f" .yaml)"; done
fi

# Commas as well as spaces: the CI input is a comma-separated list.
WANTED="${WANTED//,/ }"

ordered=()
for id in $WANTED; do
    # Checked up front, so a typo in the list fails before an hour of cluster
    # build rather than after it.
    [[ -f "$SCENARIOS_DIR/$id.yaml" ]] || die "Unknown scenario '$id' -- no $SCENARIOS_DIR/$id.yaml"
    ordered+=("$id")
done
(( ${#ordered[@]} )) || die "No scenarios to run"

step "Serial run: ${#ordered[@]} scenario(s) on $(basename "$(readlink -f "$KUBECONFIG_MGMT")")"
printf '   %s\n' "${ordered[@]}"

declare -A RESULT ELAPSED
failed=0
n=0
RUN_START=$SECONDS

for id in "${ordered[@]}"; do
    n=$(( n + 1 ))
    step "[$n/${#ordered[@]}] $id"
    start=$SECONDS
    # A log directory per scenario: collect_logs.sh writes into $LOG_DIR, and
    # a shared one would leave only the last failure behind. CI uploads logs*/.
    if SCENARIO="$id" SCENARIO_KEEP=false LOG_DIR="$PROJECT_ROOT/logs-$id" \
        "$SCRIPTS_DIR/run_scenario.sh"; then
        RESULT["$id"]="passed"
    else
        RESULT["$id"]="FAILED"
        failed=$(( failed + 1 ))
        warn "$id failed -- continuing with the rest"
    fi
    ELAPSED["$id"]=$(( SECONDS - start ))
done

step "Summary"
for id in "${ordered[@]}"; do
    printf '   %-28s %-7s %dm%02ds\n' \
        "$id" "${RESULT[$id]}" "$(( ELAPSED[$id] / 60 ))" "$(( ELAPSED[$id] % 60 ))"
done
log "Total $(( (SECONDS - RUN_START) / 60 ))m$(( (SECONDS - RUN_START) % 60 ))s"

if (( failed )); then
    die "$failed of ${#ordered[@]} scenario(s) failed"
fi
ok "All ${#ordered[@]} scenarios passed"
