#!/usr/bin/env bash
###############################################################################
# delete-dms-service-roles.sh
#
# Removes the account-level DMS service roles so Terraform can create and own
# them (manage_dms_service_roles = true). Run ONCE, with IAM-admin credentials,
# before the deploy pipeline:
#
#   ./docs/iam/delete-dms-service-roles.sh
#
# WARNING: dms-vpc-role and dms-cloudwatch-logs-role are shared, account-wide
# singletons. Only run this if NO other DMS workload in the account depends on
# them. Idempotent: skips roles that don't exist.
###############################################################################
set -euo pipefail

ROLES=(dms-vpc-role dms-cloudwatch-logs-role)

for role in "${ROLES[@]}"; do
  if ! aws iam get-role --role-name "${role}" >/dev/null 2>&1; then
    echo ">> ${role} does not exist — skipping"
    continue
  fi

  echo ">> Deleting ${role}"

  # Detach managed policies
  for arn in $(aws iam list-attached-role-policies --role-name "${role}" \
      --query 'AttachedPolicies[].PolicyArn' --output text); do
    echo "   detaching ${arn##*/}"
    aws iam detach-role-policy --role-name "${role}" --policy-arn "${arn}"
  done

  # Delete inline policies
  for name in $(aws iam list-role-policies --role-name "${role}" \
      --query 'PolicyNames[]' --output text); do
    echo "   deleting inline policy ${name}"
    aws iam delete-role-policy --role-name "${role}" --policy-name "${name}"
  done

  # Remove instance-profile associations (none expected, but be safe)
  for prof in $(aws iam list-instance-profiles-for-role --role-name "${role}" \
      --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || true); do
    echo "   removing from instance profile ${prof}"
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "${prof}" --role-name "${role}"
  done

  aws iam delete-role --role-name "${role}"
  echo "   deleted"
done

echo "Done. Set manage_dms_service_roles = true and run the deploy pipeline."
