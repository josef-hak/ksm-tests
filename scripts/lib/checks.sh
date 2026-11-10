#!/usr/bin/env bash
# Declarative post-condition checks on a MultiClusterService.
#
# A scenario can hang a `checks:` list on three places -- a MultiClusterService
# in `multiClusterServices:`, an entry in `applyFirstMultiClusterServices:`, and
# an entry in `removeMultiClusterServices:`. All three are optional: a scenario
# that declares none behaves exactly as it did before this file existed, which
# is why every existing scenario is untouched.
#
# The vocabulary is small on purpose. These assert what KCM itself reports --
# conditions and the existence of objects -- and leave what landed in the child
# cluster to the steps that already check helm releases and pods.
#
#   checks:
#     - condition: ClusterInReadyState   # wait until .status.conditions says so
#       status: "True"                   # default "True"
#       message: "1/1"                   # optional substring of .message
#       timeout: 600                     # optional, else the caller's default
#
#     - absent: true                     # wait until the MCS object is gone
#       timeout: 300
#
#     - present: true                    # it must still be there ...
#       forSeconds: 30                   # ... for this long. 0 = just now.
#
#     - noServiceSet: true               # no ServiceSet may reference it ...
#       forSeconds: 60                   # ... for this long.
#
# `present` and `noServiceSet` are the negative assertions: they sit out their
# whole window whatever happens, because "has not happened yet" and "will never
# happen" are the same reading at any single moment.
#
# Expects common.sh and k8s.sh to be sourced first.

# ── Schema ───────────────────────────────────────────────────────────────────
# The yq path of the block holding the checks is passed in as a string and
# interpolated, the way services.sh already builds paths from mcs_root.

# checks_count PATH -- how many checks the block at this path declares.
checks_count() {
    yq -r "[$1 | .checks[]?] | length" "$SERVICES_FILE"
}

# check_field PATH IDX FIELD -- one field of one check, empty when unset.
#
# tostring and not `// ""`: the alternative operator treats a declared `false`
# as absent, so `delete: false` read that way comes back empty and means the
# opposite of what it says. yq prints a missing key as the string "null", which
# is the one value a scenario can never usefully declare.
check_field() {
    FIELD="$3" yq -r "$1 | .checks[$2] | .[strenv(FIELD)] | tostring" "$SERVICES_FILE" \
        | sed 's/^null$//'
}

# ── Readers ──────────────────────────────────────────────────────────────────

# condition_message KIND NAME NS TYPE -- the message of one condition, or empty.
# Never fails, so it is safe inside a polling loop.
condition_message() {
    local kind="$1" name="$2" ns="$3" type="$4"
    local args=(get "$kind" "$name")
    [[ -n "$ns" ]] && args+=(-n "$ns")
    args+=(-o "jsonpath={.status.conditions[?(@.type==\"$type\")].message}")
    kube "${args[@]}" 2>/dev/null || true
}

# serviceset_for MCS_OBJECT_NAME -- the ServiceSet that names this MCS, if any.
# Only the MCS-owned one: a ClusterDeployment keeps a ServiceSet of its own.
serviceset_for() {
    kube get serviceset -n "$NAMESPACE" \
        -o jsonpath="{.items[?(@.spec.multiClusterService==\"$1\")].metadata.name}" \
        2>/dev/null || true
}

# ── The checks ───────────────────────────────────────────────────────────────

# check_condition OBJ TYPE WANT MESSAGE TIMEOUT
check_condition() {
    local obj="$1" type="$2" want="$3" want_msg="$4" timeout="$5"
    local elapsed=0 status msg descr=""
    [[ -n "$want_msg" ]] && descr=" containing \"$want_msg\""

    log "Waiting for MultiClusterService/$obj condition $type=$want$descr (timeout ${timeout}s)"
    while (( elapsed < timeout )); do
        status="$(condition_status MultiClusterService "$obj" "" "$type")"
        msg="$(condition_message MultiClusterService "$obj" "" "$type")"
        if [[ "$status" == "$want" ]] && [[ -z "$want_msg" || "$msg" == *"$want_msg"* ]]; then
            ok "MultiClusterService/$obj: $type=$status${msg:+ -- $msg}"
            return 0
        fi
        if (( elapsed > 0 && elapsed % ${DIAG_INTERVAL:-120} == 0 )); then
            warn "Still waiting on $type after ${elapsed}s -- diagnostics:"
            kcm_errors 5m >&2
        elif (( elapsed % 30 == 0 )); then
            log "⏳ $obj $type='${status:-<none>}'${msg:+ ($msg)} (${elapsed}s)"
        fi
        sleep 5
        elapsed=$(( elapsed + 5 ))
    done

    kube get multiclusterservice "$obj" -o json 2>/dev/null \
        | jq -r '.status.conditions[]? | "\(.type)=\(.status) \(.message // "")"' >&2 || true
    die "MultiClusterService $obj: condition $type never reached $want$descr within ${timeout}s (last: ${status:-<none>} / ${msg:-<none>})"
}

