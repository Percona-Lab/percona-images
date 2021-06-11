#!/usr/bin/env bats

@test 'Percona-Server-server-80 is installed' {
  rpm -qi percona-server-server
}

@test 'Check firewalld rules' {
  firewall-cmd --list-ports --permanent | grep '3306/tcp'
  firewall-cmd --list-ports --permanent | grep '42000-42010/tcp'
}
