# shellcheck shell=bash
# Coralogix checks: agent -> Coralogix -> customer S3 archive. Sourced by scripts/validate.sh.
#
# Optional: CORALOGIX_QUERY_KEY (API key with DataQuerying permission) enables the
# Coralogix-side checks for logs, spans and metrics.

CX_NS=coralogix
CX_API="https://api.eu2.coralogix.com"

info "Coralogix collectors"
not_ready=$(kubectl get pods -n "$CX_NS" --no-headers 2>/dev/null | awk '$3!="Running"' | wc -l)
total=$(kubectl get pods -n "$CX_NS" --no-headers 2>/dev/null | wc -l)
[[ $total -gt 0 && $not_ready -eq 0 ]] && pass "$CX_NS: $total pods running" || fail "$CX_NS: $not_ready/$total pods not running"

agents=$(kubectl get ds -n "$CX_NS" -o jsonpath='{.items[0].status.numberReady}/{.items[0].status.desiredNumberScheduled}' 2>/dev/null)
[[ -n $agents && ${agents%/*} == "${agents#*/}" ]] && pass "agent DaemonSet ready on every node ($agents)" || fail "agent DaemonSet not fully ready ($agents)"

info "Demo -> agent wiring"
# cart is used because its image ships printenv; checkout is distroless (no shell tools).
pod=$(kubectl get pod -n "$DEMO_NS" -l app.kubernetes.io/component=cart -o name | head -1)
if [[ -n $pod ]]; then
  ep=$(kubectl exec -n "$DEMO_NS" "$pod" -- printenv OTEL_EXPORTER_OTLP_ENDPOINT 2>/dev/null)
  hostip=$(kubectl get -n "$DEMO_NS" "$pod" -o jsonpath='{.status.hostIP}')
  [[ $ep == *"$hostip"* ]] && pass "cart exports to node-local agent ($ep)" || fail "cart endpoint is '$ep', expected node IP $hostip"
fi

errs=$(kubectl logs -n "$CX_NS" -l app.kubernetes.io/name=opentelemetry-agent --since=10m --tail=2000 2>/dev/null \
  | grep -cE '"level":"error"|Exporting failed|code = (Unauthenticated|PermissionDenied)|status( code)?:? 40[13]\b')
[[ $errs -eq 0 ]] && pass "no export/auth errors in agent logs (last 10m)" || fail "$errs export/auth error lines in agent logs (last 10m)"

info "Coralogix (query API)"
if [[ -n ${CORALOGIX_QUERY_KEY:-} ]]; then
  dp() {
    curl -sS -X POST "$CX_API/api/v1/dataprime/query" \
      -H "Authorization: Bearer $CORALOGIX_QUERY_KEY" -H 'Content-Type: application/json' \
      -d "{\"query\": \"$1\", \"metadata\": {\"syntax\": \"QUERY_SYNTAX_DATAPRIME\", \"startDate\": \"$(date -u -d '-15 min' +%FT%TZ)\", \"endDate\": \"$(date -u +%FT%TZ)\"}}"
  }
  for src in logs spans; do
    n=$(dp "source $src | filter \$l.applicationname != null | count" | grep -o '"_count[^}]*' | grep -o '[0-9]\+' | head -1)
    [[ ${n:-0} -gt 0 ]] && pass "$src in Coralogix (last 15m): $n" || fail "no $src in Coralogix in the last 15m"
  done
  m=$(curl -sS -G "$CX_API/metrics/api/v1/query" -H "Authorization: Bearer $CORALOGIX_QUERY_KEY" \
      --data-urlencode 'query=count(k8s_pod_cpu_utilization_ratio)' | grep -o '"value":\[[^]]*\]')
  [[ -n $m ]] && pass "metrics in Coralogix: $m" || fail "no k8s metrics returned from PromQL API"
else
  echo "skip: set CORALOGIX_QUERY_KEY to check logs/spans/metrics via API (or verify in the UI)"
fi

info "Customer-owned S3 archive"
for kind in logs metrics; do
  bucket=$(terraform -chdir="$ROOT/vendors/coralogix/terraform" output -raw "archive_${kind}_bucket" 2>/dev/null)
  [[ -z $bucket ]] && { fail "no $kind bucket in terraform outputs"; continue; }
  # Fail on AWS errors and on empty buckets explicitly; only a real object counts.
  if ! out=$(aws s3api list-objects-v2 --bucket "$bucket" --output json \
      --query '{n: length(Contents || `[]`), t: max_by(Contents || `[]`, &LastModified).LastModified}' 2>&1); then
    fail "$bucket: $(echo "$out" | tail -1)"; continue
  fi
  n=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["n"] or 0)' <<<"$out")
  t=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["t"] or "")' <<<"$out")
  if [[ $n -eq 0 ]]; then
    fail "$bucket: empty (archive connected in the UI? first writes take ~10-15 min)"
  else
    age=$(( ($(date +%s) - $(date -d "$t" +%s)) / 60 ))
    [[ $age -le 30 ]] && pass "$bucket: $n objects, newest ${age} min ago" \
                      || fail "$bucket: newest object is ${age} min old (archiving stalled?)"
  fi
done

