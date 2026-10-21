#!/usr/bin/env bash
# One cluster, several scenarios, one after another. No `set -e`: the loop
# decides what a failure means, and it still has a summary to print.
set -uo pipefail

# Run a set of scenarios against ./kcfg_k0rdent, in order.
#
#   export SCENARIOS="101_basic 201_svcdep"   # empty = every scenario
#   ./scripts/run_scenarios.sh
#
# Each scenario removes its own services, so the next one starts from the same
# cluster state -- remove_services.sh asserts that, which is what makes sharing
# a cluster safe.
#
# The run stops at the first failure: on a shared cluster the ones after it
# would be starting from a state nobody asserted anyway, and the environment
# costs minutes that a known-bad run should not spend.

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
FAILED=""
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
        FAILED="$id"
    fi
    ELAPSED["$id"]=$(( SECONDS - start ))
    [[ -n "$FAILED" ]] && break
done

# Says what was never attempted as well as what ran: a summary listing three
# scenarios after a run that stopped at the first would read as three verdicts.
step "Summary"
for id in "${ordered[@]}"; do
    printf '   %-28s %-9s %s\n' "$id" "${RESULT[$id]:-not run}" \
        "$( [[ -n "${ELAPSED[$id]:-}" ]] \
            && printf '%dm%02ds' "$(( ELAPSED[$id] / 60 ))" "$(( ELAPSED[$id] % 60 ))" )"
done
log "Total $(( (SECONDS - RUN_START) / 60 ))m$(( (SECONDS - RUN_START) % 60 ))s"

if [[ -n "$FAILED" ]]; then
    die "$FAILED failed -- stopping, $(( ${#ordered[@]} - n )) scenario(s) not run"
fi
ok "All ${#ordered[@]} scenarios passed"
