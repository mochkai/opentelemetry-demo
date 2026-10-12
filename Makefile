SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

-include .env
export

.DEFAULT_GOAL := help

AWS_DIR        := infra/aws
DEMO_NS        := otel-demo
DEMO_CHART_VER := 0.42.3

# Node group sizes restored by `make wake` (keep in sync with infra/aws eks.tf).
NODES_MIN     := 2
NODES_MAX     := 4
NODES_DESIRED := 3

# Values files for the demo, applied in order. The base file only adds scheduling
# rules; the chart's bundled collector and backends stay on unless a vendor
# overlay (appended by vendors/*/vendor.mk) turns them off.
DEMO_VALUES := helm/otel-demo-values.yaml

UP_STEPS := aws kubeconfig repos demo

# Vendor integrations plug in here: each vendors/<name>/vendor.mk may append to
# DEMO_VALUES, override UP_STEPS and add targets.
-include vendors/*/vendor.mk

.PHONY: help up down aws kubeconfig repos demo status validate frontend destroy-k8s sleep wake check-env rebalance

help:
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-20s %s\n", $$1, $$2}'

up: $(UP_STEPS) ## Build everything end to end

aws: ## Provision VPC and EKS
	terraform -chdir=$(AWS_DIR) init -upgrade
	terraform -chdir=$(AWS_DIR) apply

kubeconfig: ## Point kubectl at the EKS cluster
	$$(terraform -chdir=$(AWS_DIR) output -raw kubeconfig_command)

repos:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update

demo: ## Install the OpenTelemetry Demo
	helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
	  --version $(DEMO_CHART_VER) -n $(DEMO_NS) --create-namespace \
	  $(addprefix -f ,$(DEMO_VALUES)) --wait --timeout 15m

status: ## Show demo pods
	kubectl get pods -n $(DEMO_NS)

validate: ## Run end-to-end validation checks
	./scripts/validate.sh

frontend: ## Port-forward the demo storefront to http://localhost:8080
	kubectl -n $(DEMO_NS) port-forward svc/frontend-proxy 8080:8080

# Scale worker nodes to 0. The control plane (~$0.10/h) and NAT gateway keep
# running, but nodes are most of the cost. Helm releases and cluster config survive;
# pods are rescheduled on `make wake`. A later `terraform apply` resets min_size.
sleep: ## Scale worker nodes to 0 (cluster kept, ~5 min to wake)
	CLUSTER=$$(terraform -chdir=$(AWS_DIR) output -raw cluster_name)
	REGION=$$(terraform -chdir=$(AWS_DIR) output -raw region)
	NG=$$(aws eks list-nodegroups --region $$REGION --cluster-name $$CLUSTER --query 'nodegroups[0]' --output text)
	aws eks update-nodegroup-config --region $$REGION --cluster-name $$CLUSTER --nodegroup-name $$NG \
	  --scaling-config minSize=0,maxSize=$(NODES_MAX),desiredSize=0 --query 'update.status' --output text
	echo "Scaling $$NG to 0 nodes. Run 'make wake' to bring it back."

wake: ## Scale worker nodes back up and wait for them to be Ready
	CLUSTER=$$(terraform -chdir=$(AWS_DIR) output -raw cluster_name)
	REGION=$$(terraform -chdir=$(AWS_DIR) output -raw region)
	NG=$$(aws eks list-nodegroups --region $$REGION --cluster-name $$CLUSTER --query 'nodegroups[0]' --output text)
	aws eks update-nodegroup-config --region $$REGION --cluster-name $$CLUSTER --nodegroup-name $$NG \
	  --scaling-config minSize=$(NODES_MIN),maxSize=$(NODES_MAX),desiredSize=$(NODES_DESIRED) --query 'update.status' --output text
	aws eks wait nodegroup-active --region $$REGION --cluster-name $$CLUSTER --nodegroup-name $$NG
	until [ "$$(kubectl get nodes --no-headers 2>/dev/null | grep -cw Ready)" -ge $(NODES_MIN) ]; do sleep 15; done
	kubectl get nodes

destroy-k8s:
	-helm uninstall otel-demo -n $(DEMO_NS)

down: destroy-k8s ## Tear down the demo and the cluster (stops most AWS costs)
	terraform -chdir=$(AWS_DIR) destroy

# Where each demo pod sends telemetry vs. the node it runs on, read from the pod
# spec so it works for every image. Services use one of three variables for the
# endpoint; $(OTEL_COLLECTOR_NAME) resolves to the pod's node IP (status.hostIP).
# "live" = confirmed with printenv inside the container (needs printenv in the
# image; distroless ones like checkout show "spec" only). Shell $ is written $$.
check-env: ## Show where every demo pod sends telemetry, next to its node IP
	@printf '%-17s %-14s %-32s %s\n' SERVICE NODE_IP SENDS_TO SOURCE
	@kubectl get pods -n $(DEMO_NS) -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.app\.kubernetes\.io/component}{"|"}{.status.hostIP}{"|"}{.spec.containers[0].env[?(@.name=="OTEL_EXPORTER_OTLP_ENDPOINT")].value}{"|"}{.spec.containers[0].env[?(@.name=="OTEL_COLLECTOR_HOST")].value}{"|"}{.spec.containers[0].env[?(@.name=="TRACELOOP_BASE_URL")].value}{"|"}{.metadata.deletionTimestamp}{"\n"}{end}' \
	| sort -t'|' -k2 | while IFS='|' read -r pod svc ip e1 e2 e3 deleting; do
	  [ -n "$$deleting" ] && continue   # skip pods shutting down during a rollout
	  ep=$${e1:-$${e2:-$$e3}}
	  if [ -z "$$ep" ]; then
	    printf '%-17s %-14s %-32s %s\n' "$$svc" "$$ip" "-" "no OTLP endpoint set; container logs via node agent"
	    continue
	  fi
	  ep=$${ep//\$$(OTEL_COLLECTOR_NAME)/$$ip}
	  live=$$(kubectl exec -n $(DEMO_NS) "$$pod" -- printenv OTEL_EXPORTER_OTLP_ENDPOINT 2>/dev/null) && src="live" || src="spec"
	  printf '%-17s %-14s %-32s %s\n' "$$svc" "$$ip" "$$ep" "$$src"
	done
# Kubernetes never moves running pods. After `make wake` (nodes join one at a time)
# or a node change, restart the demo so the scheduler re-places every pod with all
# nodes available and the spread rule in k8s/otel-demo-values.yaml applies.
rebalance: ## Re-spread demo pods across all nodes (brief partial disruption)
	kubectl rollout restart deploy -n $(DEMO_NS)
	kubectl rollout status deploy -n $(DEMO_NS) --timeout=10m
	kubectl get pods -n $(DEMO_NS) -o jsonpath='{range .items[*]}{.status.hostIP}{"\n"}{end}' | sort | uniq -c | sed 's/^/pods per node: /'
