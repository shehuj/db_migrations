# AWS Database Migration Demo

Production-grade, infrastructure-as-code demonstration of migrating a
self-managed **MySQL on EC2** database to **Amazon RDS for MySQL** using **AWS
Database Migration Service (DMS)** with full-load + change data capture (CDC).

Provisioning is split by concern:

| Concern | Tool | Location |
| --- | --- | --- |
| Infrastructure (VPC, EC2, RDS, DMS, IAM, monitoring) | Terraform (modular) | `terraform/` |
| Source database configuration (install MySQL, enable binlog, seed data) | Ansible over **SSM** (keyless) | `ansible/` |
| CI/CD — **deploy** (infra + config) and manual **migrate** | GitHub Actions (OIDC) | `.github/workflows/` |
| Helper scripts / seed SQL | Bash + SQL | `scripts/` |

The source host is **private and SSM-only** — no SSH, no key pair, no public IP.
Deploying the stack and running the migration are **two separate flows**: deploy
gets the databases ready; a manually-triggered migrate flow moves the data.

## Architecture

```text
                          VPC (10.20.0.0/16)
  ┌───────────────────────────────────────────────────────────────┐
  │  Public subnets      Private subnets (source, RDS, DMS, SSM)   │
  │  ┌─────────┐         ┌───────────────┐    ┌───────────────┐    │
  │  │   NAT   │         │  EC2 (source) │    │  DMS replic.  │    │
  │  │ gateway │◄──apt───│  MySQL 8.0    │    │  instance     │──► │ RDS MySQL
  │  └─────────┘         │  Ansible-cfg  │◄CDC│               │    │ (target)
  │                      └───────┬───────┘    └───────────────┘    │
  │                   SSM endpoints (ssm/ssmmessages/ec2messages)  │
  └──────────────────────────────┼────────────────────────────────┘
                                 │ SSM (Ansible, no SSH/no public IP)
                             GitHub Actions
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
│       ├── networking/        # VPC, subnets, NAT, SGs, SSM interface endpoints
│       ├── iam/               # DMS service roles + EC2 instance profile (SSM + S3)
│       ├── ec2/               # private source MySQL host (SSM-only)
│       ├── rds/               # target RDS MySQL + subnet/parameter groups
│       ├── dms/               # replication instance, endpoints, task
│       └── monitoring/        # SNS topic + CloudWatch alarms
├── ansible/
│   ├── site.yml               # entry playbook
│   ├── ansible.cfg            # enable_plugins: host_list + aws_ec2
│   ├── group_vars/all.yml     # aws_ssm connection defaults (bucket, region)
│   ├── inventory/aws_ec2.yml  # dynamic inventory (by instance id) for local runs
│   ├── requirements.yml       # amazon.aws, ansible.mysql, community.aws
│   └── roles/mysql_source/    # install MySQL, enable ROW binlog, users, seed
├── scripts/
│   ├── install_mysql.sh       # standalone fallback installer
│   ├── populate_db.sql        # sample schema + seed data
│   └── teardown.sh            # complete per-env cleanup flow
├── docs/iam/                  # deploy-role DMS + SSM policies, service-role helpers
├── .github/workflows/
│   ├── ci.yml                 # fmt/validate/tflint/ansible-lint on PRs
│   ├── deploy.yml             # preflight → plan → apply → configure (SSM, OIDC)
│   ├── migrate.yml            # manual DMS migration for dev/prod
│   └── destroy.yml            # gated teardown (workflow_dispatch)
└── Makefile                   # local convenience targets
```

## Prerequisites

You provide these once, out of band:

- Terraform >= 1.5, Ansible (`ansible-core` >= 2.16)
- An **S3 bucket + DynamoDB table** for remote state/locking
- A **GitHub OIDC provider + IAM role** in your AWS account that trusts this repo
  (the role needs to manage VPC/EC2/RDS/DMS/IAM/CloudWatch/SNS **and** drive SSM)
- An **existing S3 bucket** for Ansible's SSM file transfer (default
  `bathbucket31`, set via `ssm_transfer_bucket`) in the deployment region
- The repository secrets/variables below

No EC2 key pair is required — the source host is private and configured over SSM.

### Required configuration

Set these under **Settings → Secrets and variables → Actions** (or with the
`gh` CLI). The `preflight` job fails fast and lists any that are missing.

