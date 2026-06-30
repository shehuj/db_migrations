# AWS Database Migration Demo

Production-grade, infrastructure-as-code demonstration of migrating a
self-managed **MySQL on EC2** database to **Amazon RDS for MySQL** using **AWS
Database Migration Service (DMS)** with full-load + change data capture (CDC).

Provisioning is split by concern:

| Concern | Tool | Location |
| --- | --- | --- |
| Infrastructure (VPC, EC2, RDS, DMS, IAM, monitoring) | Terraform (modular) | `terraform/` |
| Source database configuration (install MySQL, enable binlog, seed data) | Ansible | `ansible/` |
| CI/CD (validate → plan → apply → configure) | GitHub Actions (OIDC) | `.github/workflows/` |
| Helper scripts / seed SQL | Bash + SQL | `scripts/` |

## Architecture

```text
                          VPC (10.20.0.0/16)
  ┌───────────────────────────────────────────────────────────────┐
  │  Public subnets                Private subnets                 │
  │  ┌───────────────┐             ┌───────────────┐               │
  │  │  EC2 (source) │   binlog    │  DMS replic.  │   apply       │
  │  │  MySQL 8.0    │◄────CDC─────│  instance     │──────────────►│ RDS MySQL
  │  │  Ansible-cfg  │             │               │               │ (target)
  │  └───────────────┘             └───────────────┘               │
  │         ▲                              │                       │
  └─────────┼──────────────────────────────┼──────────────────────┘
            │ SSH/SSM (Ansible)             │ CloudWatch metrics
        GitHub Actions                   SNS alarms (monitoring module)
```

DMS reads the source via a least-privilege replication user, performs an initial
full load, then streams ongoing changes from the MySQL binary log to RDS.

## Repository layout

```text
.
├── terraform/
│   ├── main.tf                # root module composition
│   ├── variables.tf / outputs.tf / locals.tf / providers.tf / versions.tf
│   ├── backend.tf             # partial S3 backend (configured at init)
│   ├── bootstrap/             # one-time: state backend + OIDC provider + deploy role
│   ├── environments/          # dev.tfvars / prod.tfvars
│   └── modules/
│       ├── networking/        # VPC, subnets, NAT, route tables, security groups
│       ├── iam/               # DMS service roles + EC2 instance profile
│       ├── ec2/               # source MySQL host (minimal bootstrap only)
│       ├── rds/               # target RDS MySQL + subnet/parameter groups
│       ├── dms/               # replication instance, endpoints, task
│       └── monitoring/        # SNS topic + CloudWatch alarms
├── ansible/
│   ├── site.yml               # entry playbook
│   ├── ansible.cfg            # uses dynamic aws_ec2 inventory
│   ├── inventory/aws_ec2.yml  # discovers host by Terraform tags
│   ├── requirements.yml       # amazon.aws, community.mysql collections
│   └── roles/mysql_source/    # install MySQL, enable ROW binlog, users, seed
├── scripts/
│   ├── install_mysql.sh       # standalone fallback installer
│   └── populate_db.sql        # sample schema + seed data
├── .github/workflows/
│   ├── ci.yml                 # fmt/validate/tflint/ansible-lint on PRs
│   └── terraform.yml          # plan → apply → ansible configure (OIDC)
└── Makefile                   # local convenience targets
```

## Prerequisites

- Terraform >= 1.5, Ansible (`ansible-core` >= 2.16)
- An AWS account + admin credentials for the one-time bootstrap below
- An EC2 key pair if you want SSH/Ansible access from your laptop

## First-time setup (bootstrap)

The CI pipeline needs three things it cannot create for itself: a remote-state
backend (S3 + DynamoDB), a GitHub OIDC provider, and an IAM role for Actions to
assume. The `terraform/bootstrap/` stack provisions them. Run it **once**,
locally, with admin credentials (it uses local state — no backend):

```bash
cd terraform/bootstrap
terraform init
terraform apply -var github_owner=<your-org> -var github_repo=db_migrations
```

