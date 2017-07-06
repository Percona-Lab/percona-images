#!/usr/bin/env bats

@test 'Percona-Server-MongoDB-34 is installed' {
  rpm -qi Percona-Server-MongoDB-34
}

@test 'Percona-Server-MongoDB-34 is up and running' {
    skip 'not implemented'
}

@test 'Check firewalld rules' {
  firewall-cmd --list-ports --permanent | grep '27017/tcp'
  firewall-cmd --list-ports --permanent | grep '42000-42010/tcp'
}

