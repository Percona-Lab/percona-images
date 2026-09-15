#!/usr/bin/env bats

@test 'no account has an authorized_keys file' {
    ! find /root /home -name authorized_keys -size +0c 2>/dev/null | grep -q .
}

@test 'root login over SSH is disabled' {
    grep -qE '^PermitRootLogin\s+no$' /etc/ssh/sshd_config
}

@test 'no SSH host keys are present' {
    ! ls /etc/ssh/ssh_host_* 2>/dev/null | grep -q .
}

@test 'no OS account has a usable password' {
    # Anything other than a locked or absent hash would be a shared credential
    # in a published image.
    ! awk -F: '$2 !~ /^[!*]/ && $2 != "" { print $1 }' /etc/shadow | grep -q .
}

@test 'no stored MySQL credentials remain' {
    [ ! -f /root/.my.cnf ]
    [ ! -f /home/ec2-user/.my.cnf ]
}

@test 'the machine id is cleared' {
    [ ! -s /etc/machine-id ]
}

@test 'cloud-init state was reset' {
    [ ! -d /var/lib/cloud/instances ]
}

@test 'no package cache remains' {
    ! find /var/cache/dnf -name '*.rpm' 2>/dev/null | grep -q .
}

@test 'no shell history remains' {
    [ ! -f /root/.bash_history ]
    [ ! -f /home/ec2-user/.bash_history ]
}

@test 'ansible was removed before the snapshot' {
    # bats itself is still running from /opt/bats at this point, so its own
    # removal cannot be asserted from inside the image. Task 8 removes it in the
    # same provisioner, immediately after this suite exits.
    ! rpm -q ansible-core
    ! rpm -q ansible
}
