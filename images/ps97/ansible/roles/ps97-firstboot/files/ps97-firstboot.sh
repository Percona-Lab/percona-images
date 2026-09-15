#!/bin/bash
set -euo pipefail

# Every path is overridable so the suite in test/unit can exercise this against a
# temporary directory instead of a live system, with a stub standing in for mysqld.
ROOT="${PS97_FIRSTBOOT_ROOT:-}"
DATADIR="${PS97_FIRSTBOOT_DATADIR:-${ROOT}/data/mysql}"
MARKER="${PS97_FIRSTBOOT_MARKER:-${ROOT}/data/.ps97-firstboot-done}"
RUN_DIR="${PS97_FIRSTBOOT_RUNDIR:-${ROOT}/run/ps97-firstboot}"
CONSOLE="${PS97_FIRSTBOOT_CONSOLE:-/dev/console}"
MYSQLD="${PS97_FIRSTBOOT_MYSQLD:-/usr/sbin/mysqld}"
GROWFS="${PS97_FIRSTBOOT_GROWFS:-1}"

MOTD_DIR="${ROOT}/etc/motd.d"
MOTD_FILE="${MOTD_DIR}/30-ps97"
INIT_SQL="${RUN_DIR}/init.sql"
SOCKET="${RUN_DIR}/mysqld.sock"
PIDFILE="${RUN_DIR}/mysqld.pid"

PASSWORD_LENGTH=32
SHUTDOWN_TIMEOUT=120

generate_password() {
    # Alphanumeric only: the value is interpolated into a SQL string literal and
    # printed to a console banner, so it never needs quoting or escaping in either.
    #
    # Reading a fixed chunk before filtering keeps the producer from being killed
    # by SIGPIPE, which would otherwise trip pipefail. The filter discards roughly
    # three quarters of the bytes, so the loop covers a short first draw.
    local candidate=""
    while [ "${#candidate}" -lt "$PASSWORD_LENGTH" ]; do
        candidate+=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
    done
    printf '%s' "${candidate:0:$PASSWORD_LENGTH}"
}

datadir_populated() {
    # mysqld --initialize creates the system schema here. Its presence is the
    # only reliable signal that this disk already carries an initialized server,
    # and it is what protects a reattached data volume from being wiped.
    [ -d "${DATADIR}/mysql" ]
}

grow_data_filesystem() {
    [ "$GROWFS" = "1" ] || return 0
    # The filesystem comes from the AMI snapshot at its baked size. A user who
    # asks for a larger volume at launch gets the extra space only after this.
    xfs_growfs "$(dirname "$DATADIR")" >/dev/null 2>&1 || true
}

own_as_mysql() {
    [ -n "${PS97_FIRSTBOOT_SKIP_CHOWN:-}" ] && return 0
    chown mysql:mysql "$@"
}

initialize_datadir() {
    install -d -m 0750 "$DATADIR"
    own_as_mysql "$DATADIR"
    "$MYSQLD" --initialize-insecure --user=mysql --datadir="$DATADIR"
}

write_init_sql() {
    local password="$1"

    install -d -m 0700 "$RUN_DIR"
    own_as_mysql "$RUN_DIR"

    # The file below carries the password in plaintext. Removing it from a trap
    # covers the paths where the server fails to start and errexit ends the
    # script before the explicit cleanup runs. The signal handlers exit rather
    # than returning, because a handler that falls through would leave this
    # script ignoring the stop request systemd sends its unit.
    trap 'rm -f "$INIT_SQL"' EXIT
    trap 'rm -f "$INIT_SQL"; exit 143' TERM
    trap 'rm -f "$INIT_SQL"; exit 130' INT

    # RUN_DIR is on tmpfs, so the plaintext never reaches disk, and the file is
    # removed as soon as the temporary instance exits.
    (umask 077; printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" \
        "$password" > "$INIT_SQL")
    chmod 0600 "$INIT_SQL"
    own_as_mysql "$INIT_SQL"
}

apply_password() {
    # --init-file runs before the server accepts its first connection, and
    # --skip-networking keeps that first connection off the network entirely, so
    # there is no window in which root has an empty password on a live socket.
    "$MYSQLD" --user=mysql --datadir="$DATADIR" \
        --skip-networking \
        --socket="$SOCKET" \
        --pid-file="$PIDFILE" \
        --init-file="$INIT_SQL" \
        --daemonize

    local pid elapsed=0
    pid=$(cat "$PIDFILE")

    # mysqld treats SIGTERM as a clean shutdown. mysqladmin would need the
    # credential that was just set, which this script deliberately does not keep.
    kill "$pid" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        [ "$elapsed" -ge "$SHUTDOWN_TIMEOUT" ] && break
        sleep 1
        elapsed=$(( elapsed + 1 ))
    done

    rm -f "$INIT_SQL"
}

write_banner() {
    local password="$1" banner

    banner=$(cat <<BANNER

+++++++++++++++++ Percona Server for MySQL 9.7 +++++++++++++++++

  A unique password was generated for this instance:

      ${password}

  Connect with:  mysql -u root -p

  MySQL listens on localhost only. Review
  /etc/my.cnf.d/99-percona-ami.cnf before exposing it, and change
  this password once setup is complete.

+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

BANNER
)

    mkdir -p "$MOTD_DIR"
    printf '%s\n' "$banner" > "$MOTD_FILE"
    chmod 0644 "$MOTD_FILE"

    # Reaching the console puts the password in the EC2 system log, which is the
    # only way to recover it when SSH access is not yet working.
    printf '%s\n' "$banner" > "$CONSOLE" 2>/dev/null || true
}

main() {
    if [ -e "$MARKER" ] || datadir_populated; then
        return 0
    fi

    grow_data_filesystem

    local password
    password=$(generate_password)

    initialize_datadir
    write_init_sql "$password"
    apply_password
    write_banner "$password"

    touch "$MARKER"
}

main "$@"
