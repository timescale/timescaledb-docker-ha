SHELL = bash
.SHELLFLAGS = -ec
.ONESHELL:
.DELETE_ON_ERROR:

all: help

# setting SLIM changes a bit about what we build, removing some larger things
SLIM ?=

# NOAI doesn't include the ai packages since they are quite large
NOAI ?=

PG_MAJOR?=17
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=

# Additional PostgreSQL extensions we want to include with specific version/commit tags
ifneq ($(SLIM),)
	# Slim:
	PGAI_VERSION?=main
	PGVECTORSCALE_VERSIONS?=0.5.1
	POSTGIS_VERSIONS?=
	PG_AUTH_MON?=
  PG_STAT_MONITOR?=
	PG_LOGERRORS?=
	PGVECTO_RS?=
	TIMESCALEDB_VERSIONS?=latest
	TOOLKIT_VERSIONS?=all
	PGBOUNCER?=
	PGBACKREST?=
	PGBOUNCER_EXPORTER_VERSION?=
	PGBACKREST_EXPORTER_VERSION?=
	PATRONI?=
	BARMAN?=
	TOOLS?=
else
	# Regular:
	PGAI_VERSION?=extension-0.8.0
	PGVECTORSCALE_VERSIONS?=all
	POSTGIS_VERSIONS?=3
	PG_AUTH_MON?=v3.0
	PG_STAT_MONITOR?=2.1.0
	PG_LOGERRORS?=v2.1.3
	PGVECTO_RS?=0.4.0
	TIMESCALEDB_VERSIONS?=all
	TOOLKIT_VERSIONS?=all
	PGBOUNCER?=true
	PGBACKREST?=true
	PGBOUNCER_EXPORTER_VERSION?=0.9.0
	PGBACKREST_EXPORTER_VERSION?=0.18.0
	PATRONI?=true
	BARMAN?=true
	TOOLS?=true
endif

ifneq ($(NOAI),)
	PGAI_VERSION=
	PGVECTORSCALE_VERSIONS=
	PGVECTO_RS=
endif

# This is used to build the docker --platform, so pick amd64 or arm64
PLATFORM?=amd64

DOCKER_TAG_POSTFIX?=
ALL_VERSIONS?=false
OSS_ONLY?=false

# If you're using ephemeral runners, then we want to use the cache, otherwise we don't want caching so that
# we always get updated upstream packages
USE_DOCKER_CACHE?=true
ifeq ($(strip $(USE_DOCKER_CACHE)),true)
  DOCKER_CACHE :=
else
  DOCKER_CACHE := --no-cache
endif

ifeq ($(ALL_VERSIONS),true)
  DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-all
  ifeq ($(PG_MAJOR),17)
    PG_VERSIONS := 17 16 15 14 13 12
  else ifeq ($(PG_MAJOR),16)
    PG_VERSIONS := 16 15 14 13 12
  else ifeq ($(PG_MAJOR),15)
    PG_VERSIONS := 15 14 13 12
  else ifeq ($(PG_MAJOR),14)
    PG_VERSIONS := 14 13 12
  else ifeq ($(PG_MAJOR),13)
    PG_VERSIONS := 13 12
  else ifeq ($(PG_MAJOR),12)
    PG_VERSIONS := 12
  endif
else
  PG_VERSIONS := $(PG_MAJOR)
endif

ifeq ($(SLIM),true)
	DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-slim
	PG_VERSIONS := $(PG_MAJOR)
endif

ifeq ($(NOAI),true)
	DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-noai
endif

ifeq ($(OSS_ONLY),true)
  DOCKER_TAG_POSTFIX := $(strip $(DOCKER_TAG_POSTFIX))-oss
endif

DOCKER_FROM?=ubuntu:22.04
DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescale/timescaledb-ha
DOCKER_PUBLISH_URL?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)

