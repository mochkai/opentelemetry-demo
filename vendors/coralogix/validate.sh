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
pod=$(kubectl get pod -n "$DEMO_NS" -l app.kubernetes.io/component=checkout -o name | head -1)
if [[ -n $pod ]]; then
  ep=$(kubectl exec -n "$DEMO_NS" "$pod" -- printenv OTEL_EXPORTER_OTLP_ENDPOINT 2>/dev/null)
  hostip=$(kubectl get -n "$DEMO_NS" "$pod" -o jsonpath='{.status.hostIP}')
  [[ $ep == *"$hostip"* ]] && pass "checkout exports to node-local agent ($ep)" || fail "checkout endpoint is '$ep', expected node IP $hostip"
fi

errs=$(kubectl logs -n "$CX_NS" -l app.kubernetes.io/name=opentelemetry-agent --since=10m --tail=2000 2>/dev/null \
  | grep -ciE 'exporting failed|permission denied|unauthenticated|403|401')
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
  latest=$(aws s3api list-objects-v2 --bucket "$bucket" --query 'sort_by(Contents,&LastModified)[-1].[LastModified,Key]' --output text 2>&1)
  if [[ $latest == None* || -z $latest ]]; then
    fail "$bucket: empty (connected in the UI? first writes can take ~10-15 min)"
  elif [[ $latest == *rror* ]]; then
    fail "$bucket: $latest"
  else
    pass "$bucket: latest object $latest"
  fi
done

