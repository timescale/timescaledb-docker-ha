PG_MAJOR?=11
PGVERSION=pg$(PG_MAJOR)
POSTGIS_VERSIONS?="3 2.5"

# CI/CD can benefit from specifying a specific apt packages mirror
DEBIAN_REPO_MIRROR?=""

# These variables have to do with this Docker repository
GIT_COMMIT=$(shell git describe --always --tag --long --abbrev=8)
GIT_BRANCH=$(shell git symbolic-ref --short HEAD)
GIT_REMOTE=$(shell git config --get remote.origin.url | sed 's/.*@//g')
GIT_STATUS=$(shell git status --porcelain | paste -sd "," -)
GIT_AUTHOR?=$(USER)
GIT_REV?=$(shell git rev-parse HEAD)

# These variables have to do with what software we pull in from github
GITHUB_USER?=""
GITHUB_TOKEN?=""
GITHUB_REPO?="timescale/timescaledb"
GITHUB_TAG?="master"

# We store the GIT_INFO_JSON inside the Docker image if we build it using make
# this ensures we always know if we have an image, what the git context was when
# it was created
GIT_INFO_JSON=$(shell echo '{"url": "'$(GIT_REMOTE)'", "revision": "'$(GIT_REV)'", "status": "'$(GIT_STATUS)'", "author": "'$(GIT_AUTHOR)'"}')

TAG?=$(subst /,_,$(GIT_BRANCH)-$(GIT_COMMIT))
REGISTRY?=localhost:5000
TIMESCALEDB_REPOSITORY?=timescale/timescaledb-docker-ha
TIMESCALEDB_IMAGE?=$(REGISTRY)/$(TIMESCALEDB_REPOSITORY)
TIMESCALEDB_BUILDER_URL?=$(TIMESCALEDB_IMAGE):builder-$(PGVERSION)
TIMESCALEDB_RELEASE_URL?=$(TIMESCALEDB_IMAGE):$(TAG)-$(PGVERSION)
TIMESCALEDB_LATEST_URL?=$(TIMESCALEDB_IMAGE):latest-$(PGVERSION)
PG_PROMETHEUS?=0.2.2

DOCKER_BUILD_COMMAND=docker build --build-arg GIT_INFO_JSON='$(GIT_INFO_JSON)' --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_PROMETHEUS=$(PG_PROMETHEUS) --build-arg DEBIAN_REPO_MIRROR=$(DEBIAN_REPO_MIRROR) $(DOCKER_IMAGE_CACHE)

default: build

.build_$(TAG)_$(PGVERSION)_postgis: Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL)-postgis --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) .
	docker tag $(TIMESCALEDB_RELEASE_URL)-postgis $(TIMESCALEDB_LATEST_URL)-postgis
	touch .build_$(TAG)_$(PGVERSION)_postgis

.build_$(TAG)_$(PGVERSION)_oss: Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL)-oss --build-arg OSS_ONLY=" -DAPACHE_ONLY=1"  .
	docker tag $(TIMESCALEDB_RELEASE_URL)-oss $(TIMESCALEDB_LATEST_URL)-oss
	touch .build_$(TAG)_$(PGVERSION)_oss

.build_$(TAG)_$(PGVERSION)_tag: Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL) \
		--build-arg GITHUB_REPO=$(GITHUB_REPO) --build-arg GITHUB_USER=$(GITHUB_USER) \
		--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) --build-arg GITHUB_TAG=$(GITHUB_TAG) .
	@touch .build_$(TAG)_$(PGVERSION)_tag

.build_$(TAG)_$(PGVERSION): Dockerfile
	$(DOCKER_BUILD_COMMAND) -t $(TIMESCALEDB_RELEASE_URL) .
	docker tag $(TIMESCALEDB_RELEASE_URL) $(TIMESCALEDB_LATEST_URL)
	touch .build_$(TAG)_$(PGVERSION)

builder:
	$(DOCKER_BUILD_COMMAND) --target builder -t $(TIMESCALEDB_BUILDER_URL) .

build: builder .build_$(TAG)_$(PGVERSION)

build-postgis: .build_$(TAG)_$(PGVERSION)_postgis

build-oss: .build_$(TAG)_$(PGVERSION)_oss

build-tag: .build_$(TAG)_$(PGVERSION)_tag
	docker image ls $(TIMESCALEDB_RELEASE_URL)

build-all: build build-oss

push-builder: builder
	docker push $(TIMESCALEDB_BUILDER_URL)

push: build
	docker push $(TIMESCALEDB_RELEASE_URL)
	docker push $(TIMESCALEDB_LATEST_URL)

push-postgis: build-postgis
	docker push $(TIMESCALEDB_RELEASE_URL)-postgis

push-oss: build-oss
	docker push $(TIMESCALEDB_RELEASE_URL)-oss

push-all: push push-postgis push-oss

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

.PHONY: default build builder build-postgis build-oss build-tag build-all push push-builder push-postgis push-oss push-all test

