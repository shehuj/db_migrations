# AWS Dev + Prod Database Provisioning

Infrastructure-as-code that provisions **two Amazon RDS for MySQL databases** — a
developer-facing **dev** database and a locked-down **prod** database — with
**Terraform** (modular) and configures/seeds them with **Ansible**.

- **dev DB** — publicly reachable (security-group-locked to your CIDRs).
  All developers connect directly from their machines.
- **prod DB** — private, no public endpoint. The **only** way in is an **SSM
  bastion** (port-forwarding through Session Manager).
- **Ansible** configures both databases: creates the schema, a least-privilege
  application user, and seeds sample data. Dev is reached directly; prod is
  reached through the SSM tunnel.

| Concern | Tool | Location |
| --- | --- | --- |
| Infrastructure (VPC, 2× RDS, bastion, IAM, monitoring) | Terraform (modular) | `terraform/` |
| Database config + seed (schema, app user, data) | Ansible (role) | `ansible/` |
| CI/CD — **deploy** (infra), **configure** (Ansible), **destroy** | GitHub Actions (OIDC) | `.github/workflows/` |

## Architecture

```text
                              VPC (10.20.0.0/16)
  ┌──────────────────────────────────────────────────────────────────┐
  │ Public subnets                Private subnets                     │
  │ ┌───────────────┐             ┌──────────────┐   ┌──────────────┐ │
  │ │ dev DB (RDS)  │             │ SSM bastion  │──►│ prod DB (RDS)│ │
  │ │ public,       │             └──────▲───────┘   │ private      │ │
  │ │ SG-locked     │                    │           └──────────────┘ │
  │ └──────▲────────┘                    │ (port-forward)             │
  └────────┼─────────────────────────────┼────────────────────────────┘
           │ MySQL from dev CIDRs         │ aws ssm start-session
     developers + Ansible            admins + Ansible (via tunnel)
```

## Repository layout

```text
.
├── terraform/
│   ├── main.tf                # root composition (rds_dev, rds_prod, ec2)
│   ├── variables.tf / outputs.tf / locals.tf / providers.tf / versions.tf
│   ├── backend.tf             # partial S3 backend (configured at init)
│   ├── environments/          # dev.tfvars / prod.tfvars (deployment tiers)
│   └── modules/
│       ├── networking/        # VPC, subnets, NAT, SGs, SSM interface endpoints
│       ├── iam/               # SSM bastion instance profile
│       ├── rds/               # reusable MySQL instance (role = dev | prod)
│       ├── ec2/               # SSM bastion (jump host for the private prod DB)
│       └── monitoring/        # SNS topic + CloudWatch alarms
├── ansible/
│   ├── configure.yml          # playbook: configure + seed a DB tier
│   ├── ansible.cfg / requirements.yml
│   ├── inventory/hosts.yml    # dev + prod logical targets (connection: local)
│   ├── group_vars/            # all.yml + per-tier dev.yml / prod.yml
│   └── roles/mysql_appdb/     # schema, app user, seed data (community.mysql)
├── scripts/
│   ├── prod_tunnel.sh         # open the SSM port-forward to the prod DB
│   └── teardown.sh            # complete per-tier cleanup flow
├── docs/iam/                  # deploy-role SSM policy
├── .github/workflows/
│   ├── ci.yml                 # terraform fmt/validate/tflint + ansible lint
│   ├── deploy.yml             # preflight → plan → apply (infra only, OIDC)
│   ├── configure.yml          # manual Ansible run (dev direct / prod via SSM)
│   └── destroy.yml            # gated teardown (workflow_dispatch)
└── Makefile                   # local convenience targets
```

## Prerequisites

You provide these once, out of band:

- Terraform >= 1.5, Ansible (`ansible-core`), and the `PyMySQL` driver
- The AWS CLI + `session-manager-plugin` (to reach the prod DB)
- An **S3 bucket + DynamoDB table** for remote state/locking
- A **GitHub OIDC provider + IAM role** that trusts this repo (manages
  VPC/EC2/RDS/IAM/CloudWatch/SNS + S3/DynamoDB state)
- The repository secrets/variables below
- Your IP/CIDR to allow into the dev DB (`dev_db_allowed_cidrs`)

No EC2 key pair, no SSH — the bastion is SSM-only and the databases are managed.

### Required configuration

```bash
gh secret set AWS_ROLE_ARN        --body 'arn:aws:iam::<acct>:role/<deploy-role>'
gh secret set TF_BACKEND_BUCKET   --body '<your-tfstate-bucket>'
gh secret set TF_BACKEND_TABLE    --body '<your-lock-table>'
gh secret set RDS_ADMIN_PASSWORD  --body '<strong-password>'   # master pw (both DBs)
gh secret set APP_DB_PASSWORD     --body '<strong-password>'   # app user pw (optional)
gh variable set AWS_REGION        --body 'us-east-1'           # optional (defaults to us-east-1)
```

