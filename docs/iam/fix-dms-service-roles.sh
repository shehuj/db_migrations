#!/usr/bin/env bash
###############################################################################
# fix-dms-service-roles.sh
#
# Repairs the account-level DMS service roles (dms-vpc-role and
# dms-cloudwatch-logs-role) when they already exist but are "not configured
# properly" — i.e. missing the correct trust policy or managed policy.
#
# Run once, with credentials allowed to manage IAM (your admin, not the CI role
# unless it has iam:AttachRolePolicy / iam:UpdateAssumeRolePolicy on these roles):
#
#   ./docs/iam/fix-dms-service-roles.sh
#
# Idempotent: safe to re-run. Use this instead of managing the roles in
# Terraform (keep manage_dms_service_roles = false).
###############################################################################
set -euo pipefail

TRUST='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "dms.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}'

declare -A ROLES=(
  [dms-vpc-role]="arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  [dms-cloudwatch-logs-role]="arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
)

for role in "${!ROLES[@]}"; do
  policy_arn="${ROLES[$role]}"
  echo ">> Repairing ${role}"

  if ! aws iam get-role --role-name "${role}" >/dev/null 2>&1; then
    echo "   creating (did not exist)"
    aws iam create-role --role-name "${role}" \
      --assume-role-policy-document "${TRUST}" >/dev/null
  else
    echo "   fixing trust policy"
    aws iam update-assume-role-policy --role-name "${role}" \
      --policy-document "${TRUST}"
  fi

  echo "   attaching ${policy_arn##*/}"
  aws iam attach-role-policy --role-name "${role}" --policy-arn "${policy_arn}"
done

echo "Done. DMS service roles are configured. Re-run the deploy pipeline."
