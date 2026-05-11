.PHONY: check install

check:
	bash -n docker-migrate.sh
	bash -n install.sh
	shellcheck docker-migrate.sh install.sh

install:
	./install.sh
