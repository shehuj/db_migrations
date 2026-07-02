#!/usr/bin/env bash
###############################################################################
# setup_source_db.sh
#
# Prepares the dev/source RDS so it can act as a DMS source, and seeds it:
#   1. enable binary-log retention (RDS-specific procedure) for CDC
#   2. create the DMS replication user with least-privilege grants
#   3. load the sample schema + data
#
# Run locally against the PUBLIC dev DB (your IP must be in dev_db_allowed_cidrs):
#   export DEV_DB_HOST="$(terraform -chdir=terraform output -raw dev_db_address)"
#   export RDS_ADMIN_PASSWORD='...'   # RDS master password
#   export DMS_DB_PASSWORD='...'      # password to set for the DMS user
#   ./scripts/setup_source_db.sh
#
# Requires the mysql client. Idempotent.
###############################################################################
set -euo pipefail

: "${DEV_DB_HOST:?set DEV_DB_HOST (terraform output dev_db_address)}"
: "${RDS_ADMIN_PASSWORD:?set RDS_ADMIN_PASSWORD}"
: "${DMS_DB_PASSWORD:?set DMS_DB_PASSWORD}"

DB_NAME="${DB_NAME:-appdb}"
DMS_USER="${DMS_USER:-dms_user}"
ADMIN_USER="${ADMIN_USER:-admin}"
DIR="$(cd "$(dirname "$0")" && pwd)"

# MYSQL_PWD keeps the password out of the process list / shell history.
export MYSQL_PWD="$RDS_ADMIN_PASSWORD"

echo "==> Configuring binlog retention + DMS user on ${DEV_DB_HOST}"
mysql -h "$DEV_DB_HOST" -u "$ADMIN_USER" <<SQL
CALL mysql.rds_set_configuration('binlog retention hours', 24);

CREATE USER IF NOT EXISTS '${DMS_USER}'@'%' IDENTIFIED BY '${DMS_DB_PASSWORD}';
ALTER USER '${DMS_USER}'@'%' IDENTIFIED BY '${DMS_DB_PASSWORD}';
GRANT SELECT, RELOAD, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '${DMS_USER}'@'%';
GRANT SELECT ON \`${DB_NAME}\`.* TO '${DMS_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "==> Loading seed data into ${DB_NAME}"
mysql -h "$DEV_DB_HOST" -u "$ADMIN_USER" "$DB_NAME" < "$DIR/populate_db.sql"

echo "Done. Dev/source DB is ready for DMS (source endpoint user: ${DMS_USER})."
