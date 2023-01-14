SHELL = bash
.SHELLFLAGS = -ec
.ONESHELL:
.DELETE_ON_ERROR:

all: help

PG_MAJOR?=15
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=

# Additional PostgreSQL extensions we want to include with specific version/commit tags
POSTGIS_VERSIONS?="3"
PG_AUTH_MON?=v2.0
PG_STAT_MONITOR?=1.1.1
PG_LOGERRORS?=3c55887b
TIMESCALEDB_VERSIONS?=1.7.5 2.1.0 2.1.1 2.2.0 2.2.1 2.3.0 2.3.1 2.4.0 2.4.1 2.4.2 2.5.0 2.5.1 2.5.2 2.6.0 2.6.1 2.7.0 2.7.1 2.7.2 2.8.0 2.8.1 2.9.1
TIMESCALE_PROMSCALE_EXTENSIONS?=0.5.0 0.5.1 0.5.2 0.5.4 0.6.0 0.7.0 0.8.0
TIMESCALEDB_TOOLKIT_EXTENSIONS?=1.6.0 1.7.0 1.8.0 1.10.1 1.11.0 1.12.0 1.12.1 1.13.0 1.13.1 1.14.0 1.15.0 1.16.0

# This is used to build the docker --platform, so pick amd64 or arm64
PLATFORM?=amd64

DOCKER_TAG_POSTFIX?=-multi
ALL_VERSIONS?=false
OSS_ONLY?=false

USE_DOCKER_CACHE?=true
ifeq ($(strip $(USE_DOCKER_CACHE)),true)
  DOCKER_CACHE :=
else
  DOCKER_CACHE := --no-cache
endif

ifeq ($(ALL_VERSIONS),true)
  DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-all
  ifeq ($(PG_MAJOR),15)
    PG_VERSIONS := 15 14 13 12
  else ifeq ($(PG_MAJOR),14)
    PG_VERSIONS := 14 13 12
  endif
else
  PG_VERSIONS := $(PG_MAJOR)
endif

ifeq ($(OSS_ONLY),true)
  DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-oss
endif

DOCKER_FROM?=ubuntu:22.04
DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescaledev/timescaledb-ha
DOCKER_PUBLISH_URL?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)

DOCKER_BUILDER_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder
DOCKER_BUILDER_ARCH_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder-$(PLATFORM)
DOCKER_RELEASE_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_RELEASE_ARCH_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-$(PLATFORM)

GITHUB_STEP_SUMMARY?=/dev/null
GITHUB_OUTPUT?=/dev/null

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
VAR_PGMAJOR="$$(awk -F '=' '/postgresql.version=/ {print $$2}' $(VAR_VERSION_INFO) 2>/dev/null)"
VAR_TSVERSION="$$(awk -F '=' '/timescaledb.version=/ {print $$2}' $(VAR_VERSION_INFO) 2>/dev/null)"
VAR_TSMAJOR="$$(awk -F '[.=]' '/timescaledb.version=/ {print $$3 "." $$4}' $(VAR_VERSION_INFO))"
VAR_VERSION_INFO=version_info-$(PG_MAJOR)$(DOCKER_TAG_POSTFIX).log

# We require the use of buildkit, as we use the --secret arguments for docker build
export DOCKER_BUILDKIT = 1

# We label all the Docker Images with the versions of PostgreSQL, TimescaleDB and some other extensions
# afterwards, by using introspection, as minor versions may differ even when using the same
# Dockerfile
DOCKER_BUILD_COMMAND=docker build \
					 $(DOCKER_CACHE) \
					 --platform "linux/$(PLATFORM)" \
					 --pull \
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
					 --build-arg RELEASE_URL="$(DOCKER_RELEASE_URL)" \
					 --build-arg BUILDER_URL="$(DOCKER_BUILDER_URL)" \
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
.PHONY: fast
fast: DOCKER_EXTRA_BUILDARGS= --build-arg GITHUB_TAG=master
fast: PG_AUTH_MON=
fast: PG_LOGERRORS=
fast: PG_VERSIONS=15
fast: POSTGIS_VERSIONS=
fast: TIMESCALEDB_TOOLKIT_EXTENSIONS=
fast: TIMESCALE_PROMSCALE_EXTENSION=
fast: ALLOW_ADDING_EXTENSIONS=true
fast: build

