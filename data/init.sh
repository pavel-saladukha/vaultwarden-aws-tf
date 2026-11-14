#!/bin/bash
# EC2 startup: install the host, restore data, then start the application.
set -euo pipefail

# Terraform fills these values from the inputs and local.software.
export AWS_DEFAULT_REGION="${aws_region}"
export AWS_PAGER=""
REPOSITORY_RELEASE="${repository_release}"
AWSCLI_VERSION="${awscli_version}"
SQLITE_VERSION="${sqlite_version}"
DOCKER_RPM="${docker_rpm}"
CONTAINERD_RPM="${containerd_rpm}"
PYTHON_RPM="${python_rpm}"
PYTHON_PIP_RPM="${python_pip_rpm}"
PYTHON_SETUPTOOLS_RPM="${python_setuptools_rpm}"
COMPOSE_VERSION="${docker_compose_version}"
COMPOSE_CHECKSUM="${docker_compose_checksum}"
BUILDX_VERSION="${docker_buildx_version}"
BUILDX_CHECKSUM="${docker_buildx_checksum}"
FAIL2BAN_COMMIT="${fail2ban_commit}"
CERTBOT_VERSION="${certbot_version}"
CERTBOT_ROUTE53_VERSION="${certbot_route53_version}"
CERTBOT_TEST_OPTION="${enable_test_cert}"
DOMAIN="${full_domain_name}"
CERTIFICATE_EMAIL="${email_for_cert}"
HOSTED_ZONE_ID="${hosted_zone_id}"
CONFIG_BUCKET="s3://${s3_configs}"
BACKUP_BUCKET="${s3_backups}"

APP_HOME=/home/ec2-user
SCRIPTS_DIR="$APP_HOME/scripts"
COMPOSE_FILE="$APP_HOME/docker-compose.yml"
DOCKER_PLUGINS_DIR=/usr/local/lib/docker/cli-plugins

download_config() {
    local source_name=$1
    local destination=$2
    aws s3 cp "$CONFIG_BUCKET/$source_name" "$destination" --sse
}

install_host_packages() {
    echo "Install host packages from repository $REPOSITORY_RELEASE."
    # Later scheduled updates must use the same repository snapshot.
    printf '%s\n' "$REPOSITORY_RELEASE" > /etc/dnf/vars/releasever
    dnf upgrade -y --releasever="$REPOSITORY_RELEASE"
    dnf install -y --releasever="$REPOSITORY_RELEASE" \
        "awscli-2-$AWSCLI_VERSION" "sqlite-$SQLITE_VERSION" \
        jq git cronie tar gzip util-linux iproute ca-certificates
    systemctl enable --now crond
}

register_dns() (
    # A subshell keeps the temporary-file cleanup local to this operation.
    local metadata_url=http://169.254.169.254/latest
    local token ipv4 batch_file change_id

    echo "Register the public address for $DOMAIN."
    token=$(curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 --retry 3 \
        -X PUT "$metadata_url/api/token" \
        -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
    ipv4=$(curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 --retry 3 \
        -H "X-aws-ec2-metadata-token: $token" "$metadata_url/meta-data/public-ipv4")

    batch_file=$(mktemp)
    trap 'rm -f -- "$batch_file"' EXIT
    jq -n --arg name "$DOMAIN" --arg address "$ipv4" '{
        Changes: [{
            Action: "UPSERT",
            ResourceRecordSet: {
                Name: $name,
                Type: "A",
                TTL: 60,
                ResourceRecords: [{Value: $address}]
            }
        }]
    }' > "$batch_file"
    change_id=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "file://$batch_file" \
        --query ChangeInfo.Id --output text)
    aws route53 wait resource-record-sets-changed --id "$change_id"
)

install_verified_binary() (
    local url=$1
    local expected_checksum=$2
    local destination=$3
    local download

    download=$(mktemp)
    trap 'rm -f -- "$download"' EXIT
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$download"
    if ! printf '%s  %s\n' "$expected_checksum" "$download" | sha256sum --check --status; then
        echo "Download checksum does not match: $url" >&2
        exit 1
    fi
    install -m 0755 "$download" "$destination"
)