# check_absent OBJ TIMEOUT
check_absent() {
    wait_for_absence MultiClusterService "$1" "" "$2" 5 \
        || die "MultiClusterService '$1' was still there after ${2}s"
}

# check_present OBJ FOR_SECONDS -- it exists, and goes on existing. A deletion
# that is supposed to be refused is only refused if it is still refused a while
# later; an object mid-finalizer looks exactly the same at the first glance.
check_present() {
    local obj="$1" window="$2" elapsed=0 rc
    step "Expecting '$obj' to still be there${window:+ for ${window}s}"
    while :; do
        rc=0; resource_exists MultiClusterService "$obj" || rc=$?
        (( rc == 2 )) && die "Could not ask the API whether '$obj' exists"
        (( rc == 0 )) || die "MultiClusterService '$obj' disappeared after ${elapsed}s, it should have been held back"
        (( elapsed >= window )) && break
        sleep 5
        elapsed=$(( elapsed + 5 ))
    done
    ok "'$obj' is still present after ${elapsed}s, as expected"
}

# check_no_serviceset OBJ FOR_SECONDS -- nothing was rolled out for it, and
# goes on not being rolled out.
check_no_serviceset() {
    local obj="$1" window="$2" elapsed=0 sset
    step "Expecting no ServiceSet for '$obj'${window:+ for ${window}s}"
    while :; do
        sset="$(serviceset_for "$obj")"
        [[ -z "$sset" ]] \
            || die "ServiceSet '$sset' was created for '$obj' after ${elapsed}s, its dependencies were not ready"
        (( elapsed >= window )) && break
        sleep 5
        elapsed=$(( elapsed + 5 ))
    done
    ok "'$obj' has no ServiceSet after ${elapsed}s, as expected"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

# run_checks PATH OBJ DEFAULT_TIMEOUT -- every check declared at PATH, in order.
# A block with no checks is a no-op, which is what keeps this optional.
run_checks() {
    local path="$1" obj="$2" default_timeout="$3"
    local n i timeout cond want msg window
    n="$(checks_count "$path")"
    (( n > 0 )) || return 0

    for (( i = 0; i < n; i++ )); do
        timeout="$(check_field "$path" "$i" timeout)"
        timeout="${timeout:-$default_timeout}"
        window="$(check_field "$path" "$i" forSeconds)"
        window="${window:-0}"

        cond="$(check_field "$path" "$i" condition)"
        if [[ -n "$cond" ]]; then
            want="$(check_field "$path" "$i" status)"
            msg="$(check_field "$path" "$i" message)"
            check_condition "$obj" "$cond" "${want:-True}" "$msg" "$timeout"
            continue
        fi
        [[ "$(check_field "$path" "$i" absent)" == "true" ]] \
            && { check_absent "$obj" "$timeout"; continue; }
        [[ "$(check_field "$path" "$i" present)" == "true" ]] \
            && { check_present "$obj" "$window"; continue; }
        [[ "$(check_field "$path" "$i" noServiceSet)" == "true" ]] \
            && { check_no_serviceset "$obj" "$window"; continue; }

        die "Scenario '$SCENARIO': check $i at $path declares none of condition, absent, present, noServiceSet"
    done
}

# ── Optional top-level blocks ────────────────────────────────────────────────
# Both are lists of { name, checks } over the MCS keys the scenario already
# declares. Absent means the old behaviour, so nothing existing has to change.

# apply_first_count / removal_count -- 0 when the block is not declared.
apply_first_count() {
    yq -r '[.applyFirstMultiClusterServices[]?] | length' "$SERVICES_FILE"
}

removal_count() {
    yq -r '[.removeMultiClusterServices[]?] | length' "$SERVICES_FILE"
}

# block_name BLOCK IDX -- the MCS key an entry refers to.
block_name() {
    yq -r ".$1[$2].name" "$SERVICES_FILE"
}

# block_flag BLOCK IDX FIELD -- a scalar field of an entry, empty when unset.
# tostring for the same reason as check_field: `delete: false` is the whole
# point of the field and `// ""` would swallow it.
block_flag() {
    FIELD="$3" yq -r ".$1[$2] | .[strenv(FIELD)] | tostring" "$SERVICES_FILE" \
        | sed 's/^null$//'
}

# block_object_name BLOCK IDX -- the Kubernetes name, with a typo caught here
# rather than as a confusing "not found" three steps later.
block_object_name() {
    local key idx
    key="$(block_name "$1" "$2")"
    idx="$(mcs_index_of "$key")"
    [[ -n "$idx" ]] || die "Scenario '$SCENARIO': $1[$2] names '$key', which is not a declared MultiClusterService"
    mcs_object_name "$idx"
}
