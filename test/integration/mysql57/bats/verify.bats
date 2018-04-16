#!/usr/bin/env bats

@test 'Percona-Server-server57 is installed' {
  rpm -qi Percona-Server-server-57
}

@test 'Check firewalld rules' {
  firewall-cmd --list-ports --permanent | grep '3306/tcp'
  firewall-cmd --list-ports --permanent | grep '42000-42010/tcp'
}
