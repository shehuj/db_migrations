#!/usr/bin/env bash
###############################################################################
# install_mysql.sh
#
# Standalone fallback installer for the source MySQL host (Ubuntu 22.04). The
# canonical configuration path is the Ansible role under ansible/; this script
# exists for manual bootstrapping / debugging when Ansible is unavailable.
#
# Usage (on the host, as root):
#   DB_NAME=appdb \
#   DMS_USER=dms_user DMS_PASSWORD=... \
#   APP_USER=admin APP_PASSWORD=... \
#   ./install_mysql.sh
###############################################################################
set -euo pipefail

DB_NAME="${DB_NAME:-appdb}"
DMS_USER="${DMS_USER:-dms_user}"
DMS_PASSWORD="${DMS_PASSWORD:?DMS_PASSWORD is required}"
APP_USER="${APP_USER:-admin}"
APP_PASSWORD="${APP_PASSWORD:?APP_PASSWORD is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mysql-server

# --- Enable binlog (ROW) so DMS can perform CDC ------------------------------
cat >/etc/mysql/mysql.conf.d/dms.cnf <<'EOF'
[mysqld]
bind-address           = 0.0.0.0
server_id              = 1
log_bin                = /var/log/mysql/mysql-bin.log
binlog_format          = ROW
binlog_row_image       = FULL
expire_logs_days       = 1
EOF

systemctl restart mysql
systemctl enable mysql

# --- Provision schema + users ------------------------------------------------
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;

CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${APP_USER}'@'%';

CREATE USER IF NOT EXISTS '${DMS_USER}'@'%' IDENTIFIED BY '${DMS_PASSWORD}';
GRANT SELECT, RELOAD, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '${DMS_USER}'@'%';
GRANT SELECT ON \`${DB_NAME}\`.* TO '${DMS_USER}'@'%';

FLUSH PRIVILEGES;
SQL

# --- Seed sample data --------------------------------------------------------
if [[ -f "$(dirname "$0")/populate_db.sql" ]]; then
  mysql "${DB_NAME}" <"$(dirname "$0")/populate_db.sql"
fi

echo "MySQL source host configured for DMS (database=${DB_NAME})."
