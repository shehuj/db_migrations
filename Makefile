# Convenience targets for local development.
# Secrets are read from the environment as TF_VAR_* (see README).

TF_DIR ?= terraform
ENV    ?= dev

.PHONY: help fmt validate lint init plan apply destroy teardown setup-source clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

fmt: ## terraform fmt
	cd $(TF_DIR) && terraform fmt -recursive

validate: ## terraform validate (no backend)
	cd $(TF_DIR) && terraform init -backend=false && terraform validate

lint: ## tflint
	cd $(TF_DIR) && tflint --recursive

init: ## terraform init with backend (needs backend.hcl)
	cd $(TF_DIR) && terraform init -backend-config=backend.hcl

plan: ## terraform plan for ENV (default dev)
	cd $(TF_DIR) && terraform plan -var-file=environments/$(ENV).tfvars

apply: ## terraform apply for ENV
	cd $(TF_DIR) && terraform apply -var-file=environments/$(ENV).tfvars

destroy: ## Raw terraform destroy for ENV (no pre/post steps)
	cd $(TF_DIR) && terraform destroy -var-file=environments/$(ENV).tfvars

teardown: ## Full cleanup for ENV: stop DMS, clear protection, destroy, sweep orphans
	./scripts/teardown.sh $(ENV)

setup-source: ## Prep the dev/source DB: binlog retention + DMS user + seed data
	DEV_DB_HOST="$$(cd $(TF_DIR) && terraform output -raw dev_db_address)" \
		./scripts/setup_source_db.sh

clean: ## Remove local terraform plan artifacts
	find $(TF_DIR) -name tfplan -delete