install_docker_tools() {
    local compose_url="https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64"
    local buildx_url="https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-$BUILDX_VERSION.linux-amd64"

    echo "Install Docker, Python, Compose, and Buildx."
    dnf install -y "docker-$DOCKER_RPM" "containerd-$CONTAINERD_RPM" \
        "python3.14-$PYTHON_RPM" "python3.14-pip-$PYTHON_PIP_RPM" \
        "python3.14-setuptools-$PYTHON_SETUPTOOLS_RPM" iptables
    usermod -aG docker ec2-user
    systemctl enable --now docker.service

    mkdir -p "$DOCKER_PLUGINS_DIR"
    install_verified_binary "$compose_url" "$COMPOSE_CHECKSUM" /usr/local/bin/docker-compose
    ln -sfn /usr/local/bin/docker-compose /usr/bin/docker-compose
    ln -sfn /usr/local/bin/docker-compose "$DOCKER_PLUGINS_DIR/docker-compose"
    install_verified_binary "$buildx_url" "$BUILDX_CHECKSUM" "$DOCKER_PLUGINS_DIR/docker-buildx"
}

install_fail2ban() (
    local source_dir

    echo "Install Fail2ban from commit $FAIL2BAN_COMMIT."
    source_dir=$(mktemp -d)
    trap 'rm -rf -- "$source_dir"' EXIT
    git -C "$source_dir" init
    git -C "$source_dir" remote add origin https://github.com/fail2ban/fail2ban.git
    git -C "$source_dir" fetch --depth 1 origin "$FAIL2BAN_COMMIT"
    git -C "$source_dir" checkout --detach "$FAIL2BAN_COMMIT"

    # Use the same interpreter for the installed scripts and their modules.
    python3.14 -m venv --system-site-packages /opt/fail2ban
    cd "$source_dir"
    /opt/fail2ban/bin/python setup.py build
    /opt/fail2ban/bin/python setup.py install --prefix=/opt/fail2ban
    cat > /etc/systemd/system/fail2ban.service <<'UNIT'
[Unit]
Description=Fail2ban
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
Environment=PYTHONNOUSERSITE=1
RuntimeDirectory=fail2ban
ExecStart=/opt/fail2ban/bin/python /opt/fail2ban/bin/fail2ban-server -xf start
ExecReload=/opt/fail2ban/bin/python /opt/fail2ban/bin/fail2ban-client reload
ExecStop=/opt/fail2ban/bin/python /opt/fail2ban/bin/fail2ban-client stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    # Start only after the filters, jails, and application logs are ready.
    systemctl enable fail2ban
)

install_fail2ban_config() {
    # Each source file maps to a jail or filter on the host.
    download_config vaultwarden-jail.conf /etc/fail2ban/jail.d/vaultwarden.conf
    download_config vaultwarden-filter.conf /etc/fail2ban/filter.d/vaultwarden.conf
    download_config vaultwarden-admin-jail.conf /etc/fail2ban/jail.d/vaultwarden-admin.conf
    download_config vaultwarden-admin-filter.conf /etc/fail2ban/filter.d/vaultwarden-admin.conf
    download_config nginx-botsearch-jail.conf /etc/fail2ban/jail.d/nginx-botsearch.conf
    download_config nginx-http-auth-jail.conf /etc/fail2ban/jail.d/nginx-http-auth.conf
    download_config nginx-301-jail.conf /etc/fail2ban/jail.d/nginx-301.conf
    download_config nginx-301-filter.conf /etc/fail2ban/filter.d/nginx-301.conf
    download_config nginx-400-jail.conf /etc/fail2ban/jail.d/nginx-400.conf
    download_config nginx-400-filter.conf /etc/fail2ban/filter.d/nginx-400.conf
    download_config nginx-404-jail.conf /etc/fail2ban/jail.d/nginx-404.conf
    download_config nginx-404-filter.conf /etc/fail2ban/filter.d/nginx-404.conf
}

install_certificate() {
    local test_options=()
    if [[ -n "$CERTBOT_TEST_OPTION" ]]; then
        test_options+=("$CERTBOT_TEST_OPTION")
    fi

    echo "Install Certbot and request the certificate for $DOMAIN."
    python3.14 -m venv /opt/certbot
    /opt/certbot/bin/python -m pip install \
        "certbot==$CERTBOT_VERSION" "certbot-dns-route53==$CERTBOT_ROUTE53_VERSION"
    /opt/certbot/bin/certbot certonly \
        --dns-route53 --domain "$DOMAIN" -m "$CERTIFICATE_EMAIL" \
        --key-type ecdsa --agree-tos --non-interactive --quiet "$${test_options[@]}"
}

