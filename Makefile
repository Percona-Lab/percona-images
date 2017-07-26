 export PACKER_CACHE_DIR := .cache
export PACKER_VERSION := 1.0.2
export CENTOS_ISO := 1706.02

clean:
	rm -rf .kitchen/ Gemfile.lock ansible/{Ansiblefile.lock,tmp} *.ova *-virtualbox-ovf
	find . -name "*~" -delete

clean-all: clean
	rm -rf ${PACKER_CACHE_DIR}

fetch:
	mkdir -p ${PACKER_CACHE_DIR}/${CENTOS_ISO} || :
	test -f ${PACKER_CACHE_DIR}/id_rsa_vagrant \
	    || curl -L https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant \
		-o ${PACKER_CACHE_DIR}/id_rsa_vagrant
	chmod 600 ${PACKER_CACHE_DIR}/id_rsa_vagrant
	test -f ${PACKER_CACHE_DIR}/${CENTOS_ISO}/CentOS7.ova \
		|| wget --progress=dot:giga https://atlas.hashicorp.com/centos/boxes/7/versions/${CENTOS_ISO}/providers/virtualbox.box \
		-O ${PACKER_CACHE_DIR}/${CENTOS_ISO}/CentOS7.ova
	test -f ${PACKER_CACHE_DIR}/${CENTOS_ISO}/box.ovf \
		|| tar -C ${PACKER_CACHE_DIR}/${CENTOS_ISO} -xf ${PACKER_CACHE_DIR}/${CENTOS_ISO}/CentOS7.ova

deps:
	gem install bundler || :
	bundle install
	cd ansible && \
	    librarian-ansible install
	mkdir -p ${PACKER_CACHE_DIR} || :
	curl https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip -o ${PACKER_CACHE_DIR}/packer.zip
	unzip -o ${PACKER_CACHE_DIR}/packer.zip -d ~/bin

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

mongo34-ovf: fetch
	packer build -only virtualbox-ovf packer/mongo34.json

mongo34-ami:
	packer build -only amazon-ebs packer/mongo34.json
