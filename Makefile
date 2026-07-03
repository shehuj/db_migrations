# Convenience targets for local development.
# Secrets are read from the environment (TF_VAR_* for Terraform,
# RDS_ADMIN_PASSWORD / APP_DB_PASSWORD for Ansible). See README.

TF_DIR      ?= terraform
ANSIBLE_DIR ?= ansible
ENV         ?= dev

.PHONY: help fmt validate lint init plan apply destroy teardown \
        ansible-deps configure-dev prod-tunnel configure-prod clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## --- Terraform --------------------------------------------------------------

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

teardown: ## Full cleanup for ENV: clear protection, destroy, sweep orphans
	./scripts/teardown.sh $(ENV)

## --- Ansible (configure + seed the databases) -------------------------------

ansible-deps: ## Install the community.mysql collection + PyMySQL driver
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml
	python3 -m pip install --quiet PyMySQL

configure-dev: ## Configure + seed the dev DB (public; needs RDS_ADMIN_PASSWORD)
	cd $(ANSIBLE_DIR) && DEV_DB_HOST="$$(cd ../$(TF_DIR) && terraform output -raw dev_db_address)" \
		ansible-playbook configure.yml --limit dev

prod-tunnel: ## Open the SSM port-forward to the prod DB (leave running)
	./scripts/prod_tunnel.sh

configure-prod: ## Configure + seed the prod DB (needs prod-tunnel open + RDS_ADMIN_PASSWORD)
	cd $(ANSIBLE_DIR) && ansible-playbook configure.yml --limit prod

clean: ## Remove local terraform plan artifacts
	find $(TF_DIR) -name tfplan -delete
