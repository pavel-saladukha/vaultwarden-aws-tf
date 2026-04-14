#!/bin/bash
set -euo pipefail

home_dir="/home/ec2-user"
scripts_path="$home_dir/scripts"

# Apply OS updates first.
bash "$scripts_path/update.sh"

# backup.sh already handles compose down/up.
bash "$scripts_path/backup.sh"

# Truncate logs in place to preserve ownership and file handles.
: > "$home_dir/nginx/access.log"
: > "$home_dir/nginx/error.log"
: > "$home_dir/vw-data/vaultwarden.log"

chown -R ec2-user:ec2-user "$home_dir"

shutdown -r now
