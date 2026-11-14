#!/bin/bash
# Check Spot termination notices with IMDSv2.
set -euo pipefail
metadata_url=http://169.254.169.254/latest
while true; do
    token=$(curl --noproxy '*' -fsS --connect-timeout 3 --max-time 5 \
        -X PUT "$metadata_url/api/token" -H 'X-aws-ec2-metadata-token-ttl-seconds: 60') || { sleep 5; continue; }
    status=$(curl --noproxy '*' -sS --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' \
        -H "X-aws-ec2-metadata-token: $token" "$metadata_url/meta-data/spot/instance-action") || { sleep 5; continue; }
    # Only a successful notice can trigger shutdown. Ignore authentication and network errors.
    if [[ "$status" == 200 ]]; then
        docker-compose -f /home/ec2-user/docker-compose.yml stop
        /home/ec2-user/scripts/backup.sh
        break
    fi
    sleep 5
done