DOCKER_BUILDER_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder
DOCKER_BUILDER_ARCH_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder-$(PLATFORM)
DOCKER_RELEASE_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_RELEASE_ARCH_URL=$(DOCKER_PUBLISH_URL):pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-$(PLATFORM)
CICD_URL=$(DOCKER_PUBLISH_URL):cicd-$(shell printf "%.7s" "$(GITHUB_SHA)")
CICD_ARCH_URL=$(CICD_URL)-$(PLATFORM)

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
VERSION_INFO = /tmp/outputs/version_info
VAR_PGMAJORMINOR="$$(awk -F '=' '/postgresql.version=/ {print $$2}' $(VERSION_INFO) 2>/dev/null)"
VAR_TSVERSION="$$(awk -F '=' '/timescaledb.version=/ {print $$2}' $(VERSION_INFO) 2>/dev/null)"
VAR_TSMAJOR="$$(awk -F '[.=]' '/timescaledb.version=/ {print $$3 "." $$4}' $(VERSION_INFO))"

# In these steps we do some introspection to find out some details of the versions
# that are inside the Docker image. As we use the Ubuntu packages, we do not know until
# after we have built the image, what patch version of PostgreSQL, or PostGIS is installed.
#
# We will then attach this information as OCI labels to the final Docker image
# docker buildx build does a push to export it, so it doesn't exist in the regular local registry yet
VERSION_TAG?=
ifeq ($(VERSION_TAG),)
VERSION_TAG := pg$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-builder-$(PLATFORM)
$(VERSION_INFO): builder
endif
VERSION_IMAGE := $(DOCKER_PUBLISH_URL):$(VERSION_TAG)

# The purpose of publishing the images under many tags, is to provide
# some choice to the user as to their appetite for volatility.
#
#  1. timescale/timescaledb-ha:pg12
#  2. timescale/timescaledb-ha:pg12-ts1.7
#  3. timescale/timescaledb-ha:pg12.3-ts1.7
#  4. timescale/timescaledb-ha:pg12.3-ts1.7.1

$(VERSION_INFO):
	docker rm --force builder_inspector >&/dev/null || true
	docker run --rm -d --name builder_inspector -e PGDATA=/tmp/pgdata --user=postgres "$(VERSION_IMAGE)" sleep 300
	docker cp ./cicd "builder_inspector:/cicd/"
	docker exec builder_inspector /cicd/smoketest.sh || (docker logs -n100 builder_inspector && exit 1)
	mkdir -p /tmp/outputs
	docker cp builder_inspector:/tmp/version_info.log "$(VERSION_INFO)"
	docker rm --force builder_inspector || true

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
					 --build-arg SLIM="$(SLIM)" \
					 --build-arg NOAI="$(NOAI)" \
					 --build-arg DOCKER_FROM="$(DOCKER_FROM)" \
					 --build-arg ALLOW_ADDING_EXTENSIONS="$(ALLOW_ADDING_EXTENSIONS)" \
					 --build-arg GITHUB_DOCKERLIB_POSTGRES_REF="$(GITHUB_DOCKERLIB_POSTGRES_REF)" \
					 --build-arg GITHUB_REPO="$(GITHUB_REPO)" \
					 --build-arg GITHUB_TIMESCALEDB_DOCKER_REF="$(GITHUB_TIMESCALEDB_DOCKER_REF)" \
					 --build-arg INSTALL_METHOD="$(INSTALL_METHOD)" \
					 --build-arg PGAI_VERSION="$(PGAI_VERSION)" \
					 --build-arg PGVECTORSCALE_VERSIONS="$(PGVECTORSCALE_VERSIONS)" \
					 --build-arg PG_AUTH_MON="$(PG_AUTH_MON)" \
					 --build-arg PG_LOGERRORS="$(PG_LOGERRORS)" \
					 --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_STAT_MONITOR="$(PG_STAT_MONITOR)" \
					 --build-arg PG_VERSIONS="$(PG_VERSIONS)" \
					 --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) \
					 --build-arg OSS_ONLY="$(OSS_ONLY)" \
					 --build-arg TIMESCALEDB_VERSIONS="$(TIMESCALEDB_VERSIONS)" \
					 --build-arg TOOLKIT_VERSIONS="$(TOOLKIT_VERSIONS)" \
					 --build-arg PGVECTO_RS="$(PGVECTO_RS)" \
					 --build-arg TOOLS="$(TOOLS)" \
					 --build-arg PATRONI="$(PATRONI)" \
					 --build-arg BARMAN="$(BARMAN)" \
					 --build-arg PGBOUNCER="$(PGBOUNCER)" \
					 --build-arg PGBACKREST="$(PGBACKREST)" \
					 --build-arg RELEASE_URL="$(DOCKER_RELEASE_URL)" \
					 --build-arg BUILDER_URL="$(DOCKER_BUILDER_URL)" \
					 --build-arg PGBOUNCER_EXPORTER_VERSION=$(PGBOUNCER_EXPORTER_VERSION) \
					 --build-arg PGBACKREST_EXPORTER_VERSION=$(PGBACKREST_EXPORTER_VERSION) \
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
fast: ALL_VERSIONS=false
fast: PG_AUTH_MON=
fast: PG_LOGERRORS=
fast: PGAI_VERSION=
fast: PG_VERSIONS=17
fast: POSTGIS_VERSIONS=
fast: TOOLKIT_VERSIONS=
fast: PGVECTORSCALE_VERSIONS=
fast: build

