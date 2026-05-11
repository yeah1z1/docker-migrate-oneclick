.PHONY: check install

check:
	bash -n docker-migrate.sh
	bash -n install.sh
	python3 scripts/check-embedded-web.py

install:
	./install.sh
