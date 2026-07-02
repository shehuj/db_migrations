# AWS Database Migration Demo

Production-grade, infrastructure-as-code pipeline that migrates data from a
**developer-facing MySQL database into a locked-down production database** using
**AWS Database Migration Service (DMS)** with full-load + change data capture
(CDC). Both databases are **Amazon RDS for MySQL**.

- **dev DB (source)** — publicly reachable (security-group-locked to your IPs).
  Developers load data here directly from their machines.
- **prod DB (target)** — private, no public endpoint. The **only** ways in are
  the DMS migration (which writes into it) and an **SSM bastion** for admins.
- **DMS** replicates dev → prod (initial load, then ongoing CDC).

| Concern | Tool | Location |
| --- | --- | --- |
| Infrastructure (VPC, 2× RDS, DMS, bastion, IAM, monitoring) | Terraform (modular) | `terraform/` |
| Dev DB prep (binlog retention, DMS user, seed) | SQL script (run locally) | `scripts/` |
| CI/CD — **deploy** (infra) and manual **migrate** | GitHub Actions (OIDC) | `.github/workflows/` |

## Architecture

```text
                              VPC (10.20.0.0/16)
  ┌──────────────────────────────────────────────────────────────────┐
  │ Public subnets                Private subnets                     │
  │ ┌───────────────┐             ┌──────────────┐   ┌──────────────┐ │
  │ │ dev DB (RDS)  │◄──full-load─│ DMS replic.  │──►│ prod DB (RDS)│ │
  │ │ SOURCE        │────CDC──────►│ instance     │   │ TARGET       │ │
  │ │ public, SG-   │             └──────────────┘   │ private      │ │
  │ │ locked        │             ┌──────────────┐   └──────▲───────┘ │
  │ └──────▲────────┘             │ SSM bastion  │──────────┘         │
  │        │                      └──────▲───────┘  (port-forward)    │
  └────────┼─────────────────────────────┼────────────────────────────┘
           │ MySQL from dev CIDRs         │ aws ssm start-session
      developers (load data)         admins (reach prod DB)
```

## Repository layout

```text
.
├── terraform/
│   ├── main.tf                # root composition (rds_source, rds_target, ec2, dms)
│   ├── variables.tf / outputs.tf / locals.tf / providers.tf / versions.tf
│   ├── backend.tf             # partial S3 backend (configured at init)
│   ├── environments/          # dev.tfvars / prod.tfvars (deployment tiers)
│   └── modules/
│       ├── networking/        # VPC, subnets, NAT, SGs, SSM interface endpoints
│       ├── iam/               # DMS service roles + bastion instance profile
│       ├── rds/               # reusable MySQL instance (role = source | target)
│       ├── ec2/               # SSM bastion (jump host for the private prod DB)
│       ├── dms/               # replication instance, endpoints, task
│       └── monitoring/        # SNS topic + CloudWatch alarms
├── scripts/
│   ├── setup_source_db.sh     # prep dev DB: binlog retention + DMS user + seed
│   ├── populate_db.sql        # sample schema + seed data
│   └── teardown.sh            # complete per-tier cleanup flow
├── docs/iam/                  # deploy-role policies + DMS service-role helpers
├── .github/workflows/
│   ├── ci.yml                 # terraform fmt/validate/tflint on PRs
│   ├── deploy.yml             # preflight → plan → apply (infra only, OIDC)
│   ├── migrate.yml            # manual DMS migration (dev → prod)
│   └── destroy.yml            # gated teardown (workflow_dispatch)
└── Makefile                   # local convenience targets
```

## Prerequisites

You provide these once, out of band:

- Terraform >= 1.5, the MySQL client (for the dev DB setup script)
- An **S3 bucket + DynamoDB table** for remote state/locking
- A **GitHub OIDC provider + IAM role** that trusts this repo (manages
  VPC/EC2/RDS/DMS/IAM/CloudWatch/SNS + S3/DynamoDB state)
- The repository secrets/variables below
- Your IP/CIDR to allow into the dev DB (`dev_db_allowed_cidrs`)

No EC2 key pair, no SSH — the bastion is SSM-only and the databases are managed.

### Required configuration

```bash
gh secret set AWS_ROLE_ARN        --body 'arn:aws:iam::<acct>:role/<deploy-role>'
gh secret set TF_BACKEND_BUCKET   --body '<your-tfstate-bucket>'
gh secret set TF_BACKEND_TABLE    --body '<your-lock-table>'
gh secret set RDS_ADMIN_PASSWORD  --body '<strong-password>'   # master pw (both DBs)
gh secret set DMS_DB_PASSWORD     --body '<strong-password>'   # DMS user on the source DB
gh variable set AWS_REGION        --body 'us-east-1'           # optional (defaults to us-east-1)
```

The `preflight` job fails fast and lists any that are missing.

### Deploy-role permissions

Attach the DMS reference policy (baseline CI roles rarely include `dms:*`):

```bash
aws iam put-role-policy --role-name <your-deploy-role> \
  --policy-name db-migration-dms \
  --policy-document file://docs/iam/deploy-role-dms-policy.json
```

Whoever needs to reach the **prod DB over the SSM bastion** (you, from a laptop,
or a role) also needs the SSM policy:

