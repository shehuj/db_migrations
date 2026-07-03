#!/usr/bin/env bash
###############################################################################
# prod_tunnel.sh — open an SSM port-forward to the private prod DB.
#
# The prod database has no public endpoint; the only path in is an SSM session
# through the bastion. This maps a local port (default 3308) to the prod RDS
# host:3306 so a MySQL client — or Ansible (--limit prod) — can reach it on
# localhost. Leave it running in one terminal; run Ansible/mysql in another.
#
# Usage:
#   ./scripts/prod_tunnel.sh              # local port 3308
#   PROD_TUNNEL_PORT=3399 ./scripts/prod_tunnel.sh
#
# Requires: awscli, the session-manager-plugin, and ssm:StartSession rights.
###############################################################################
set -euo pipefail

LOCAL_PORT="${PROD_TUNNEL_PORT:-3308}"
DB_PORT="${DB_PORT:-3306}"
TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

BASTION="$(terraform -chdir="$TF_DIR" output -raw bastion_instance_id)"
PROD_HOST="$(terraform -chdir="$TF_DIR" output -raw prod_db_address)"

echo "==> Forwarding localhost:${LOCAL_PORT} -> ${PROD_HOST}:${DB_PORT} via ${BASTION}"
echo "    Leave this running; in another shell connect to 127.0.0.1:${LOCAL_PORT}."

exec aws ssm start-session --target "$BASTION" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${PROD_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