.PHONY: builder
builder: # build the `builder` target image
builder: DOCKER_EXTRA_BUILDARGS=--target builder
builder:
	$(DOCKER_BUILD_COMMAND) --tag "$(DOCKER_BUILDER_ARCH_URL)"

.PHONY: publish-builder
publish-builder: # build and publish the `builder` target image
publish-builder: builder
	docker push "$(DOCKER_BUILDER_ARCH_URL)"

# The prepare step does not build the final image, as we need to use introspection
# to find out what versions of software are installed in this image
.PHONY: release
release: # build the `release` target image
release: DOCKER_EXTRA_BUILDARGS=--target release
release: $(VAR_VERSION_INFO)
	$(DOCKER_BUILD_COMMAND) --tag "$(DOCKER_RELEASE_ARCH_URL)" \
		$$(awk -F '=' '{printf "--label com.timescaledb.image."$$1"="$$2" "}' $(VAR_VERSION_INFO))

publish-release: # build and publish the `release` target image
publish-release: release
	docker push "$(DOCKER_RELEASE_ARCH_URL)"

VERSION_TAG?=
ifeq ($(VERSION_TAG),)
VERSION_TAG := pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder-$(PLATFORM)
version_info-%.log: builder
endif
VERSION_IMAGE := $(DOCKER_PUBLISH_URL):$(VERSION_TAG)
VERSION_NAME=versioninfo-pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
version_info-%.log:
	# In these steps we do some introspection to find out some details of the versions
	# that are inside the Docker image. As we use the Ubuntu packages, we do not know until
	# after we have built the image, what patch version of PostgreSQL, or PostGIS is installed.
	#
	# We will then attach this information as OCI labels to the final Docker image
	# docker buildx build does a push to export it, so it doesn't exist in the regular local registry yet
	@docker rm --force "$(VERSION_NAME)" >&/dev/null || true
	docker run --pull always --rm -d --name "$(VERSION_NAME)" -e PGDATA=/tmp/pgdata --user=postgres "$(VERSION_IMAGE)" sleep 300
	docker cp ./cicd "$(VERSION_NAME):/cicd/"
	docker exec "$(VERSION_NAME)" /cicd/smoketest.sh || (docker logs -n100 "$(VERSION_NAME)" && exit 1)
	docker cp "$(VERSION_NAME):/tmp/version_info.log" "$(VAR_VERSION_INFO)"
	docker rm --force "$(VERSION_NAME)" || true

# The purpose of publishing the images under many tags, is to provide
# some choice to the user as to their appetite for volatility.
#
#  1. timescale/timescaledb-ha:pg12-latest
#  2. timescale/timescaledb-ha:pg12-ts1.7-latest
#  3. timescale/timescaledb-ha:pg12.3-ts1.7-latest
#  4. timescale/timescaledb-ha:pg12.3-ts1.7.1-latest

.PHONY: build-oss
build-oss: # build an OSS-only image
build-oss: OSS_ONLY=true
build-oss: DOCKER_TAG_POSTFIX=-oss
build-oss: release

.PHONY: publish-combined-builder-manifest
publish-combined-builder-manifest: # publish a combined builder image manifest
	@echo "pulling $(DOCKER_BUILDER_URL)-amd64 and $(DOCKER_BUILDER_URL)-arm64"
	docker pull "$(DOCKER_BUILDER_URL)-amd64"
	docker pull "$(DOCKER_BUILDER_URL)-arm64"
	docker manifest rm "$(DOCKER_BUILDER_URL)" >& /dev/null || true
	docker manifest create "$(DOCKER_BUILDER_URL)" --amend "$(DOCKER_BUILDER_URL)-amd64" --amend "$(DOCKER_BUILDER_URL)-arm64"
	docker manifest push "$(DOCKER_BUILDER_URL)"
	echo "pushed $(DOCKER_BUILDER_URL)"
	echo "Pushed $(DOCKER_BUILDER_URL)" >> "$(GITHUB_STEP_SUMMARY)"

