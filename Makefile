PG_MAJOR?=15
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=15 14 13 12

# Additional PostgreSQL extensions we want to include with specific version/commit tags
POSTGIS_VERSIONS?="3"
PG_AUTH_MON?=v2.0
PG_STAT_MONITOR?=1.1.1
PG_LOGERRORS?=3c55887b
TIMESCALEDB_VERSIONS?=1.7.5 2.1.0 2.1.1 2.2.0 2.2.1 2.3.0 2.3.1 2.4.0 2.4.1 2.4.2 2.5.0 2.5.1 2.5.2 2.6.0 2.6.1 2.7.0 2.7.1 2.7.2 2.8.0 2.8.1 2.9.1
TIMESCALE_PROMSCALE_EXTENSIONS?=0.5.0 0.5.1 0.5.2 0.5.4 0.6.0 0.7.0 0.8.0
TIMESCALEDB_TOOLKIT_EXTENSIONS?=1.6.0 1.7.0 1.8.0 1.10.1 1.11.0 1.12.0 1.12.1 1.13.0 1.13.1 1.14.0 1.15.0 1.16.0
OSS_ONLY?=false

DOCKER_PLATFORMS?=linux/amd64,linux/arm64

DOCKER_FROM?=ubuntu:22.04
DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescaledev/timescaledb-ha
DOCKER_PUBLISH_URL?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)
DOCKER_TAG_POSTFIX?=-multi
DOCKER_BUILDER_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder
DOCKER_RELEASE_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_CACHE_FROM?=
DOCKER_CACHE_TO?=

DOCKER_CACHE:=
ifneq ($(DOCKER_CACHE_FROM),)
DOCKER_CACHE = --cache-from $(DOCKER_CACHE_FROM)
endif
ifneq ($(DOCKER_CACHE_TO),)
DOCKER_CACHE += --cache-to $(DOCKER_CACHE_TO)
endif

DOCKER_BUILDX_CREATE?=docker buildx create --driver=docker-container --platform linux/amd64,linux/arm64 ha-multinode --use --bootstrap
DOCKER_BUILDX_DESTROY?=docker buildx rm ha-multinode

# These parameters control which entrypoints we add to the scripts
GITHUB_DOCKERLIB_POSTGRES_REF=master
GITHUB_TIMESCALEDB_DOCKER_REF=main

ALLOW_ADDING_EXTENSIONS?=true

# These variables have to do with this Docker repository
GIT_REMOTE=$(shell git config --get remote.origin.url | sed 's/.*@//g')
GIT_STATUS=$(shell git status --porcelain | paste -sd "," -)
GIT_REV?=$(shell git rev-parse HEAD)

INSTALL_METHOD?=docker-ha

# These variables have to do with what software we pull in from github for timescaledb
GITHUB_REPO?=timescale/timescaledb

# We need dynamic variables here, that is why we do not use $(shell awk ...)
VAR_PGMINOR="$$(awk -F '=' '/postgresql.version=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMINOR="$$(awk -F '=' '/timescaledb.version=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMAJOR="$$(awk -F '[.=]' '/timescaledb.version=/ {print $$3 "." $$4}' $(VAR_VERSION_INFO))"
VAR_VERSION_INFO=version_info-$(PG_MAJOR)$(DOCKER_TAG_POSTFIX).log

# We require the use of buildkit, as we use the --secret arguments for docker build
export DOCKER_BUILDKIT = 1

# We label all the Docker Images with the versions of PostgreSQL, TimescaleDB and some other extensions
# afterwards, by using introspection, as minor versions may differ even when using the same
# Dockerfile
DOCKER_BUILD_COMMAND=docker buildx build \
					 --platform "$(DOCKER_PLATFORMS)" \
					 $(DOCKER_CACHE) \
					 --push \
					 --progress=plain \
					 --build-arg DOCKER_FROM="$(DOCKER_FROM)" \
					 --build-arg ALLOW_ADDING_EXTENSIONS="$(ALLOW_ADDING_EXTENSIONS)" \
					 --build-arg GITHUB_DOCKERLIB_POSTGRES_REF="$(GITHUB_DOCKERLIB_POSTGRES_REF)" \
					 --build-arg GITHUB_REPO="$(GITHUB_REPO)" \
					 --build-arg GITHUB_TIMESCALEDB_DOCKER_REF="$(GITHUB_TIMESCALEDB_DOCKER_REF)" \
					 --build-arg INSTALL_METHOD="$(INSTALL_METHOD)" \
					 --build-arg PG_AUTH_MON="$(PG_AUTH_MON)" \
					 --build-arg PG_LOGERRORS="$(PG_LOGERRORS)" \
					 --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_STAT_MONITOR="$(PG_STAT_MONITOR)" \
					 --build-arg PG_VERSIONS="$(PG_VERSIONS)" \
					 --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) \
					 --build-arg OSS_ONLY="$(OSS_ONLY)" \
					 --build-arg TIMESCALEDB_VERSIONS="$(TIMESCALEDB_VERSIONS)" \
					 --build-arg TIMESCALE_PROMSCALE_EXTENSIONS="$(TIMESCALE_PROMSCALE_EXTENSIONS)" \
					 --build-arg TIMESCALEDB_TOOLKIT_EXTENSIONS="$(TIMESCALEDB_TOOLKIT_EXTENSIONS)" \
					 --label com.timescaledb.image.install_method=$(INSTALL_METHOD) \
					 --label org.opencontainers.image.created="$$(date -Iseconds -u)" \
					 --label org.opencontainers.image.revision="$(GIT_REV)" \
					 --label org.opencontainers.image.source="$(GIT_REMOTE)" \
					 --label org.opencontainers.image.vendor=Timescale \
					 $(DOCKER_EXTRA_BUILDARGS) \
					 .

