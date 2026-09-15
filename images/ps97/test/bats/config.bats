#!/usr/bin/env bats

BASELINE=/etc/my.cnf.d/99-percona-ami.cnf

@test 'the baseline configuration file exists' {
    [ -f "$BASELINE" ]
}

@test 'the packaged my.cnf was not edited' {
    ! grep -q 'percona-ami' /etc/my.cnf
    ! grep -qE '^\s*datadir\s*=\s*/data' /etc/my.cnf
}

@test 'datadir points at the data volume' {
    grep -qE '^\s*datadir\s*=\s*/data/mysql\s*$' "$BASELINE"
}

@test 'bind-address is loopback only' {
    grep -qE '^\s*bind-address\s*=\s*127\.0\.0\.1\s*$' "$BASELINE"
}

@test 'name resolution is skipped' {
    grep -qE '^\s*skip-name-resolve\s*=\s*ON\s*$' "$BASELINE"
}

@test 'innodb_dedicated_server is on' {
    grep -qE '^\s*innodb_dedicated_server\s*=\s*ON\s*$' "$BASELINE"
}

@test 'the first-boot script is installed and not world readable' {
    [ -x /usr/local/sbin/ps97-firstboot ]
    [ "$(stat -c '%a' /usr/local/sbin/ps97-firstboot)" = "750" ]
}

@test 'the first-boot marker is absent' {
    [ ! -e /data/.ps97-firstboot-done ]
}

@test 'the sysctl values are installed' {
    grep -qE '^vm\.swappiness\s*=\s*1$' /etc/sysctl.d/99-ps97.conf
    grep -qE '^net\.core\.somaxconn\s*=\s*1024$' /etc/sysctl.d/99-ps97.conf
}

@test 'the mysqld file descriptor limit is raised' {
    grep -qE '^LimitNOFILE=65535$' /etc/systemd/system/mysqld.service.d/10-limits.conf
}
