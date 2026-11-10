#!/usr/bin/env bash
# The optional blocks from scripts/lib/checks.sh: that they read what the
# scenario declares, and -- more to the point -- that a scenario declaring none
# of them sees nothing at all. Every scenario but 403 is in that second group,
# which is what makes this backwards compatible.
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

export SCENARIO=403_mcsdep_diamond TEST_MODE=self KCM=1.0.0
# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"
# shellcheck source=scripts/lib/services.sh
source "$SCRIPTS_DIR/lib/services.sh"
# shellcheck source=scripts/lib/checks.sh
source "$SCRIPTS_DIR/lib/checks.sh"

# ── The blocks are read as declared ──────────────────────────────────────────
assert_eq "403 applies one MCS ahead of the rest" "1" "$(apply_first_count)"
assert_eq "and it is the one at the bottom of the graph" \
    "workload" "$(block_name applyFirstMultiClusterServices 0)"
assert_eq "named for the cluster, not just the key" \
    "mcs-403-mcsdep-diamond-workload" "$(block_object_name applyFirstMultiClusterServices 0)"

assert_eq "403 drives its own removal order" "5" "$(removal_count)"
assert_eq "asking for the root first, out of dependency order" \
    "certs" "$(block_name removeMultiClusterServices 0)"
assert_eq "and coming back to it at the end" \
    "certs" "$(block_name removeMultiClusterServices 4)"
assert_eq "where nothing is deleted a second time" \
    "false" "$(block_flag removeMultiClusterServices 4 delete)"
assert_eq "an entry with no delete flag deletes" \
    "" "$(block_flag removeMultiClusterServices 1 delete)"

# ── Checks are read off any of the three places ──────────────────────────────
assert_eq "a check on the MCS itself" \
    "2" "$(checks_count "$(MCS_IDX="$(mcs_index_of crds)" mcs_root)")"
assert_eq "the condition it waits for" \
    "ClusterInReadyState" \
    "$(check_field "$(MCS_IDX="$(mcs_index_of crds)" mcs_root)" 1 condition)"
assert_eq "and the count in its message, not just the status" \
    "1/1" "$(check_field "$(MCS_IDX="$(mcs_index_of crds)" mcs_root)" 1 message)"
assert_eq "a status defaults to empty here and to True in run_checks" \
    "" "$(check_field "$(MCS_IDX="$(mcs_index_of crds)" mcs_root)" 1 status)"

assert_eq "the pre-applied one waits for a False" \
    "False" "$(check_field .applyFirstMultiClusterServices[0] 0 status)"
assert_eq "and for nothing to be rolled out" \
    "true" "$(check_field .applyFirstMultiClusterServices[0] 1 noServiceSet)"
assert_eq "sitting out a window rather than glancing once" \
    "60" "$(check_field .applyFirstMultiClusterServices[0] 1 forSeconds)"

assert_eq "the refused delete is checked for still being there" \
    "true" "$(check_field .removeMultiClusterServices[0] 1 present)"
assert_eq "and the released one for being gone" \
    "true" "$(check_field .removeMultiClusterServices[4] 0 absent)"

# ── Nothing is imposed on a scenario that asks for nothing ───────────────────
# The whole backwards-compatibility claim, asserted rather than argued.
for s in 101_basic 201_svcdep 202_svcdep_invalid 301_upgrade \
         302_upgrade_invalid_atomic 401_mcsdep_valid 402_mcsdep_invalid \
         501_no_chain 502_chain_boundary 503_direct_chain 504_stepwise_chain; do
    SERVICES_FILE="$REPO_ROOT/test_scenarios/$s.yaml"
    assert_eq "$s applies nothing ahead of the rest" "0" "$(apply_first_count)"
    assert_eq "$s keeps the default removal order" "0" "$(removal_count)"
done

# And an MCS with no checks block runs no checks.
SERVICES_FILE="$REPO_ROOT/test_scenarios/401_mcsdep_valid.yaml"
assert_eq "401's base declares no checks" \
    "0" "$(checks_count "$(MCS_IDX=0 mcs_root)")"
assert_eq "nor does its dependent" \
    "0" "$(checks_count "$(MCS_IDX=1 mcs_root)")"

# ── Dispatch: the right check runs, with the right arguments ─────────────────
# The leaves are stubbed, so this asserts how run_checks reads a block rather
# than anything about a cluster. Dispatch is where a mistyped field would turn
# an assertion into a silent no-op, which is the failure worth catching early.
SERVICES_FILE="$REPO_ROOT/test_scenarios/403_mcsdep_diamond.yaml"
TRACE=""
check_condition()    { TRACE+="condition $2 $3 '$4' $5"$'\n'; }
check_absent()       { TRACE+="absent $2"$'\n'; }
check_present()      { TRACE+="present $2"$'\n'; }
check_no_serviceset(){ TRACE+="noServiceSet $2"$'\n'; }

run_checks "$(MCS_IDX="$(mcs_index_of crds)" mcs_root)" obj 900
assert_eq "a bare condition defaults to True and no message" \
    "condition MultiClusterServiceDependencyValidation True '' 900" \
    "$(head -1 <<< "$TRACE")"
assert_eq "and the next one carries the message it declared" \
    "condition ClusterInReadyState True '1/1' 900" \
    "$(sed -n 2p <<< "$TRACE")"

TRACE=""
run_checks .applyFirstMultiClusterServices[0] obj 900
assert_eq "an explicit status is honoured" \
    "condition MultiClusterServiceDependencyValidation False '' 900" \
    "$(head -1 <<< "$TRACE")"
assert_eq "and a windowed negative check gets its window, not the timeout" \
    "noServiceSet 60" "$(sed -n 2p <<< "$TRACE")"

TRACE=""
run_checks .removeMultiClusterServices[0] obj 300
assert_eq "the refused delete waits on the condition first" \
    "condition MultiClusterServiceDependencyValidation False '' 300" \
    "$(head -1 <<< "$TRACE")"
assert_eq "then sits out the window it was given" "present 30" "$(sed -n 2p <<< "$TRACE")"

TRACE=""
run_checks .removeMultiClusterServices[4] obj 300
assert_eq "and the released one is waited out to absence" "absent 300" "$(head -1 <<< "$TRACE")"

TRACE=""
run_checks .removeMultiClusterServices[1] obj 300
assert_eq "an entry with no checks runs none" "" "${TRACE%%$'\n'}"

# ── A typo is caught where it is written ─────────────────────────────────────
SERVICES_FILE="$(mktemp)"
cat > "$SERVICES_FILE" <<'EOF'
name: fake
multiClusterServices:
  - name: real
    services: []
removeMultiClusterServices:
  - name: typo
EOF
out="$(block_object_name removeMultiClusterServices 0 2>&1 || true)"
assert_contains "an entry naming an MCS that does not exist is refused" \
    "$out" "is not a declared MultiClusterService"
rm -f "$SERVICES_FILE"

finish
