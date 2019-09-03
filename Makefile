PG_MAJOR?=11
PGVERSION=pg$(PG_MAJOR)

GIT_COMMIT=$(shell git describe --always --tag --long --abbrev=8)
GIT_BRANCH=$(shell git symbolic-ref --short HEAD)
GIT_REMOTE=$(shell git config --get remote.origin.url | sed 's/.*@//g')
GIT_STATUS=$(shell git status --porcelain | paste -sd "," -)
GIT_AUTHOR?=$(USER)
GIT_REV?=$(shell git rev-parse HEAD)

# We store the GIT_INFO_JSON inside the Docker image if we build it using make
# this ensures we always know if we have an image, what the git context was when
# it was created
GIT_INFO_JSON=$(shell echo '{"url": "'$(GIT_REMOTE)'", "revision": "'$(GIT_REV)'", "status": "'$(GIT_STATUS)'", "author": "'$(GIT_AUTHOR)'"}')

TAG?=$(subst /,_,$(GIT_BRANCH)-$(GIT_COMMIT))
REGISTRY?=localhost:5000
TIMESCALEDB_REPOSITORY?=timescale/timescaledb-docker-ha
TIMESCALEDB_IMAGE?=$(REGISTRY)/$(TIMESCALEDB_REPOSITORY)
TIMESCALEDB_RELEASE_URL?=$(TIMESCALEDB_IMAGE):$(TAG)-$(PGVERSION)
TIMESCALEDB_LATEST_URL?=$(TIMESCALEDB_IMAGE):latest-$(PGVERSION)

DOCKER_BUILD_COMMAND=docker build --build-arg GIT_INFO_JSON='$(GIT_INFO_JSON)' --build-arg PG_MAJOR=$(PG_MAJOR)

default: build

.build_$(TAG)_$(PGVERSION)_oss: Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL)-oss --build-arg OSS_ONLY=" -DAPACHE_ONLY=1"  .
	docker tag $(TIMESCALEDB_RELEASE_URL)-oss $(TIMESCALEDB_LATEST_URL)-oss
	touch .build_$(TAG)_$(PGVERSION)_oss

.build_$(TAG)_$(PGVERSION)_nov: Dockerfile customizations/nov-namedatalen.sh
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL)-nov --build-arg TS_CUSTOMIZATION=nov-namedatalen.sh  .
	docker tag $(TIMESCALEDB_RELEASE_URL)-nov $(TIMESCALEDB_LATEST_URL)-nov
	touch .build_$(TAG)_$(PGVERSION)_nov

.build_$(TAG)_$(PGVERSION): Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL) .
	docker tag $(TIMESCALEDB_RELEASE_URL) $(TIMESCALEDB_LATEST_URL)
	touch .build_$(TAG)_$(PGVERSION)

build: .build_$(TAG)_$(PGVERSION)

build-oss: .build_$(TAG)_$(PGVERSION)_oss

build-nov: .build_$(TAG)_$(PGVERSION)_nov

build-all: build build-oss build-nov

push: build
	docker push $(TIMESCALEDB_RELEASE_URL)

push-oss: build-oss
	docker push $(TIMESCALEDB_RELEASE_URL)-oss

push-nov: build-nov
	docker push $(TIMESCALEDB_RELEASE_URL)-nov

push-all: push push-oss push-nov

test: build
	# Very simple test that verifies the following things:
	# - PATH has the correct setting
	# - initdb succeeds
	# - timescaledb is correctly injected into the default configuration
	#
	# TODO: Create a good test-suite. For now, it's nice to have this target in CI/CD,
	# and have it do something worthwhile
	docker run --rm --tty $(TIMESCALEDB_RELEASE_URL) /bin/bash -c "initdb -D test && grep timescaledb test/postgresql.conf"

clean:
	rm -f *~ .build_*

.PHONY: default build build-oss build-nov build-all push push-oss push-nov push-all test
