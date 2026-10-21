#!/usr/bin/env bash
# CI runs one step per script so a failure is visible in the step list, while a
# local run goes through deploy_k0rdent.sh and run_scenario.sh. That is the
# same pipeline written twice, so assert the two agree -- a script added to one
# and forgotten in the other is exactly the drift this catches.
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

WORKFLOW="$REPO_ROOT/.github/workflows/e2e-scenario.yml"

# Teardown and diagnostics are the job's own business, not part of the
# pipeline: CI runs them on failure and cleanup, the entry points in a trap.
NOT_PIPELINE='collect_logs|remove_k0rdent|remove_adopted_cluster'

strip() { sed -E 's#.*/##' | grep -vE "^($NOT_PIPELINE)\.sh$"; }

# Only real invocations: a `run:` key in the workflow, and a command at the
# start of a line in the entry points. Anchored so the usage comments at the
# top of each script -- which name the script itself -- are not counted.
ci="$(grep -oE '^ +run: \./scripts/steps/[a-z_0-9]+\.sh$' "$WORKFLOW" | strip)"
# shellcheck disable=SC2016 # $SCRIPTS_DIR is the literal text being matched
local_run="$(grep -hoE '^ *"\$SCRIPTS_DIR/steps/[a-z_0-9]+\.sh"' \
    "$SCRIPTS_DIR/deploy_k0rdent.sh" "$SCRIPTS_DIR/run_scenario.sh" \
    | tr -d '"' | strip)"

assert_eq "CI runs the same scripts, in the same order, as the entry points" \
    "$local_run" "$ci"

# A guard on the guard: if the extraction ever matches nothing, the comparison
# above passes trivially and stops protecting anything.
assert_not_eq "the workflow extraction found something" "" "$ci"
assert_contains "and it really is the pipeline" "$ci" "wait_for_management.sh"

# e2e-serial.yml builds the same environment and then hands phases 2 to 4 to
# run_scenarios.sh in one step, so only the build half is comparable -- and
# against deploy_k0rdent.sh alone.
SERIAL="$REPO_ROOT/.github/workflows/e2e-serial.yml"
serial_ci="$(grep -oE '^ +run: \./scripts/steps/[a-z_0-9]+\.sh$' "$SERIAL" | strip)"
# shellcheck disable=SC2016 # $SCRIPTS_DIR is the literal text being matched
build_local="$(grep -hoE '^ *"\$SCRIPTS_DIR/steps/[a-z_0-9]+\.sh"' \
    "$SCRIPTS_DIR/deploy_k0rdent.sh" | tr -d '"' | strip)"

assert_eq "the serial workflow builds the environment like deploy_k0rdent.sh" \
    "$build_local" "$serial_ci"
assert_contains "and it really is the build" "$serial_ci" "wait_for_management.sh"
assert_contains "the serial workflow runs the scenarios through run_scenarios.sh" \
    "$(cat "$SERIAL")" "run_scenarios.sh"

finish
