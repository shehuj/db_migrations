#!/usr/bin/env bash
###############################################################################
# teardown.sh — completely remove everything the repo provisions for ONE env.
#
# Order matters:
#   1. Stop DMS replication tasks   (a running task blocks endpoint/instance delete)
#   2. Clear RDS deletion protection (destroy fails while it's on — prod default)
#   3. terraform destroy            (all state-managed resources)
#   4. Sweep orphans by tag         (anything not in state, e.g. replaced instances)
#
# Usage:
#   export AWS_REGION=us-east-1
#   export TF_BACKEND_BUCKET=... TF_BACKEND_TABLE=...     # or provide terraform/backend.hcl
#   export TF_VAR_dms_db_password=... TF_VAR_rds_admin_password=...
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
: "${TF_VAR_dms_db_password:?set TF_VAR_dms_db_password}"
: "${TF_VAR_rds_admin_password:?set TF_VAR_rds_admin_password}"

# --- 1. Stop DMS replication tasks ------------------------------------------
echo "==> [1/4] Stopping DMS tasks"
for arn in $(aws dms describe-replication-tasks --region "$REGION" \
    --query "ReplicationTasks[?starts_with(ReplicationTaskIdentifier,'${PREFIX}')].ReplicationTaskArn" \
    --output text 2>/dev/null); do
  st=$(aws dms describe-replication-tasks --region "$REGION" \
       --filters "Name=replication-task-arn,Values=$arn" \
       --query 'ReplicationTasks[0].Status' --output text 2>/dev/null || echo unknown)
  if [ "$st" = "running" ] || [ "$st" = "starting" ]; then
    echo "   stopping $arn"
    aws dms stop-replication-task --region "$REGION" --replication-task-arn "$arn" >/dev/null || true
    aws dms wait replication-task-stopped --region "$REGION" \
      --filters "Name=replication-task-arn,Values=$arn" 2>/dev/null || true
  fi
done

# --- 2/3. Terraform init + destroy ------------------------------------------
cd "$TF_DIR"
echo "==> [2/4] terraform init"
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

echo "==> [3/4] Clearing RDS deletion protection, then destroying"
terraform apply -auto-approve -var-file="environments/${ENV}.tfvars" \
  -var "rds_deletion_protection=false" \
  -target=module.rds.aws_db_instance.this || true

terraform destroy -auto-approve -var-file="environments/${ENV}.tfvars"

# --- 4. Orphan sweep (tagged for this project but not in state) --------------
echo "==> [4/4] Sweeping orphans tagged Project=${PROJECT},Environment=${ENV}"
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