# We provide the fast target as the first (=default) target, as it will skip installing
# many optional extensions, and it will only install a single timescaledb (master) version.
# This is basically useful for developers of this repository, to allow fast feedback cycles.
fast: DOCKER_EXTRA_BUILDARGS= --build-arg GITHUB_TAG=master
fast: PG_AUTH_MON=
fast: PG_LOGERRORS=
fast: PG_VERSIONS=15
fast: POSTGIS_VERSIONS=
fast: TIMESCALEDB_TOOLKIT_EXTENSIONS=
fast: TIMESCALE_PROMSCALE_EXTENSION=
fast: ALLOW_ADDING_EXTENSIONS=true
fast: build

publish-builder: DOCKER_EXTRA_BUILDARGS=--target builder
publish-builder:
	$(DOCKER_BUILDX_CREATE)
	$(DOCKER_BUILD_COMMAND) --tag "$(DOCKER_BUILDER_URL)"
	$(DOCKER_BUILDX_DESTROY)

# The prepare step does not build the final image, as we need to use introspection
# to find out what versions of software are installed in this image
build: DOCKER_EXTRA_BUILDARGS=--target release
build: $(VAR_VERSION_INFO)
	$(DOCKER_BUILDX_CREATE)
	$(DOCKER_BUILD_COMMAND) \
		--tag "$(DOCKER_RELEASE_URL)" \
		$$(for latest in pg$(PG_MAJOR) pg$(PG_MAJOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMINOR); do \
			echo --tag $(DOCKER_PUBLISH_URL):$${latest}$(DOCKER_TAG_POSTFIX)-latest; \
		done) \
		$$(awk -F '=' '{printf "--label com.timescaledb.image."$$1"="$$2" "}' $(VAR_VERSION_INFO))
	$(DOCKER_BUILDX_DESTROY)

VERSION_NAME=versioninfo-pg$(PG_MAJOR)
version_info-%.log: publish-builder
	# In these steps we do some introspection to find out some details of the versions
	# that are inside the Docker image. As we use the Ubuntu packages, we do not know until
	# after we have built the image, what patch version of PostgreSQL, or PostGIS is installed.
	#
	# We will then attach this information as OCI labels to the final Docker image
	# docker buildx build does a push to export it, so it doesn't exist in the regular local registry yet
	@docker rm --force $(VERSION_NAME) || true
	docker run --pull always --rm -d --name $(VERSION_NAME) -e PGDATA=/tmp/pgdata --user=postgres $(DOCKER_BUILDER_URL) sleep 300
	docker cp ./cicd $(VERSION_NAME):/cicd/
	docker exec $(VERSION_NAME) /cicd/smoketest.sh || (docker logs $(VERSION_NAME) && exit 1)
	docker cp $(VERSION_NAME):/tmp/version_info.log $(VAR_VERSION_INFO)
	docker rm --force $(VERSION_NAME) || true

# The purpose of publishing the images under many tags, is to provide
# some choice to the user as to their appetite for volatility.
#
#  1. timescale/timescaledb-ha:pg12-latest
#  2. timescale/timescaledb-ha:pg12-ts1.7-latest
#  3. timescale/timescaledb-ha:pg12.3-ts1.7-latest
#  4. timescale/timescaledb-ha:pg12.3-ts1.7.1-latest

build-oss: OSS_ONLY=true
build-oss: DOCKER_TAG_POSTFIX=-oss
build-oss: build

publish: is_ci build

CHECK_NAME=ha-check-pg$(PGMAJOR)
check:
	@for arch in amd64 arm64; do \
		docker rm --force $(CHECK_NAME); \
		docker run --pull always --platform linux/$$arch -d --name $(CHECK_NAME) -e PGDATA=/tmp/pgdata --user=postgres "$(DOCKER_RELEASE_URL)" sleep 300; \
		docker cp ./cicd $(CHECK_NAME):/cicd/; \
		docker exec -e CI=$(CI) $(CHECK_NAME) /cicd/install_checks -v || { docker logs -n100 $(CHECK_NAME); exit 1; }; \
	done
	docker rm --force $(CHECK_NAME) || true

is_ci:
	@if [ "$${CI}" != "true" ]; then echo "environment variable CI is not set to \"true\", are you running this in Github Actions?"; exit 1; fi

list-images:
	docker images --filter "label=com.timescaledb.image.install_method=$(INSTALL_METHOD)" --filter "dangling=false"

build-tag: DOCKER_TAG_POSTFIX?=$(GITHUB_TAG)
build-tag: build

.PHONY: fast prepare build-oss release build publish test tag build-tag is_ci list-images
