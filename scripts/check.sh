#!/usr/bin/env bash
# check.sh: local CI gate, wired as the pre-push hook (.githooks/pre-push).
#
# Runs the same checks as GitHub CI with the MATCHED system toolchain.
# Escape hatch: git push --no-verify (CI remains the final authority).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Toolchain pin: system cargo + rustc + clippy-driver, matched pair.
# Never let the rustup toolchain (rustc 1.100) touch target/; it poisons
# the cache with incompatible rmeta and everything fails with E0514.
export PATH=/usr/bin:/bin

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    ok\n'; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

# run <label> <command...>: print the label, capture output, show it and
# bail on failure (with the known fix when the failure is the
# mixed-toolchain cache-poisoning signature).
run() {
    local label="$1"; shift
    step "$label"
    if "$@" >"$OUT" 2>&1; then
        ok
    elif grep -q "compiled by an incompatible version of rustc" "$OUT"; then
        printf '\n%s\n' "$(cat "$OUT")" >&2
        fail "mixed rustc artifacts in target/.
    the rustup toolchain (rustc 1.100) touched target/. Fix with:
        env PATH=/usr/bin:/bin /usr/bin/cargo clean
    then re-run this check (or just push again)."
    else
        printf '%s\n' "$(cat "$OUT")" >&2
        fail "$label failed"
    fi
}

run "format"  /usr/bin/cargo fmt --all --check
run "clippy"  /usr/bin/cargo clippy --workspace --all-targets -- -D warnings
run "tests"   /usr/bin/cargo test --workspace --quiet

printf '\n\033[1;32m✓ all local checks passed, safe to push\033[0m\n'
