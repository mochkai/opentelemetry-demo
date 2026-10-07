# Coralogix integration — included automatically by the base Makefile.
# All paths are relative to the repo root (where make runs).

CX_DIR       := vendors/coralogix
CX_S3_DIR    := $(CX_DIR)/terraform
CX_NS        := coralogix
CX_CHART_VER := 0.0.354

-include $(CX_DIR)/.env
export

DEMO_VALUES += $(CX_DIR)/helm/otel-demo-values.yaml

# Agent before demo, so the demo's first spans have somewhere to go.
UP_STEPS := aws cx-s3 kubeconfig repos cx-repo coralogix demo

.PHONY: cx-s3 cx-repo cx-secret coralogix cx-status destroy-coralogix cx-s3-destroy

# Connecting the buckets to Coralogix is done in the UI (Data Flow -> Setup Archive).
cx-s3: ## Provision the customer-owned S3 archive buckets
	terraform -chdir=$(CX_S3_DIR) init -upgrade
	terraform -chdir=$(CX_S3_DIR) apply

cx-repo:
	helm repo add coralogix https://cgx.jfrog.io/artifactory/coralogix-charts-virtual
	helm repo update

cx-secret:
	@test -n "$(CORALOGIX_PRIVATE_KEY)" || { echo "CORALOGIX_PRIVATE_KEY not set (see $(CX_DIR)/.env.example)"; exit 1; }
	kubectl create namespace $(CX_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n $(CX_NS) create secret generic coralogix-keys \
	  --from-literal=PRIVATE_KEY="$(CORALOGIX_PRIVATE_KEY)" --dry-run=client -o yaml | kubectl apply -f -

coralogix: cx-secret ## Install Coralogix Kubernetes Observability
	helm upgrade --install otel-coralogix-integration coralogix/otel-integration \
	  --version $(CX_CHART_VER) -n $(CX_NS) -f $(CX_DIR)/helm/coralogix-values.yaml --wait

cx-status: ## Show Coralogix collector pods
	kubectl get pods -n $(CX_NS) -o wide

destroy-coralogix:
	-helm uninstall otel-coralogix-integration -n $(CX_NS)

# Deliberately NOT part of `make down`: the archive is customer-owned data and the
# Coralogix UI archive connection points at it, so it outlives cluster rebuilds.
# Disconnect the archive in the Coralogix UI before running this.
cx-s3-destroy: ## Delete the S3 archive buckets AND their data (disconnect in UI first)
	terraform -chdir=$(CX_S3_DIR) destroy

# Hook into the base teardown: the agent is uninstalled with the demo.
destroy-k8s: destroy-coralogix