.PHONY: latest
latest: ALL_VERSIONS=false
latest: TIMESCALEDB_VERSIONS=latest
latest: TOOLKIT_VERSIONS=latest
latest: PGVECTORSCALE_VERSIONS=latest
latest: build

prune: # docker system prune -af
	docker system prune -af

ifeq ($(USE_DOCKER_CACHE),false)
builder: prune
endif

.PHONY: get-image-config
get-image-config:
	docker run --platform "linux/$(PLATFORM)" --rm $(DOCKER_RELEASE_URL) cat /.image_config

.PHONY: builder
builder: # build the `builder` target image
builder: DOCKER_EXTRA_BUILDARGS=--target builder
builder:
	$(DOCKER_BUILD_COMMAND) --tag "$(DOCKER_BUILDER_ARCH_URL)"

.PHONY: publish-builder
publish-builder: # build and publish the `builder` target image
publish-builder: builder $(VERSION_INFO)
	docker push "$(DOCKER_BUILDER_ARCH_URL)"
	echo "builder_id=$$(docker inspect "$(DOCKER_BUILDER_ARCH_URL)" | jq -r '.[].RepoDigests[0]')" | tee -a "$(GITHUB_OUTPUT)"

# The prepare step does not build the final image, as we need to use introspection
# to find out what versions of software are installed in this image
.PHONY: release
release: # build the `release` target image
release: DOCKER_EXTRA_BUILDARGS=--target release
release: $(VERSION_INFO)
	$(DOCKER_BUILD_COMMAND) --tag "$(DOCKER_RELEASE_ARCH_URL)" \
		$$(awk -F '=' '{printf "--label com.timescaledb.image."$$1"="$$2" "}' $(VERSION_INFO))

publish-release: # build and publish the `release` target image
publish-release: release
	docker push "$(DOCKER_RELEASE_ARCH_URL)"
	echo "release_id=$$(docker inspect "$(DOCKER_RELEASE_ARCH_URL)" | jq -r '.[].RepoDigests[0]')" | tee -a "$(GITHUB_OUTPUT)"

.PHONY: build-sha
build-sha: # build a specific git commit
build-sha: DOCKER_EXTRA_BUILDARGS=--target release
build-sha: is_ci
ifeq ($(strip $(GITHUB_SHA)),)
	$(error GITHUB_SHA is empty, is this running in github actions?)
endif
	$(DOCKER_BUILD_COMMAND) --tag "$(CICD_ARCH_URL)"

.PHONY: publish-sha
publish-sha: # push the specific git commit image
publish-sha: is_ci
	docker push "$(CICD_ARCH_URL)"

