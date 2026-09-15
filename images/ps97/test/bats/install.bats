#!/usr/bin/env bats

VERSION="${PS97_VERSION:-9.7.1}"
CHANNEL="${PS97_REPO_CHANNEL:-release}"

@test 'the build passed its version and channel through' {
    # These default when unset, so without this test a broken environment
    # handoff from the Packer provisioner would be invisible: the version
    # assertion below would compare the default against itself.
    [ -n "${PS97_VERSION:-}" ]
    [ -n "${PS97_REPO_CHANNEL:-}" ]
}

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

@test 'every package came from the Percona component at the requested channel' {
    # The vendor field cannot carry this: percona-xtrabackup-97 publishes an
    # empty vendor in every channel, so a vendor match fails on a correct image.
    # The repository a package was installed from answers the real question and
    # carries the channel too.
    run dnf repoquery --installed --qf '%{name}|%{from_repo}' \
        percona-server-server percona-server-client percona-xtrabackup-97
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
    [ "$(printf '%s\n' "$output" | grep -cE "\|(ps-97-lts|pxb-97-lts)-${CHANNEL}-")" -eq 3 ]
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
