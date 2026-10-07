#!/usr/bin/env bash
# End-to-end validation. Base checks cover the cluster and the demo; integration
# checks live in vendors/<name>/validate.sh. Each check prints PASS/FAIL with the
# evidence; exits non-zero if any check fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_NS=otel-demo
FAILS=0

pass() { printf '\e[32mPASS\e[0m %s\n' "$*"; }
fail() { printf '\e[31mFAIL\e[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
info() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

info "Kubernetes"
if kubectl get nodes >/dev/null 2>&1; then
  pass "cluster reachable: $(kubectl config current-context)"
else
  fail "kubectl cannot reach the cluster"; exit 1
fi

not_ready=$(kubectl get pods -n "$DEMO_NS" --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed"' | wc -l)
total=$(kubectl get pods -n "$DEMO_NS" --no-headers 2>/dev/null | wc -l)
[[ $total -gt 0 && $not_ready -eq 0 ]] && pass "$DEMO_NS: $total pods running" || fail "$DEMO_NS: $not_ready/$total pods not running"

# Vendor-specific checks are sourced here and share the helpers above.
for check in "$ROOT"/vendors/*/validate.sh; do
  [[ -e $check ]] && source "$check"
done

echo
[[ $FAILS -eq 0 ]] && { pass "all checks passed"; exit 0; } || { fail "$FAILS check(s) failed"; exit 1; }