.PHONY: build-tag
build-tag: DOCKER_TAG_POSTFIX?=$(GITHUB_TAG)
build-tag: release

.PHONY: build-oss
build-oss: # build an OSS-only image
build-oss: OSS_ONLY=true
build-oss: DOCKER_TAG_POSTFIX=-oss
build-oss:
	$(DOCKER_BUILD_COMMAND)

.PHONY: build
build: # build a local docker image
build: DOCKER_TAG_POSTFIX=-local
build:
	$(DOCKER_BUILD_COMMAND)

.PHONY: publish-combined-builder-manifest
publish-combined-builder-manifest: $(VERSION_INFO) # publish a combined builder image manifest
	@set -x
	images=()
	for image in $$(cd /tmp/outputs && echo builder-* | sed 's/builder-/sha256:/g'); do
		images+=("--amend" "$(DOCKER_PUBLISH_URL)@$$image")
	done
	cat $(VERSION_INFO) || true
	echo "Creating manifest $(DOCKER_BUILDER_URL) that includes $(DOCKER_BUILDER_URL)-amd64 and $(DOCKER_BUILDER_URL)-arm64 for pg $(VAR_PGMAJORMINOR)}"
	for tag in pg$(PG_MAJOR) pg$(VAR_PGMAJORMINOR); do
		url="$(DOCKER_PUBLISH_URL):$$tag$(DOCKER_TAG_POSTFIX)-builder"
		docker manifest rm "$$url" || true
		docker manifest create "$$url" "$${images[@]}"
		docker manifest push "$$url"
		echo "Pushed $$url ($${images[@]})" | tee -a "$(GITHUB_STEP_SUMMARY)"
	done

.PHONY: publish-combined-manifest
publish-combined-manifest: # publish the main combined manifest that includes amd64 and arm64 images
publish-combined-manifest: $(VERSION_INFO)
	@set -x
	images=()
	for image in $$(cd /tmp/outputs && echo release-* | sed 's/release-/sha256:/g'); do
		images+=("--amend" "$(DOCKER_PUBLISH_URL)@$$image")
	done
	cat $(VERSION_INFO) || true
	echo "Creating manifest $(DOCKER_RELEASE_URL) that includes $(DOCKER_RELEASE_URL)-amd64 and $(DOCKER_RELEASE_URL)-arm64 for pg $(VAR_PGMAJORMINOR)"
	for tag in pg$(PG_MAJOR) pg$(PG_MAJOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMAJORMINOR)-ts$(VAR_TSVERSION); do
		url="$(DOCKER_PUBLISH_URL):$$tag$(DOCKER_TAG_POSTFIX)"
		docker manifest rm "$$url" || true
		docker manifest create "$$url" "$${images[@]}"
		docker manifest push "$$url"
		echo "Pushed $$url ($${images[@]})" | tee -a "$(GITHUB_STEP_SUMMARY)"
	done

.PHONY: publish-manifests
publish-manifests: # publish the combined manifests for the builder and the release images
publish-manifests: publish-combined-builder-manifest publish-combined-manifest

.PHONY: publish-combined-sha
publish-combined-sha: is_ci # publish a combined image manifest for a CICD branch build
	@echo "Creating manifest $(CICD_URL) that includes $(CICD_URL)-amd64 and $(CICD_URL)-arm64"
	amddigest_image="$$(./fetch_tag_digest $(CICD_URL)-amd64)"
	armdigest_image="$$(./fetch_tag_digest $(CICD_URL)-arm64)"
	echo "AMD: $$amddigest_image ARM: $$armdigest_image"
	docker manifest rm "$(CICD_URL)" >& /dev/null || true
	docker manifest create "$(CICD_URL)" --amend "$$amddigest_image" --amend "$$armdigest_image"
	docker manifest push "$(CICD_URL)"
	echo "pushed $(CICD_URL)"
	echo "Pushed $(CICD_URL) (amd:$$amddigest_image, arm:$$armdigest_image)" >> "$(GITHUB_STEP_SUMMARY)"

