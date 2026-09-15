#!/usr/bin/env bats

@test 'fstab mounts the data volume by label' {
    grep -qE '^LABEL=PS97DATA\s+/data\s+xfs' /etc/fstab
}

@test 'fstab does not mount the data volume by device path' {
    # A device path here would leave the instance in emergency mode on any
    # family that names the disk differently from the build instance.
    ! grep -E '^\s*/dev/\S+\s+/data\s' /etc/fstab
}

@test 'fstab marks the data volume nofail' {
    grep -E '^LABEL=PS97DATA\s+/data\s+xfs' /etc/fstab | grep -q nofail
}

@test 'the data volume is mounted and is xfs' {
    findmnt -n -o FSTYPE /data | grep -qx xfs
}

@test 'the datadir exists with the expected ownership and mode' {
    [ -d /data/mysql ]
    [ "$(stat -c '%U:%G' /data/mysql)" = "mysql:mysql" ]
    [ "$(stat -c '%a' /data/mysql)" = "750" ]
}

@test 'the datadir is empty' {
    # The single most important assertion in this image. A populated datadir
    # means a baked server UUID and a baked root credential shared by every
    # instance launched from the AMI.
    [ -z "$(ls -A /data/mysql)" ]
}

@test 'no server identity was baked' {
    [ ! -e /data/mysql/auto.cnf ]
}

@test 'the datadir carries the mysqld SELinux context' {
    # semanage ships in policycoreutils-python-utils, which the storage role
    # installs. matchpathcon would need libselinux-utils, which the base image
    # does not guarantee.
    semanage fcontext -l | grep '^/data/mysql' | grep -q mysqld_db_t
}