# since we're using immutable tags, we don't need to pull/find the child image SHAs, we can just use the tags
.PHONY: publish-combined-manifest
publish-combined-manifest: # publish the main combined manifest that includes amd64 and arm64 images
publish-combined-manifest: $(VAR_VERSION_INFO)
	@echo "pulling $(DOCKER_RELEASE_URL)-amd64 and $(DOCKER_RELEASE_URL)-arm64"
	docker pull "$(DOCKER_RELEASE_URL)-amd64"
	docker pull "$(DOCKER_RELEASE_URL)-arm64"
	docker manifest rm "$(DOCKER_RELEASE_URL)" >& /dev/null || true
	docker manifest create "$(DOCKER_RELEASE_URL)" --amend "$(DOCKER_RELEASE_URL)-amd64" --amend "$(DOCKER_RELEASE_URL)-arm64"
	docker manifest push "$(DOCKER_RELEASE_URL)"
	echo "pushed $(DOCKER_RELEASE_URL)"
	echo "Pushed $(DOCKER_RELEASE_URL)" >> "$(GITHUB_STEP_SUMMARY)"
	for tag in pg$(PG_MAJOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMAJOR)-ts$(VAR_TSVERSION); do
		url="$(DOCKER_PUBLISH_URL):$$tag$(DOCKER_TAG_POSTFIX)"
		echo "pushing $$url"
		docker manifest rm "$$url" >&/dev/null || true
		docker manifest create "$$url" --amend "$(DOCKER_RELEASE_URL)-amd64" "$(DOCKER_RELEASE_URL)-arm64"
		docker manifest push "$$url"
		echo "pushed $$url"
		echo "Pushed $$url" >> "$(GITHUB_STEP_SUMMARY)"
	done

.PHONY: publish-manifests
publish-manifests: # publish the combined manifests for the builder and the release images
publish-manifests: publish-combined-builder-manifest publish-combined-manifest

CHECK_NAME=ha-check-pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
.PHONY: check
check: # check images to see if they have all the requested content
	@for arch in amd64 arm64; do \
		key="$$(mktemp -u XXXXXX)"
		check_name="$(CHECK_NAME)-$$arch-$$key"
		echo "Checking $(DOCKER_RELEASE_URL)" >> $(GITHUB_STEP_SUMMARY); \
		echo "### Checking $$arch $(DOCKER_RELEASE_URL)" >> $(GITHUB_STEP_SUMMARY); \
		docker rm --force "$(CHECK_NAME)" >&/dev/null || true
		docker run \
			--platform linux/"$$arch" \
			--pull always \
			-d \
			--name "$$check_name" \
			-e PGDATA=/tmp/pgdata \
			--user=postgres \
			"$(DOCKER_RELEASE_URL)" sleep 300
		docker exec -u root "$$check_name" mkdir -p /cicd/scripts
		tar -cf - -C ./cicd . | docker exec -u root -i "$$check_name" tar -C /cicd -x
		tar -cf - -C ./build_scripts . | docker exec -u root -i "$$check_name" tar -C /cicd/scripts -x
		docker exec -e GITHUB_STEP_SUMMARY="/tmp/step_summary-$$key" -e CI="$(CI)" "$$check_name" /cicd/install_checks -v || { docker logs -n100 "$$check_name"; exit 1; }
		docker rm --force "$$check_name" >&/dev/null || true
	done

.PHONY: is_ci
is_ci:
	@if [ "$${CI}" != "true" ]; then echo "environment variable CI is not set to \"true\", are you running this in Github Actions?"; exit 1; fi

.PHONY: list-images
list-images: # list local images
	docker images --filter "label=com.timescaledb.image.install_method=$(INSTALL_METHOD)" --filter "dangling=false"

.PHONY: build-tag
build-tag: DOCKER_TAG_POSTFIX?=$(GITHUB_TAG)
build-tag: build

HELP_TARGET_DEPTH ?= \#
help: # Show how to get started & what targets are available
	@printf "This is a list of all the make targets that you can run, e.g. $(BOLD)make check$(NORMAL)\n\n"
	@awk -F':+ |$(HELP_TARGET_DEPTH)' '/^[0-9a-zA-Z._%-]+:+.+$(HELP_TARGET_DEPTH).+$$/ { printf "$(GREEN)%-20s\033[0m %s\n", $$1, $$3 }' $(MAKEFILE_LIST)
	@echo
