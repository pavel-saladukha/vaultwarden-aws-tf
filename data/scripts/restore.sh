#!/bin/bash
# Usage: restore.sh ARCHIVE
# Stop Vaultwarden and move the current vw-data directory before restore.
# This script does not start the application or run database migrations.
set -euo pipefail
umask 077

home_dir="${VW_HOME:-/home/ec2-user}"
baseline_dir=""
restore_dir=""

preserve_baseline() {
    local archive=$1

    # Keep the source archive unchanged so recovery can use the old software.
    mkdir -p "$home_dir/recovery"
    baseline_dir=$(mktemp -d "$home_dir/recovery/baseline.XXXXXXXX")
    cp -- "$archive" "$baseline_dir/backup.tar.gz"
    (
        cd "$baseline_dir"
        sha256sum backup.tar.gz > backup.tar.gz.sha256
    )
    echo "Preserved baseline: $baseline_dir"
}

check_database() {
    local database=$1

    if [[ ! -f "$database" ]]; then
        echo "Database snapshot is missing: $database" >&2
        exit 1
    fi
    if [[ $(sqlite3 "$database" 'PRAGMA integrity_check;') != ok ]]; then
        echo "Database failed its integrity check: $database" >&2
        exit 1
    fi
}

restore_database() {
    local data_dir="$restore_dir/vw-data"
    local snapshot="$data_dir/backup.sqlite3"

    check_database "$snapshot"
    # Older archives can contain a live database. Use only the checked snapshot.
    rm -f -- "$data_dir/db.sqlite3" "$data_dir/db.sqlite3-wal" "$data_dir/db.sqlite3-shm"
    # The snapshot is already a complete SQLite database.
    mv -- "$snapshot" "$data_dir/db.sqlite3"
}

remove_temporary_files() {
    # Never remove the preserved baseline, even if restore fails.
    rm -rf -- "$restore_dir"
}

main() {
    if (( $# != 1 )); then
        echo "Usage: restore.sh ARCHIVE" >&2
        exit 2
    fi
    local archive=$1
    # Resolve relative paths before changing the working directory.
    if [[ "$archive" != /* ]]; then
        archive="$PWD/$archive"
    fi

    cd "$home_dir"
    exec 9>"$home_dir/.vaultwarden-data.lock"
    if ! flock -n 9; then
        echo "A database operation is active." >&2
        exit 1
    fi
    if [[ -e vw-data || -L vw-data ]]; then
        echo "Move the current vw-data before restore." >&2
        exit 1
    fi

    preserve_baseline "$archive"
    restore_dir=$(mktemp -d "$home_dir/restore.XXXXXXXX")
    trap remove_temporary_files EXIT

    # Trust archives from our backup bucket. tar reads gzip and legacy raw tar.
    tar -xf "$baseline_dir/backup.tar.gz" -C "$restore_dir"
    restore_database
    # Install data only after extraction and the database restore succeed.
    mv -- "$restore_dir/vw-data" "$home_dir/vw-data"
}

main "$@"
