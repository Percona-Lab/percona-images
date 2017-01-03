clean:
	rm -rf .kitchen/ Gemfile.lock ansible/{Ansiblefile.lock,roles,tmp} .cache pmm-ovf mysql57-ovf
	find . -name "*~" -delete

fetch:
	mkdir -p .cache || :
	test -f .cache/id_rsa_vagrant \
	    || curl -L https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant \
		-o .cache/id_rsa_vagrant
	test -f .cache/CentOS-7-x86_64-Vagrant-1611_01.VirtualBox.ova \
        || wget https://atlas.hashicorp.com/centos/boxes/7/versions/1611.01/providers/virtualbox.box \
		-O .cache/CentOS-7-x86_64-Vagrant-1611_01.VirtualBox.ova
	chmod 600 .cache/id_rsa_vagrant

deps:
	bundle install
	cd ansible && \
	    librarian-ansible install

pmm-ovf: fetch
	PACKER_CACHE_DIR=.cache packer build -only virtualbox-ovf packer/pmm.json

pmm-ami:
	packer build -only amazon-ebs packer/pmm.json

mysql57-ovf: fetch
	PACKER_CACHE_DIR=.cache packer build -only virtualbox-ovf packer/mysql57.json

mysql57-ami:
	packer build -only amazon-ebs packer/mysql57.json

