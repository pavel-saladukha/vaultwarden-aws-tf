#!/bin/bash
set -euo pipefail
# The repository release is fixed in /etc/dnf/vars/releasever during startup.
dnf upgrade -y
