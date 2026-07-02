#!/usr/bin/env bash
# SSM bastion bootstrap. No database here — just the SSM agent (for access) and a
# MySQL client so an admin can reach the RDS instances from inside the VPC.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mysql-client

# SSM agent ships preinstalled on Ubuntu 22.04 via snap; ensure it is running.
snap start amazon-ssm-agent || systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