```bash
gh secret set AWS_ROLE_ARN           --body 'arn:aws:iam::<acct>:role/<deploy-role>'
gh secret set TF_BACKEND_BUCKET      --body '<your-tfstate-bucket>'
gh secret set TF_BACKEND_TABLE       --body '<your-lock-table>'
gh secret set DMS_DB_PASSWORD        --body '<strong-password>'
gh secret set RDS_ADMIN_PASSWORD     --body '<strong-password>'
gh secret set SOURCE_DB_ADMIN_PASSWORD --body '<strong-password>'   # used by Ansible
gh variable set AWS_REGION           --body 'us-east-1'             # optional (defaults to us-east-1)
```

There is **no `SSH_PRIVATE_KEY`** anymore — access is SSM-only.

### Deploy-role permissions

The IAM role in `AWS_ROLE_ARN` must be allowed to manage every service in the
stack, plus drive Ansible over SSM. Beyond the usual
VPC/EC2/RDS/CloudWatch/SNS/IAM and S3/DynamoDB (state) permissions, attach the
two reference policies:

```bash
# DMS management (start/stop task, endpoints, test-connection, table stats)
aws iam put-role-policy --role-name <your-deploy-role> \
  --policy-name db-migration-dms \
  --policy-document file://docs/iam/deploy-role-dms-policy.json

# SSM session + the transfer bucket (for the aws_ssm Ansible connection)
aws iam put-role-policy --role-name <your-deploy-role> \
  --policy-name db-migration-ssm \
  --policy-document file://docs/iam/deploy-role-ssm-policy.json
```

