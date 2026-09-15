SHELL := /bin/bash
PACKER ?= ~/bin/packer
PACKER_VERSION ?= 1.11.2

.PHONY: deps lint unit container validate build clean

deps:
	mkdir -p ~/bin .cache
	curl -fsSL https://releases.hashicorp.com/packer/$(PACKER_VERSION)/packer_$(PACKER_VERSION)_linux_amd64.zip \
	  -o .cache/packer.zip
	unzip -o .cache/packer.zip -d ~/bin
	$(PACKER) init packer/

lint:
	shellcheck ansible/roles/ps97-firstboot/files/ps97-firstboot.sh \
	  test/smoke/smoke.sh test/container/run.sh scripts/cleanup-orphans.sh
	$(PACKER) fmt -check -diff packer/
	ansible-lint ansible/

unit:
	bats test/unit/

container:
	test/container/run.sh

validate:
	$(PACKER) validate -var-file=packer/release.pkvars.hcl packer/

build:
	$(PACKER) build -var-file=packer/release.pkvars.hcl packer/

clean:
	rm -rf .cache build-*.log IMAGES
