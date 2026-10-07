SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

-include .env
export

.DEFAULT_GOAL := help

AWS_DIR        := infra/aws
DEMO_NS        := otel-demo
DEMO_CHART_VER := 0.42.3

# Extra values files for the demo. Empty = chart defaults (bundled collector,
# Jaeger, Prometheus, Grafana, OpenSearch). Vendors append their overlays.
DEMO_VALUES :=

UP_STEPS := aws kubeconfig repos demo

# Vendor integrations plug in here: each vendors/<name>/vendor.mk may append to
# DEMO_VALUES, override UP_STEPS and add targets.
-include vendors/*/vendor.mk

.PHONY: help up down aws kubeconfig repos demo status validate frontend destroy-k8s

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

destroy-k8s:
	-helm uninstall otel-demo -n $(DEMO_NS)

down: destroy-k8s ## Tear everything down (stops AWS costs)
	terraform -chdir=$(AWS_DIR) destroy
