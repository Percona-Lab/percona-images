#!/usr/bin/env bats

VERSION="${PS97_VERSION:-9.7.1}"
CHANNEL="${PS97_REPO_CHANNEL:-release}"

@test 'the server package is installed' {
    rpm -q percona-server-server
}

@test 'the client package is installed' {
    rpm -q percona-server-client
}

@test 'xtrabackup is installed' {
    rpm -q percona-xtrabackup-97
}

@test 'the installed server version matches the requested version' {
    [ "$(rpm -q --queryformat '%{VERSION}' percona-server-server)" = "$VERSION" ]
}

@test 'every Percona package was provided by Percona' {
    for pkg in percona-server-server percona-server-client percona-xtrabackup-97; do
        rpm -q --queryformat '%{VENDOR}' "$pkg" | grep -qi percona
    done
}

@test 'no release candidate ships on the release channel' {
    [ "$CHANNEL" = "release" ] || skip 'only enforced on the release channel'
    ! rpm -qa --queryformat '%{NAME} %{RELEASE}\n' 'percona-*' | grep -q 'rc[0-9]'
}

@test 'the mysql user and group exist' {
    getent passwd mysql
    getent group mysql
}

@test 'mysqld.service is enabled' {
    systemctl is-enabled mysqld.service
}

@test 'the first-boot unit is enabled' {
    systemctl is-enabled ps97-firstboot.service
}

@test 'the transparent huge pages unit is enabled' {
    systemctl is-enabled ps97-thp.service
}

@test 'mysqld never ran during the bake' {
    ! systemctl is-active --quiet mysqld.service
}
