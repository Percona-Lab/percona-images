export PACKER_CACHE_DIR := .cache

clean:
	rm -rf .kitchen/ Gemfile.lock ansible/{Ansiblefile.lock,tmp} *.ova *-virtualbox-ovf
	find . -name "*~" -delete

clean-all: clean
	rm -rf .cache

fetch:
	mkdir -p .cache || :
	test -f .cache/id_rsa_vagrant \
	    || curl -L https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant \
		-o .cache/id_rsa_vagrant
	test -f .cache/CentOS-7-x86_64-Vagrant-1611_01.VirtualBox.ova \
        || wget https://atlas.hashicorp.com/centos/boxes/7/versions/1611.01/providers/virtualbox.box \
		-O .cache/CentOS-7-x86_64-Vagrant-1611_01.VirtualBox.ova
	test -f .cache/CentOS-7-x86_64-170201.ova \
		|| wget https://atlas.hashicorp.com/centos/boxes/7/versions/1702.01/providers/virtualbox.box \
		-O .cache/CentOS-7-x86_64-170201.ova
	chmod 600 .cache/id_rsa_vagrant

deps:
	gem install bundler || :
	bundle install
	cd ansible && \
	    librarian-ansible install
	mkdir -p .cache || :
	curl https://releases.hashicorp.com/packer/0.12.1/packer_0.12.1_linux_amd64.zip > .cache/packer.zip
	unzip -o .cache/packer.zip -d ~/bin

pmm-ovf: fetch
	packer build -only virtualbox-ovf packer/pmm.json

pmm-ami:
	packer build -only amazon-ebs packer/pmm.json

mysql57-ovf: fetch
	packer build -only virtualbox-ovf packer/mysql57.json

mysql57-ami:
	packer build -only amazon-ebs packer/mysql57.json

docker-ovf: fetch
	packer build -only virtualbox-ovf packer/docker.json

