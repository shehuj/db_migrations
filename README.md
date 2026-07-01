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

You provide these once, out of band:

- Terraform >= 1.5, Ansible (`ansible-core` >= 2.16)
- An **S3 bucket + DynamoDB table** for remote state/locking
- A **GitHub OIDC provider + IAM role** in your AWS account that trusts this repo
  (the role needs permissions to manage VPC/EC2/RDS/DMS/IAM/CloudWatch/SNS)
- An EC2 key pair if you want SSH/Ansible access
- The repository secrets/variables below

### Required configuration

Set these under **Settings → Secrets and variables → Actions** (or with the
`gh` CLI). The pipeline's `preflight` job fails fast and lists any that are
missing.

```bash
gh secret set AWS_ROLE_ARN           --body 'arn:aws:iam::<acct>:role/<deploy-role>'
gh secret set TF_BACKEND_BUCKET      --body '<your-tfstate-bucket>'
gh secret set TF_BACKEND_TABLE       --body '<your-lock-table>'
gh secret set DMS_DB_PASSWORD        --body '<strong-password>'
gh secret set RDS_ADMIN_PASSWORD     --body '<strong-password>'
gh secret set SOURCE_DB_ADMIN_PASSWORD --body '<strong-password>'   # used by Ansible
gh secret set SSH_PRIVATE_KEY        < path/to/keypair.pem          # used by Ansible
gh variable set AWS_REGION           --body 'us-east-1'             # optional (defaults to us-east-1)
```

### Deploy-role permissions

The IAM role in `AWS_ROLE_ARN` must be allowed to manage every service in the
stack. DMS actions in particular are **not** covered by many baseline CI roles
(and are excluded from `PowerUserAccess` only via IAM — DMS itself is included,
but a hand-scoped role usually omits it). Attach the reference policy in
[`docs/iam/deploy-role-dms-policy.json`](docs/iam/deploy-role-dms-policy.json)
if you hit `AccessDeniedException` on `dms:*`:

```bash
aws iam put-role-policy \
  --role-name <your-deploy-role> \
  --policy-name db-migration-dms \
  --policy-document file://docs/iam/deploy-role-dms-policy.json
```

The role also needs the usual VPC/EC2/RDS/CloudWatch/SNS/IAM permissions (to
create the `dms-vpc-role` / `dms-cloudwatch-logs-role` and the EC2 instance
profile), plus S3/DynamoDB access to the state backend.

### Existing DMS service roles

`dms-vpc-role` and `dms-cloudwatch-logs-role` are fixed-name, account-level
singletons. If your account already has them (from a prior DMS console use or an
earlier apply), Terraform will fail with `EntityAlreadyExists`. Set
`manage_dms_service_roles = false` so Terraform skips creating them — DMS only
requires that they exist. `environments/dev.tfvars` ships with this set to
`false`; flip it to `true` for a fresh account that has never used DMS.

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
