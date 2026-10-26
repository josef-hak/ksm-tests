#!/usr/bin/env bash
# The scripts copied from k0rdent/catalog call each other as ./scripts/<name>.sh
# from the repository root, which is why they keep catalog's layout and their
# original names. A copy that forgets a sibling fails halfway through
# provisioning -- where it is most expensive to find out.
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Every sibling actually invoked -- a line that runs one, not a usage comment
# or a hint in a message. Anchored at the start of a line, optionally behind
# `VAR=value ` assignments, which is how catalog writes them.
calls() {
    grep -hoE '^[A-Z_]*=?[A-Za-z0-9_.-]*[[:space:]]*\./scripts/[a-z_0-9]+\.sh' \
        "$SCRIPTS_DIR"/*.sh | grep -oE '[a-z_0-9]+\.sh$' | sort -u
}

missing=""
while read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -f "$SCRIPTS_DIR/$ref" ]] || missing+="$ref "
done < <(calls)

assert_eq "every sibling a copied script calls is in scripts/" "" "$missing"

# A guard on the guard: the extraction has to be finding something, or the
# check above passes by matching nothing at all.
assert_not_eq "and it really found the calls" "0" "$(calls | wc -l | tr -d ' ')"

# The call itself: run one from the repository root and it must get past the
# sibling to its own error, not die on a missing file.
out="$(cd "$REPO_ROOT" && env -u AWS_ACCESS_KEY_ID TEST_MODE=aws \
    ./scripts/setup_provider_credential.sh 2>&1)" || true
assert_not_contains "a sibling call resolves at runtime" "$out" "No such file"
assert_contains "and reaches the check it was calling" "$out" "AWS_ACCESS_KEY_ID"

finish
