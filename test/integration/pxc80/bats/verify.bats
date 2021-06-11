#!/usr/bin/env bats

@test 'Percona-XtraDB-Cluster-server-80 is installed' {
  rpm -qi percona-xtradb-cluster-server
}

@test 'Check firewalld rules' {
  firewall-cmd --list-ports --permanent | grep '3306/tcp'
  firewall-cmd --list-ports --permanent | grep '42000-42010/tcp'
}
