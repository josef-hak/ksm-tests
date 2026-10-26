#!/usr/bin/env bash
# The scripts copied from k0rdent/catalog call each other as ./scripts/<name>.sh.
# That resolves here only because of the `scripts -> .` symlink next to them,
# and only when they are run from their own directory. Both are easy to lose:
# a copy that forgets a sibling fails halfway through provisioning, which is
# exactly where it is most expensive to find out.
# shellcheck source=scripts/tests/bash/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CATALOG="$SCRIPTS_DIR/catalog"

assert_eq "the scripts symlink is there" "." "$(readlink "$CATALOG/scripts")"

# Every sibling actually invoked -- a line that runs one, not a usage comment
# or a hint in a message. Anchored at the start of a line, optionally behind
# `VAR=value ` assignments, which is how catalog writes them.
missing=""
while read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -f "$CATALOG/$ref" ]] || missing+="$ref "
done < <(grep -hoE '^[A-Z_]*=?[A-Za-z0-9_.-]*[[:space:]]*\./scripts/[a-z_0-9]+\.sh' "$CATALOG"/*.sh \
    | grep -oE '[a-z_0-9]+\.sh$' | sort -u)

assert_eq "every sibling a copied script calls was copied too" "" "$missing"

# A guard on the guard: the extraction has to be finding something, or the
# check above passes by matching nothing at all.
found="$(grep -hoE '^[A-Z_]*=?[A-Za-z0-9_.-]*[[:space:]]*\./scripts/[a-z_0-9]+\.sh' "$CATALOG"/*.sh \
    | grep -coE '[a-z_0-9]+\.sh$' || true)"
assert_not_eq "and it really found the calls" "0" "$found"

# The call itself: run one from its own directory and it must get past the
# sibling to its own error, not die on a missing file.
out="$(cd "$CATALOG" && env -u AWS_ACCESS_KEY_ID TEST_MODE=aws ./setup_provider_credential.sh 2>&1)" || true
assert_not_contains "a sibling call resolves at runtime" "$out" "No such file"
assert_contains "and reaches the check it was calling" "$out" "AWS_ACCESS_KEY_ID"

finish