```bash
aws iam put-role-policy --role-name <your-role> \
  --policy-name db-migration-ssm \
  --policy-document file://docs/iam/deploy-role-ssm-policy.json
```

### Existing DMS service roles

`dms-vpc-role` and `dms-cloudwatch-logs-role` are fixed-name, account-level
singletons. Terraform owns them (`manage_dms_service_roles = true`). If the
account already has them, remove once so Terraform can recreate clean copies:

```bash
./docs/iam/delete-dms-service-roles.sh   # IAM-admin creds
```

(If they must stay account-managed, set `manage_dms_service_roles = false` and
repair with `./docs/iam/fix-dms-service-roles.sh`.)

## Usage

### 1. Deploy the infrastructure

```bash
export TF_VAR_rds_admin_password='...'
export TF_VAR_dms_db_password='...'
cp terraform/backend.hcl.example terraform/backend.hcl   # edit bucket/table
make init
make plan ENV=dev
make apply ENV=dev
```

…or push to `main` / run the **Deploy** workflow. This provisions both RDS
instances, the bastion, and DMS — it does **not** load data or migrate.

### 2. Prepare + load the dev (source) DB

Your IP must be in `dev_db_allowed_cidrs`. Then:

```bash
export DEV_DB_HOST="$(cd terraform && terraform output -raw dev_db_address)"
export RDS_ADMIN_PASSWORD='...'   # master password
export DMS_DB_PASSWORD='...'      # password for the DMS user to create
make setup-source                 # binlog retention + DMS user + seed data
```

Load whatever additional data you want straight into the dev DB with any MySQL
client — it's a normal, reachable database.

### 3. Run the migration (dev → prod)

**Actions → Migrate → Run workflow** → pick `dev` or `prod` tier. It tests the
DMS endpoint connections, starts the replication task, and reports status +
table statistics. With `full-load-and-cdc`, the initial load runs and then
changes stream continuously.

## Connecting to the databases

```bash
# dev DB — public, connect directly (your IP must be allowed):
mysql -h "$(cd terraform && terraform output -raw dev_db_address)" -u admin -p appdb

# prod DB — private, reach it via SSM port forwarding through the bastion:
BASTION=$(cd terraform && terraform output -raw bastion_instance_id)
PROD=$(cd terraform && terraform output -raw prod_db_address)
aws ssm start-session --target "$BASTION" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$PROD\"],\"portNumber\":[\"3306\"],\"localPortNumber\":[\"3308\"]}"
#   then, in another shell:
#   mysql -h 127.0.0.1 -P 3308 -u admin -p appdb
```

Requires the AWS CLI + `session-manager-plugin` and `ssm:StartSession` rights.

## Design notes

- **Dev open, prod locked.** The source DB is developer-reachable (SG-locked) so
  data lands there naturally; the target DB has no public endpoint and is only
  writable by DMS and reachable by admins through the SSM bastion.
- **Managed databases.** Both sides are RDS — no self-managed MySQL, no host to
  patch or configure, no SSH keys anywhere.
- **CDC readiness.** The source parameter group sets `binlog_format=ROW` /
  `binlog_row_image=FULL`; the setup script enables RDS binlog retention and
  creates a least-privilege DMS user (`SELECT, RELOAD, REPLICATION CLIENT,
  REPLICATION SLAVE`).
- **No secrets in code.** Passwords flow through `TF_VAR_*` / CI secrets;
  `.gitignore` blocks state, tfvars, and keys.
- **Deploy vs migrate.** Provisioning and data movement are separate flows —
  migration is a deliberate, manually-triggered action.
- **Resilient DMS.** Engine version floats on the AWS regional default, and a
  `time_sleep` after the IAM service roles covers IAM propagation.

## Troubleshooting

| Symptom | Cause & fix |
| --- | --- |
| `preflight` fails listing missing secrets | Set them (see Required configuration). |
| `AccessDeniedException` on `dms:*` | Attach `docs/iam/deploy-role-dms-policy.json` to the deploy role. |
| `EntityAlreadyExists: dms-vpc-role` | Run `docs/iam/delete-dms-service-roles.sh` once, then Terraform owns them. |
| `The IAM Role ... is not configured properly` | Delete + let Terraform recreate (its `time_sleep` covers propagation), or `docs/iam/fix-dms-service-roles.sh`. |
| Can't reach the dev DB | Your IP isn't in `dev_db_allowed_cidrs`. Add it and re-apply. |
| DMS source connection fails | Run `scripts/setup_source_db.sh` (creates the DMS user + binlog retention). |
| DMS target: `Cannot create Exception table` | The target user can't create tables in `appdb`; grant it or drop leftover `awsdms_*` tables. |
| `ssm:StartSession` denied | Attach `docs/iam/deploy-role-ssm-policy.json` to your role. |

## Cleanup

A plain `terraform destroy` mishandles ordering (running DMS task blocks
deletion, prod RDS has deletion protection). Use the complete flow:

```bash
export AWS_REGION=us-east-1
export TF_BACKEND_BUCKET=... TF_BACKEND_TABLE=...
export TF_VAR_rds_admin_password=... TF_VAR_dms_db_password=...
make teardown ENV=dev
```

…or run the **Destroy** workflow (type `destroy` to confirm; Environment-gated).

> Not removed (you created them): the state bucket, lock table, and OIDC
> provider + deploy role. Empty the versioned state bucket before deleting it.