(The EC2 instance role's access to the transfer bucket is created by Terraform.)

### Existing DMS service roles

`dms-vpc-role` and `dms-cloudwatch-logs-role` are fixed-name, account-level
singletons DMS looks up globally. This project has **Terraform own them**
(`manage_dms_service_roles = true`, the default and set in `environments/*`).

Because they are account-wide, Terraform can only create them if they don't
already exist. If the account already has them (from a prior DMS console use or
a partial apply — often *misconfigured*, which shows up as
`The IAM Role ... is not configured properly`), remove them **once** so
Terraform can create clean, correctly-configured copies:

```bash
./docs/iam/delete-dms-service-roles.sh   # IAM-admin creds; deletes both roles
```

> Only run this on an account where no other DMS workload depends on those
> shared roles.

After that, every apply creates and reconciles them via Terraform — no manual
steps. (If instead you must leave the roles account-managed, set
`manage_dms_service_roles = false` and repair them in place with
`./docs/iam/fix-dms-service-roles.sh`.)

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

# 4. Configure the source MySQL host over SSM (needs session-manager-plugin
#    installed locally, plus the community.aws collection)
export DMS_DB_PASSWORD="$TF_VAR_dms_db_password"
export SSM_TRANSFER_BUCKET=bathbucket31
make configure     # uses the dynamic inventory -> instance id -> aws_ssm
```

The databases are now ready. To move data, run the **migration** flow (below) —
it's intentionally separate from deploy.

## CI/CD

Two OIDC-authenticated flows (no static AWS keys), plus PR checks:

- **`ci.yml`** — every PR: `terraform fmt`/`validate`, `tflint`, `ansible-lint`,
  and a playbook syntax check. No cloud credentials needed.
- **`deploy.yml`** — push to `main` or manual dispatch: `preflight` (verifies
  secrets) → `plan` → `apply` (GitHub-Environment gated) → `configure` (Ansible
  **over SSM**). Gets the databases ready; does **not** migrate data. The
  `configure` job installs the `session-manager-plugin`, waits for the instance
  to register with SSM, then runs the playbook against the exact instance id
  from the Terraform output (`-i "<instance-id>,"`).
- **`migrate.yml`** — **manual only** (`workflow_dispatch`, pick `dev`/`prod`):
  tests the DMS endpoint connections, starts the replication task, and reports
  status + table statistics. Environment-gated for required reviewers.

Required repository configuration:

| Type | Name | Purpose |
| --- | --- | --- |
| Variable | `AWS_REGION` | Deployment region (optional; defaults to `us-east-1`) |
| Secret | `AWS_ROLE_ARN` | IAM role assumed via OIDC |
| Secret | `TF_BACKEND_BUCKET` / `TF_BACKEND_TABLE` | Remote state + lock |
| Secret | `SOURCE_DB_ADMIN_PASSWORD` / `DMS_DB_PASSWORD` / `RDS_ADMIN_PASSWORD` | DB credentials |

## Design notes

- **SSM-only, no SSH.** The source host is private with no public IP and no key
  pair. Ansible connects via the `aws_ssm` plugin through interface endpoints;
  there is no port 22 anywhere and no SSH key to manage or leak.
- **Deploy vs migrate.** Deploying the stack and running the migration are
  separate flows — data movement is a deliberate, manually-triggered action.
- **Separation of concern.** Terraform never installs or configures MySQL —
  the EC2 module does only a minimal bootstrap (Python + SSM agent) so Ansible
  owns all database configuration idempotently.
- **CDC readiness.** The Ansible role enables `binlog_format=ROW` /
  `binlog_row_image=FULL`, writes the drop-in as `zz-dms.cnf` so it wins over the
  packaged `mysqld.cnf` bind-address, and asserts binary logging is on.
- **Least privilege.** DMS connects with a dedicated user holding only
  `SELECT, RELOAD, REPLICATION CLIENT, REPLICATION SLAVE`.
- **No secrets in code.** All passwords flow through `TF_VAR_*` / CI secrets /
  Ansible `--extra-vars`; `.gitignore` blocks state, tfvars, and keys.
- **Reproducible state.** S3 backend is partial and supplied per-environment at
  `init` time, so the same code targets dev and prod.
- **Deterministic Ansible targeting.** CI configures the single instance id from
  `terraform output`, not whatever the dynamic inventory finds.
- **Resilient DMS setup.** The engine version floats on the AWS regional default
  (pinning a stale version fails), and a `time_sleep` after the IAM service roles
  covers IAM propagation before DMS validates them.

## Troubleshooting

Issues hit while standing this up, and their fixes:

| Symptom | Cause & fix |
| --- | --- |
| `preflight` fails listing missing secrets | Set them — see [Required configuration](#required-configuration). |
| `AccessDeniedException` on `dms:*` | Attach `docs/iam/deploy-role-dms-policy.json` to the deploy role. |
| `EntityAlreadyExists: dms-vpc-role` | The singleton roles exist. Run `docs/iam/delete-dms-service-roles.sh` once, then Terraform owns them. |
| `The IAM Role ... is not configured properly` | A pre-existing role is misconfigured, or IAM hasn't propagated. Delete + let Terraform recreate (the `time_sleep` covers propagation), or `docs/iam/fix-dms-service-roles.sh`. |
| `No replication engine found with version` | Leave `dms_engine_version = ""` so AWS picks the regional default. |
| Ansible: instance not registered with SSM | The host needs egress to the SSM endpoints. Confirm the interface endpoints are up and the instance role has `AmazonSSMManagedInstanceCore`; the deploy job waits up to ~5 min. |
| Ansible: `aws_ssm` connection / S3 access denied | The deploy role needs `docs/iam/deploy-role-ssm-policy.json`, and `ssm_transfer_bucket` must exist in the deployment region. |
| DMS target: `Cannot create Exception table` | The RDS target user can't create tables in `appdb` — grant it, or drop leftover `awsdms_*` tables from a failed run. |
| Playbook assert fails on `mysql_source_app_password` | Set the `SOURCE_DB_ADMIN_PASSWORD` secret. |

## Cleanup

A plain `terraform destroy` is not enough: a running DMS task blocks endpoint
deletion, prod RDS has deletion protection, and an earlier replaced instance can
linger as an orphan. Use the complete flow, which handles all of that.

**Locally** (per environment — the account may have both `dev` and `prod`):

```bash
export AWS_REGION=us-east-1
export TF_BACKEND_BUCKET=... TF_BACKEND_TABLE=...        # or a terraform/backend.hcl
export TF_VAR_dms_db_password=... TF_VAR_rds_admin_password=...
make teardown ENV=dev      # -> scripts/teardown.sh dev
make teardown ENV=prod
```

The teardown flow:

1. **Stops** any running DMS replication task (so endpoints/instance can delete).
2. **Clears** RDS deletion protection (a targeted apply — no-op if already off).
3. **`terraform destroy`** removes every state-managed resource (VPC, EC2, RDS,
   DMS, IAM roles incl. `dms-vpc-role`, monitoring).
4. **Sweeps** any orphaned instances tagged `Project=aws-db-migration` for the env.

**Via CI:** run the **Destroy** workflow (`workflow_dispatch`) — pick the
environment and type `destroy` to confirm. It's gated by the GitHub Environment,
so add required reviewers for `prod`.

> **Not removed** (they're prerequisites you created, not repo resources): the
> remote-state S3 bucket, the DynamoDB lock table, and the GitHub OIDC provider +
> deploy IAM role. Delete those manually if you're done for good — and empty the
> state bucket first (it's versioned).

For a quick, raw destroy of a single environment with no pre/post steps:
`make destroy ENV=dev`.
