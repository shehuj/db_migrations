# Remote state backend.
#
# The backend is intentionally left "partial": concrete values (bucket, key,
# region, dynamodb_table) are supplied at init time via `-backend-config` so the
# same code can target multiple environments without editing tracked files.
#
# Example:
#   terraform init \
#     -backend-config="bucket=my-tfstate-bucket" \
#     -backend-config="key=db-migrations/dev/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=my-tf-locks" \
#     -backend-config="encrypt=true"
#
# See terraform/backend.hcl.example for a ready-to-copy file.
terraform {
  backend "s3" {}
}
