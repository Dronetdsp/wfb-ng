ARCH ?= $(shell uname -i)
PYTHON ?= /usr/bin/python3
COMMIT ?= $(shell git rev-parse HEAD)
VERSION ?= $(shell $(PYTHON) ./version.py $(shell git show -s --format="%ct" $(shell git rev-parse HEAD)) $(shell git rev-parse --abbrev-ref HEAD))
SOURCE_DATE_EPOCH ?= $(shell git show -s --format="%ct" $(shell git rev-parse HEAD))
DOCKER_SRC_IMAGE ?= "arm64v8/ubuntu:latest"

export VERSION COMMIT SOURCE_DATE_EPOCH

_LDFLAGS := $(LDFLAGS) -lrt -lpcap -lsodium
_CFLAGS := $(CFLAGS) -Wall -O2 -DWFB_VERSION='"$(VERSION)-$(shell /bin/bash -c '_tmp=$(COMMIT); echo $${_tmp::8}')"'

all: all_bin gs.key test

env:
	virtualenv env --python=$(PYTHON)
	./env/bin/pip install --upgrade pip setuptools stdeb

all_bin: wfb_rx wfb_tx wfb_keygen

gs.key: wfb_keygen
	@if ! [ -f gs.key ]; then ./wfb_keygen; fi

src/%.o: src/%.c src/*.h
	$(CC) $(_CFLAGS) -std=gnu99 -c -o $@ $<

src/%.o: src/%.cpp src/*.hpp src/*.h
	$(CXX) $(_CFLAGS) -std=gnu++11 -c -o $@ $<

wfb_rx: src/rx.o src/radiotap.o src/fec.o src/wifibroadcast.o
	$(CXX) -o $@ $^ $(_LDFLAGS)

wfb_tx: src/tx.o src/fec.o src/wifibroadcast.o
	$(CXX) -o $@ $^ $(_LDFLAGS)

wfb_keygen: src/keygen.o
	$(CC) -o $@ $^ $(_LDFLAGS)

test: all_bin
	PYTHONPATH=`pwd` trial3 wfb_ng.tests

rpm:  all_bin env
	rm -rf dist
	./env/bin/python ./setup.py bdist_rpm --force-arch $(ARCH)
	rm -rf wfb_ng.egg-info/

deb:  all_bin env
	rm -rf deb_dist
	./env/bin/python ./setup.py --command-packages=stdeb.command bdist_deb
	rm -rf wfb_ng.egg-info/ wfb-ng-$(VERSION).tar.gz

__deb_docker: all_bin
	rm -rf deb_dist
	$(PYTHON) ./setup.py --command-packages=stdeb.command bdist_deb
	rm -rf wfb_ng.egg-info/ wfb-ng-$(VERSION).tar.gz
	chown -R --reference=. .

bdist: all_bin
	rm -rf dist
	$(PYTHON) ./setup.py bdist --plat-name linux-$(ARCH)
	rm -rf wfb_ng.egg-info/

clean:
	rm -rf env wfb_rx wfb_tx wfb_keygen dist deb_dist build wfb_ng.egg-info wfb-ng-*.tar.gz _trial_temp *~ src/*.o


deb_docker:
	TAG="wfb-ng:build-`date +%s`"; docker build -t $$TAG docker --build-arg SRC_IMAGE=$(DOCKER_SRC_IMAGE)  && \
	docker run -i --rm -v $(PWD):/build $$TAG bash -c "export VERSION=$(VERSION) COMMIT=$(COMMIT) SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) PYTHON=python3 && cd /build && make clean && make test && make __deb_docker"
	docker ps -a -f 'status=exited' --format '{{ .ID }} {{ .Image }}' | grep wfb-ng:build | tail -n+11 | while read c i ; do docker rm $$c && docker rmi $$i; done