CHECK_NAME=ha-check
.PHONY: check
check: # check images to see if they have all the requested content
	@set -x
	for arch in amd64 arm64; do
		key="$$(mktemp -u XXXXXX)"
		check_name="$(CHECK_NAME)-$$key"
		echo "### Checking $$arch $(DOCKER_RELEASE_URL)" >> $(GITHUB_STEP_SUMMARY)
		docker rm --force "$$check_name" >&/dev/null || true
		docker run \
			--platform linux/"$$arch" \
			--pull always \
			-d \
			--name "$$check_name" \
			-e PGDATA=/tmp/pgdata \
			--user=postgres \
			"$(DOCKER_RELEASE_URL)" sleep 300
		docker exec -u root "$$check_name" mkdir -p /cicd/scripts
		docker exec -u root "$$check_name" chown -R postgres: /cicd
		tar -cf - -C ./cicd . | docker exec -i "$$check_name" tar -C /cicd -x
		tar -cf - -C ./build_scripts . | docker exec -i "$$check_name" tar -C /cicd/scripts -x
		docker exec -e GITHUB_STEP_SUMMARY="/tmp/step_summary-$$key" -e CI="$(CI)" "$$check_name" /cicd/install_checks -v || { docker logs -n100 "$$check_name"; exit 1; }
		docker exec "$$check_name" cat "/tmp/step_summary-$$key" >> "$(GITHUB_STEP_SUMMARY)" 2>&1
		docker rm --force "$$check_name" >&/dev/null || true
	done

.PHONY: check-sha
check-sha: # check a specific git commit-based image
	@echo "### Checking $(CICD_ARCH_URL)" >> $(GITHUB_STEP_SUMMARY)
	case "$(CICD_ARCH_URL)" in
	*-amd64) arch=amd64;;
	*-arm64) arch=arm64;;
	*) echo "unknown architecture for $(CICD_ARCH_URL)" >&2; exit 1;;
	esac
	key="$$(mktemp -u XXXXXX)"
	check_name="$(CHECK_NAME)-$$key"
	docker rm --force "$$check_name" >&/dev/null || true
	docker run \
		--platform linux/"$$arch" \
		-d \
		--name "$$check_name" \
		-e PGDATA=/tmp/pgdata \
		--user=postgres \
		"$(CICD_ARCH_URL)" sleep 300
	docker exec -u root "$$check_name" mkdir -p /cicd/scripts
	docker exec -u root "$$check_name" chown -R postgres: /cicd
	tar -cf - -C ./cicd . | docker exec -i "$$check_name" tar -C /cicd -x
	tar -cf - -C ./build_scripts . | docker exec -i "$$check_name" tar -C /cicd/scripts -x
	docker exec -e GITHUB_STEP_SUMMARY="/tmp/step_summary-$$key" -e CI="$(CI)" "$$check_name" /cicd/install_checks -v || { docker logs -n100 "$$check_name"; exit 1; }
	docker exec -i "$$check_name" cat "/tmp/step_summary-$$key" >> "$(GITHUB_STEP_SUMMARY)" 2>&1
	docker rm --force "$$check_name" >&/dev/null || true

.PHONY: is_ci
is_ci:
	@if [ "$${CI}" != "true" ]; then echo "environment variable CI is not set to \"true\", are you running this in Github Actions?"; exit 1; fi

.PHONY: list-images
list-images: # list local images
	docker images --filter "label=com.timescaledb.image.install_method=$(INSTALL_METHOD)" --filter "dangling=false"

HELP_TARGET_DEPTH ?= \#
help: # Show how to get started & what targets are available
	@printf "This is a list of all the make targets that you can run, e.g. $(BOLD)make check$(NORMAL)\n\n"
	@awk -F':+ |$(HELP_TARGET_DEPTH)' '/^[0-9a-zA-Z._%-]+:+.+$(HELP_TARGET_DEPTH).+$$/ { printf "$(GREEN)%-20s\033[0m %s\n", $$1, $$3 }' $(MAKEFILE_LIST)
	@echo
