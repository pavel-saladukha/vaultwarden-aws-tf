#!/bin/bash
# Stop Vaultwarden, save its data, then start it again on success or failure.
set -euo pipefail
umask 077

# Terraform supplies the bucket name. VW_HOME is optional for local tests.
home_dir="$${VW_HOME:-/home/ec2-user}"
backup_bucket="s3://${s3_bucket_name}"
work_dir=""

finish_backup() {
    local exit_status=$1
    trap - EXIT

    # A failed stop, database check, or upload must not prevent this attempt.
    if ! docker-compose up -d vaultwarden; then
        echo "Cannot start Vaultwarden after backup." >&2
        exit_status=1
    fi

    if (( exit_status == 0 )); then
        rm -rf -- "$work_dir"
    else
        echo "Backup failed. Local files: $work_dir" >&2
    fi
    exit "$exit_status"
}

create_database_snapshot() {
    local snapshot="$work_dir/vw-data/backup.sqlite3"

    mkdir "$work_dir/vw-data"
    sqlite3 "$home_dir/vw-data/db.sqlite3" ".backup '$snapshot'"
    if [[ $(sqlite3 "$snapshot" 'PRAGMA integrity_check;') != ok ]]; then
        echo "Database snapshot failed its integrity check: $snapshot" >&2
        exit 1
    fi
}

create_archive() {
    # Keep attachments, keys, and configuration. Add the checked snapshot
    # instead of the live database, its journal files, and the application log.
    tar -cf "$work_dir/backup.tar" \
        --exclude='vw-data/db.sqlite3' \
        --exclude='vw-data/db.sqlite3-wal' \
        --exclude='vw-data/db.sqlite3-shm' \
        --exclude='vw-data/backup.sqlite3' \
        --exclude='vw-data/vaultwarden.log' \
        -C "$home_dir" vw-data
    tar -rf "$work_dir/backup.tar" -C "$work_dir" vw-data/backup.sqlite3
    gzip "$work_dir/backup.tar"
}

upload_archive() {
    local dated_key
    dated_key=$(date -u +%Y/%m/%d/%Y%m%dT%H%M%S)-$(basename "$work_dir").tar.gz

    # Keep a dated recovery copy before replacing the latest backup.
    # If either upload fails, the EXIT handler keeps the local archive.
    aws s3 cp "$work_dir/backup.tar.gz" "$backup_bucket/$dated_key" --sse AES256
    aws s3 cp "$work_dir/backup.tar.gz" "$backup_bucket/backup-latest.tar.gz" --sse AES256
}

main() {
    cd "$home_dir"

    # File descriptor 9 holds the same lock that restore.sh uses.
    exec 9>"$home_dir/.vaultwarden-data.lock"
    if ! flock -n 9; then
        echo "A database operation is active." >&2
        exit 1
    fi
    if [[ ! -f vw-data/db.sqlite3 ]]; then
        echo "Database is missing: $home_dir/vw-data/db.sqlite3" >&2
        exit 1
    fi

    work_dir=$(mktemp -d "$home_dir/backup.XXXXXXXX")
    trap 'finish_backup "$?"' EXIT

    docker-compose stop vaultwarden
    create_database_snapshot
    create_archive
    upload_archive
}

main "$@"
