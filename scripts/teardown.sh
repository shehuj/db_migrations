#!/usr/bin/env bash
###############################################################################
# teardown.sh — completely remove everything the repo provisions for ONE env.
#
# Order matters:
#   1. Clear prod RDS deletion protection (destroy fails while it's on)
#   2. terraform destroy                  (all state-managed resources)
#   3. Sweep orphans by tag               (anything not in state)
#
# Usage:
#   export AWS_REGION=us-east-1
#   export TF_BACKEND_BUCKET=... TF_BACKEND_TABLE=...   # or provide terraform/backend.hcl
#   export TF_VAR_rds_admin_password=...
#   ./scripts/teardown.sh dev
#
# Requires: awscli, terraform, and credentials allowed to delete the stack.
###############################################################################
set -euo pipefail

ENV="${1:-dev}"
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT:-aws-db-migration}"
PREFIX="${PROJECT}-${ENV}"
TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

echo "==> Teardown '${ENV}' (prefix ${PREFIX}) in ${REGION}"
: "${TF_VAR_rds_admin_password:?set TF_VAR_rds_admin_password}"

cd "$TF_DIR"

echo "==> [1/3] terraform init"
if [ -n "${TF_BACKEND_BUCKET:-}" ]; then
  terraform init -reconfigure \
    -backend-config="bucket=${TF_BACKEND_BUCKET}" \
    -backend-config="key=db-migrations/${ENV}/terraform.tfstate" \
    -backend-config="region=${REGION}" \
    -backend-config="dynamodb_table=${TF_BACKEND_TABLE}" \
    -backend-config="encrypt=true"
else
  terraform init -reconfigure -backend-config=backend.hcl
fi

echo "==> [2/3] Clearing prod RDS deletion protection, then destroying"
terraform apply -auto-approve -var-file="environments/${ENV}.tfvars" \
  -var "prod_db_deletion_protection=false" \
  -target=module.rds_prod.aws_db_instance.this || true

terraform destroy -auto-approve -var-file="environments/${ENV}.tfvars" \
  -var "prod_db_deletion_protection=false"

# --- 3. Orphan sweep (tagged for this project but not in state) --------------
echo "==> [3/3] Sweeping orphans tagged Project=${PROJECT},Environment=${ENV}"
orphans=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=${PROJECT}" "Name=tag:Environment,Values=${ENV}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
if [ -n "$orphans" ]; then
  echo "   terminating orphan instances: $orphans"
  aws ec2 terminate-instances --region "$REGION" --instance-ids $orphans >/dev/null || true
else
  echo "   no orphan instances"
fi

echo "==> Done. NOT removed (managed outside this repo, delete manually if desired):"
echo "    - remote state bucket / DynamoDB lock table"
echo "    - the GitHub OIDC provider + deploy IAM role"
echo "    Run again per environment (e.g. ./scripts/teardown.sh prod)."
