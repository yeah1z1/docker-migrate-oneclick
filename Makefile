.PHONY: check install

check:
	python3 -m py_compile bin/docker-migrate
	python3 -m unittest discover -s tests
	bash -n install.sh

install:
	./install.sh
