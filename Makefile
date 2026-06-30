# Convenience targets for local development.
# Secrets are read from the environment as TF_VAR_* (see README).

TF_DIR      ?= terraform
ANSIBLE_DIR ?= ansible
ENV         ?= dev

.PHONY: help fmt validate lint init plan apply destroy configure clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

fmt: ## terraform fmt
	cd $(TF_DIR) && terraform fmt -recursive

validate: ## terraform validate (no backend)
	cd $(TF_DIR) && terraform init -backend=false && terraform validate

lint: ## Lint Terraform + Ansible
	cd $(TF_DIR) && tflint --recursive
	cd $(ANSIBLE_DIR) && ansible-lint

init: ## terraform init with backend (needs backend.hcl)
	cd $(TF_DIR) && terraform init -backend-config=backend.hcl

plan: ## terraform plan for ENV (default dev)
	cd $(TF_DIR) && terraform plan -var-file=environments/$(ENV).tfvars

apply: ## terraform apply for ENV
	cd $(TF_DIR) && terraform apply -var-file=environments/$(ENV).tfvars

destroy: ## terraform destroy for ENV
	cd $(TF_DIR) && terraform destroy -var-file=environments/$(ENV).tfvars

configure: ## Run Ansible against the provisioned source host
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml && \
		ansible-playbook site.yml \
		  --extra-vars "mysql_source_app_password=$$SOURCE_DB_ADMIN_PASSWORD" \
		  --extra-vars "mysql_source_dms_password=$$DMS_DB_PASSWORD"

clean: ## Remove local terraform plan artifacts
	find $(TF_DIR) -name tfplan -delete