install_scripts() {
    local script
    mkdir -p "$SCRIPTS_DIR"
    for script in backup.sh restore.sh update.sh maintenance.sh AWS_SpotTerminationNotifier.sh; do
        download_config "$script" "$SCRIPTS_DIR/$script"
        chmod 0755 "$SCRIPTS_DIR/$script"
    done
}

write_cron_file() {
    local name=$1
    local job=$2

    # Replace the file so a repeated setup cannot add duplicate jobs.
    printf 'SHELL=/bin/bash\nPATH=/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n%s\n' \
        "$job" > "/etc/cron.d/$name"
    chmod 0644 "/etc/cron.d/$name"
}

configure_scheduled_jobs() {
    local reload_nginx="/usr/bin/docker-compose -f $COMPOSE_FILE exec -T nginx nginx -s reload"

    write_cron_file backup-vaultwarden \
        "0 1 * * * root bash $SCRIPTS_DIR/backup.sh >> /var/log/vaultwarden-backup.log 2>&1"
    write_cron_file update-packages \
        "0 2 */7 * * root bash $SCRIPTS_DIR/update.sh > /dev/null 2>&1"
    write_cron_file maintenance \
        "0 3 * * 0 root bash $SCRIPTS_DIR/maintenance.sh >> /var/log/vaultwarden-maintenance.log 2>&1"
    write_cron_file renew-certs \
        "0 4 * * * root /opt/certbot/bin/certbot renew --deploy-hook '$reload_nginx' >> /var/log/vaultwarden-certbot.log 2>&1"
}

configure_spot_handler() {
    cat > /etc/systemd/system/vaultwarden-spot.service <<'UNIT'
[Unit]
Description=Vaultwarden Spot termination handler
Wants=network-online.target
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/home/ec2-user/scripts/AWS_SpotTerminationNotifier.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable vaultwarden-spot.service
}

install_application_config() {
    mkdir -p "$APP_HOME/nginx"
    touch "$APP_HOME/nginx/access.log" "$APP_HOME/nginx/error.log"
    download_config nginx.conf "$APP_HOME/nginx/nginx.conf"
    download_config Dockerfile "$APP_HOME/nginx/Dockerfile"
    download_config docker-compose.yml "$COMPOSE_FILE"
}

restore_latest_backup() {
    local backup_count
    local archive="$APP_HOME/latest.tar.gz"

    echo "Check the latest backup in $BACKUP_BUCKET."
    # An AWS error must stop startup. Only a confirmed missing key permits
    # a new database. An empty bucket has no Contents field in its response.
    backup_count=$(aws s3api list-objects-v2 --bucket "$BACKUP_BUCKET" \
        --prefix backup-latest.tar.gz --output json | \
        jq '[.Contents[]? | select(.Key == "backup-latest.tar.gz")] | length')
    if (( backup_count == 0 )); then
        mkdir -p "$APP_HOME/vw-data"
    else
        aws s3 cp "s3://$BACKUP_BUCKET/backup-latest.tar.gz" "$archive" --sse
        bash "$SCRIPTS_DIR/restore.sh" "$archive"
        rm -- "$archive"
    fi
}

start_services() {
    echo "Start Vaultwarden, Nginx, Fail2ban, and the Spot handler."
    touch "$APP_HOME/vw-data/vaultwarden.log"
    chown -R ec2-user:ec2-user "$APP_HOME"
    docker-compose -f "$COMPOSE_FILE" build nginx
    docker-compose -f "$COMPOSE_FILE" up -d
    systemctl restart fail2ban
    systemctl start vaultwarden-spot.service
}

main() {
    install_host_packages
    register_dns
    install_docker_tools
    install_fail2ban
    install_fail2ban_config
    install_certificate
    install_scripts
    configure_scheduled_jobs
    configure_spot_handler
    install_application_config

    # Restore before the first start: Vaultwarden runs migrations at startup.
    restore_latest_backup
    start_services

    hostnamectl set-hostname warden
    # Reboot into the selected kernel after setup.
    sleep 15
    shutdown -r now
}

# Tests can source the rendered file and call one operation with mocked tools.
if [[ "$${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
