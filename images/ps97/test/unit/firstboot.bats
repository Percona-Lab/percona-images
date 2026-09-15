#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../../ansible/roles/ps97-firstboot/files/ps97-firstboot.sh"

setup() {
    export PS97_FIRSTBOOT_ROOT="$BATS_TEST_TMPDIR/root"
    export PS97_FIRSTBOOT_DATADIR="$PS97_FIRSTBOOT_ROOT/data/mysql"
    export PS97_FIRSTBOOT_MARKER="$PS97_FIRSTBOOT_ROOT/data/.ps97-firstboot-done"
    export PS97_FIRSTBOOT_RUNDIR="$PS97_FIRSTBOOT_ROOT/run/ps97-firstboot"
    export PS97_FIRSTBOOT_CONSOLE="$BATS_TEST_TMPDIR/console"
    export PS97_FIRSTBOOT_MYSQLD="${BATS_TEST_DIRNAME}/stub-mysqld"
    export PS97_FIRSTBOOT_GROWFS=0
    export PS97_FIRSTBOOT_SKIP_CHOWN=1
    export STUB_MYSQLD_LOG="$BATS_TEST_TMPDIR/mysqld.log"
    export STUB_MYSQLD_INIT_COPY="$BATS_TEST_TMPDIR/init.sql"

    mkdir -p "$PS97_FIRSTBOOT_ROOT/data"
    : > "$STUB_MYSQLD_LOG"

    MOTD="$PS97_FIRSTBOOT_ROOT/etc/motd.d/30-ps97"
}

password_from_motd() {
    grep -oE '[A-Za-z0-9]{32}' "$MOTD" | head -1
}

@test 'generates a 32 character alphanumeric password' {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    password=$(password_from_motd)
    [ "${#password}" -eq 32 ]
    [[ "$password" =~ ^[A-Za-z0-9]+$ ]]
}

@test 'generates a different password on a clean run' {
    run "$SCRIPT"
    first=$(password_from_motd)
    rm -rf "$PS97_FIRSTBOOT_ROOT"
    mkdir -p "$PS97_FIRSTBOOT_ROOT/data"
    run "$SCRIPT"
    second=$(password_from_motd)
    [ "$first" != "$second" ]
}

@test 'initializes the datadir exactly once' {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '--initialize-insecure' "$STUB_MYSQLD_LOG")" -eq 1 ]
}

@test 'applies the password through an init file' {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    password=$(password_from_motd)
    grep -q "ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}';" "$STUB_MYSQLD_INIT_COPY"
    [ "$(grep -c 'ALTER USER' "$STUB_MYSQLD_INIT_COPY")" -eq 1 ]
}

@test 'starts the temporary instance without networking' {
    run "$SCRIPT"
    grep -- '--skip-networking' "$STUB_MYSQLD_LOG"
}

@test 'removes the init file after use' {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -f "$PS97_FIRSTBOOT_RUNDIR/init.sql" ]
}

@test 'creates the marker beside the datadir, never inside it' {
    run "$SCRIPT"
    [ -f "$PS97_FIRSTBOOT_MARKER" ]
    [ ! -e "$PS97_FIRSTBOOT_DATADIR/.ps97-firstboot-done" ]
}

@test 'is a no-op when the marker exists' {
    touch "$PS97_FIRSTBOOT_MARKER"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -s "$STUB_MYSQLD_LOG" ]
    [ ! -f "$MOTD" ]
}

@test 'is a no-op when the datadir is already populated' {
    mkdir -p "$PS97_FIRSTBOOT_DATADIR/mysql"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -s "$STUB_MYSQLD_LOG" ]
}

@test 'writes the banner to the console' {
    run "$SCRIPT"
    password=$(password_from_motd)
    grep -q "$password" "$PS97_FIRSTBOOT_CONSOLE"
    grep -q 'Percona Server for MySQL' "$PS97_FIRSTBOOT_CONSOLE"
}

@test 'the banner explains how to connect' {
    run "$SCRIPT"
    grep -q 'mysql -u root -p' "$MOTD"
}

@test 'the motd file is world readable' {
    run "$SCRIPT"
    [ "$(stat -c '%a' "$MOTD")" = "644" ]
}