Then push the outputs into the repo (the stack prints the exact `gh` commands as
the `gh_cli_commands` output):

```bash
gh secret set AWS_ROLE_ARN       --body "$(terraform output -raw deploy_role_arn)"
gh secret set TF_BACKEND_BUCKET  --body "$(terraform output -raw state_bucket)"
gh secret set TF_BACKEND_TABLE   --body "$(terraform output -raw lock_table)"
gh variable set AWS_REGION       --body "$(terraform output -raw region)"
# Database secrets (choose strong values):
gh secret set DMS_DB_PASSWORD          --body '...'
gh secret set RDS_ADMIN_PASSWORD       --body '...'
gh secret set SOURCE_DB_ADMIN_PASSWORD --body '...'
gh secret set SSH_PRIVATE_KEY < path/to/keypair.pem
```

The deploy pipeline's `preflight` job fails fast with a clear message if any of
these secrets are missing, so you'll know immediately if something wasn't set.

> If your account already has a GitHub OIDC provider, apply with
> `-var create_oidc_provider=false`.

## Quick start (local)

```bash
# 1. Provide secrets via environment (never commit these)
export TF_VAR_dms_db_password='...'        # DMS source replication user
export TF_VAR_rds_admin_password='...'     # target RDS master password
export SOURCE_DB_ADMIN_PASSWORD='...'      # source admin (used by Ansible only)

# 2. Configure the remote state backend
cp terraform/backend.hcl.example terraform/backend.hcl   # edit bucket/table
make init

# 3. Review and apply the infrastructure
make plan ENV=dev
make apply ENV=dev

# 4. Configure the source MySQL host with Ansible
export DMS_DB_PASSWORD="$TF_VAR_dms_db_password"
make configure
```

Then start the migration from the DMS console (or set `dms_start_task = true`
and re-apply) and watch the table statistics / CloudWatch alarms.

## CI/CD

- **`ci.yml`** runs on every PR: `terraform fmt`/`validate`, `tflint`, and
  `ansible-lint` + playbook syntax check. No cloud credentials needed.
- **`terraform.yml`** runs on push to `main` (or manual dispatch):
  `plan` → `apply` (gated by a GitHub Environment for required reviewers) →
  `configure` (Ansible). Authentication uses **GitHub OIDC**, so no static AWS
  keys are stored.

Required repository configuration:

| Type | Name | Purpose |
| --- | --- | --- |
| Variable | `AWS_REGION` | Deployment region (optional; defaults to `us-east-1`) |
| Secret | `AWS_ROLE_ARN` | IAM role assumed via OIDC |
| Secret | `TF_BACKEND_BUCKET` / `TF_BACKEND_TABLE` | Remote state + lock |
| Secret | `SOURCE_DB_ADMIN_PASSWORD` / `DMS_DB_PASSWORD` / `RDS_ADMIN_PASSWORD` | DB credentials |
| Secret | `SSH_PRIVATE_KEY` | PEM for the EC2 key pair (Ansible step) |

## Design notes

- **Separation of concern.** Terraform never installs or configures MySQL —
  the EC2 module does only a minimal bootstrap (Python + SSM) so Ansible can own
  all database configuration idempotently.
- **CDC readiness.** The Ansible role enables `binlog_format=ROW` /
  `binlog_row_image=FULL` and asserts binary logging is on before finishing.
- **Least privilege.** DMS connects with a dedicated user holding only
  `SELECT, RELOAD, REPLICATION CLIENT, REPLICATION SLAVE`.
- **No secrets in code.** All passwords flow through `TF_VAR_*` / CI secrets /
  Ansible `--extra-vars`; `.gitignore` blocks state, tfvars, and keys.
- **Reproducible state.** S3 backend is partial and supplied per-environment at
  `init` time, so the same code targets dev and prod.

## Cleanup

```bash
make destroy ENV=dev
```

> RDS deletion protection is enabled in `prod.tfvars`; disable it before
> destroying a production stack.