The `preflight` job fails fast and lists any missing secrets.

### Deploy-role permissions

Whoever needs to reach the **prod DB over the SSM bastion** (you, from a laptop,
or a CI role) needs the SSM policy:

```bash
aws iam put-role-policy --role-name <your-role> \
  --policy-name db-provision-ssm \
  --policy-document file://docs/iam/deploy-role-ssm-policy.json
```

## Usage

### 1. Deploy the infrastructure

```bash
export TF_VAR_rds_admin_password='...'
cp terraform/backend.hcl.example terraform/backend.hcl   # edit bucket/table
make init
make plan  ENV=dev
make apply ENV=dev
```

…or push to `main` / run the **Deploy** workflow. This provisions both RDS
instances and the bastion — it does **not** configure or seed the databases.

### 2. Configure + seed the dev DB (public)

Your IP must be in `dev_db_allowed_cidrs`. Then:

```bash
make ansible-deps                 # community.mysql collection + PyMySQL (once)
export RDS_ADMIN_PASSWORD='...'    # master password
export APP_DB_PASSWORD='...'       # optional; password for the app user
make configure-dev                 # schema + app user + seed data
```

`make configure-dev` pulls the dev endpoint from the Terraform output and runs
`ansible-playbook configure.yml --limit dev`.

### 3. Configure + seed the prod DB (private, via SSM)

The prod DB has no public endpoint. Open the SSM port-forward in one terminal:

```bash
make prod-tunnel                   # localhost:3308 -> prod DB:3306 (leave running)
```

Then, in another terminal:

```bash
export RDS_ADMIN_PASSWORD='...'
export APP_DB_PASSWORD='...'
make configure-prod                # Ansible connects to 127.0.0.1:3308
```

Or run the **Configure** workflow (**Actions → Configure → Run workflow**) and
pick `prod` — it opens the SSM tunnel on the runner and runs Ansible for you.
(The `dev` option only works from CI if the runner's egress IP is in
`dev_db_allowed_cidrs`; dev is normally configured locally.)

## Connecting to the databases

```bash
# dev DB — public, connect directly (your IP must be allowed):
mysql -h "$(cd terraform && terraform output -raw dev_db_address)" -u admin -p appdb

# prod DB — private, reach it via the SSM tunnel:
./scripts/prod_tunnel.sh           # leave running, then in another shell:
mysql -h 127.0.0.1 -P 3308 -u admin -p appdb
```

Requires the AWS CLI + `session-manager-plugin` and `ssm:StartSession` rights.

## Design notes

- **Dev open, prod locked.** The dev DB is developer-reachable (SG-locked); the
  prod DB has no public endpoint and is reachable only through the SSM bastion.
- **Managed databases.** Both sides are RDS — no self-managed MySQL, no host to
  patch, no SSH keys anywhere.
- **Terraform provisions, Ansible configures.** Terraform owns infrastructure;
  the schema, application user, and seed data are Ansible's job — one idempotent
  role (`mysql_appdb`) drives both tiers, varying only the connection.
- **Same role, two paths.** The Ansible role is tier-agnostic; `group_vars/`
  point dev at the public endpoint and prod at the local end of the SSM tunnel.
- **No secrets in code.** Passwords flow through `TF_VAR_*` / `RDS_ADMIN_PASSWORD`
  / `APP_DB_PASSWORD` env vars / CI secrets; `.gitignore` blocks state, tfvars,
  vault passwords, and keys.

## Troubleshooting

| Symptom | Cause & fix |
| --- | --- |
| `preflight` fails listing missing secrets | Set them (see Required configuration). |
| Can't reach the dev DB | Your IP isn't in `dev_db_allowed_cidrs`. Add it and re-apply. |
| Ansible: `Can't connect to MySQL server` (prod) | The SSM tunnel isn't open. Run `make prod-tunnel` first (and check `PROD_TUNNEL_PORT`). |
| Ansible: `Access denied for user` | `RDS_ADMIN_PASSWORD` doesn't match the RDS master password. |
| `No module named 'pymysql'` | `pip install PyMySQL` (or `make ansible-deps`). |
| `ssm:StartSession` denied | Attach `docs/iam/deploy-role-ssm-policy.json` to your role. |

## Cleanup

A plain `terraform destroy` can fail when prod RDS has deletion protection on.
Use the complete flow, which clears protection first:

```bash
export AWS_REGION=us-east-1
export TF_BACKEND_BUCKET=... TF_BACKEND_TABLE=...
export TF_VAR_rds_admin_password=...
make teardown ENV=dev
```

…or run the **Destroy** workflow (type `destroy` to confirm; Environment-gated).

> Not removed (you created them): the state bucket, lock table, and OIDC
> provider + deploy role. Empty the versioned state bucket before deleting it.
