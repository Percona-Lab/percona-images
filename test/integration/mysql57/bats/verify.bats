#!/usr/bin/env bats

@test 'Percona-Server-server is up and running' {
    PASS=$(grep 'temporary password' /var/log/mysqld.log | sed -e 's/.*localhost: //')
    run mysql -uroot -p"${PASS}" -e 'SELECT Host, User FROM mysql.user' --connect-expired-password
    [[ "$output" =~ 'You must reset your password using ALTER USER statement before executing this statement.' ]]
}

@test 'Percona-Server-server57 is installed' {
  rpm -qi Percona-Server-server-57
}

@test 'Check firewalld rules' {
  firewall-cmd --list-ports --permanent | grep '3306/tcp'
  firewall-cmd --list-ports --permanent | grep '42000-42005/tcp'
}

