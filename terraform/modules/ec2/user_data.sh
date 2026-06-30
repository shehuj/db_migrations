#!/usr/bin/env bash
# Minimal bootstrap only. Database installation/configuration is owned by Ansible.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# Python is required for Ansible modules; ensure it is present.
apt-get install -y python3 python3-apt

# SSM agent ships preinstalled on Ubuntu 22.04 via snap; make sure it is running
# so the host can be managed without an open SSH port if desired.
snap start amazon-ssm-agent || systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
