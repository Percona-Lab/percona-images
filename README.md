# percona-images

Packer config to build Percona base boxes

- Install dependencies

```
bundle install
cd ansible
  librarian-ansible install
cd ..
```

- Check Ansible config and run unit tests

```
kitchen test pmm-ovf
kitchen test pmm-ami
kitchen test mysql57-ovf
kitchen test mysql57-ami
```

- Build PMM server

```
make pmm-ovf
make pmm-ami
```

- Build Percona Server for MySQL

```
make mysql57-ovf
make mysql57-ami
```
