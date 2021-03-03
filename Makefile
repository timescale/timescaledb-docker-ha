PG_MAJOR?=12
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=12 11

# Additional PostgreSQL extensions we want to include with specific version/commit tags
POSTGIS_VERSIONS?="2.5 3"
PG_AUTH_MON?=a38b2341
PG_LOGERRORS?=3c55887b
TIMESCALE_PROMSCALE_EXTENSION?=0.1.1
TIMESCALE_TSDB_ADMIN?=

DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescale/timescaledb-ha
DOCKER_PUBLISH_URL?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)
DOCKER_TAG_POSTFIX?=
DOCKER_TAG_PREPARE=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_TAG_LABELED=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-labeled

# We add a patch increment to all our immutable Docker Images. To figure out which patch number
# to assign, we need 1 repository that is the canonical source of truth
DOCKER_CANONICAL_URL?=https://index.docker.io/v1/repositories/timescale/timescaledb-ha

# These variables have to do with this Docker repository
GIT_REMOTE=$(shell git config --get remote.origin.url | sed 's/.*@//g')
GIT_STATUS=$(shell git status --porcelain | paste -sd "," -)
GIT_REV?=$(shell git rev-parse HEAD)

INSTALL_METHOD?=docker-ha

# These variables have to do with what software we pull in from github for timescaledb
GITHUB_USER?=
GITHUB_TOKEN?=
GITHUB_REPO?=timescale/timescaledb
GITHUB_TAG?=master

# We need dynamic variables here, that is why we do not use $(shell awk ...)
VAR_PGMINOR="$$(awk -F '=' '/postgresql=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMINOR="$$(awk -F '=' '/timescaledb=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMAJOR="$$(awk -F '[.=]' '/timescaledb=/ {print $$2 "." $$3}' $(VAR_VERSION_INFO))"
VAR_VERSION_INFO=version_info-$(PG_MAJOR)$(DOCKER_TAG_POSTFIX).log

# We label all the Docker Images with the versions of PostgreSQL, TimescaleDB and some other extensions
# afterwards, by using introspection, as minor versions may differ even when using the same
# Dockerfile
DOCKER_BUILD_COMMAND=docker build  \
					 --build-arg CI_JOB_TOKEN="$(CI_JOB_TOKEN)" \
					 --build-arg DEBIAN_REPO_MIRROR=$(DEBIAN_REPO_MIRROR) \
					 --build-arg INSTALL_METHOD="$(INSTALL_METHOD)" \
					 --build-arg PG_AUTH_MON="$(PG_AUTH_MON)" \
					 --build-arg PG_LOGERRORS="$(PG_LOGERRORS)" \
					 --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_VERSIONS="$(PG_VERSIONS)" \
					 --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) \
					 --build-arg TIMESCALE_PROMSCALE_EXTENSION="$(TIMESCALE_PROMSCALE_EXTENSION)" \
					 --build-arg TIMESCALE_TSDB_ADMIN="$(TIMESCALE_TSDB_ADMIN)" \
					 --label org.opencontainers.image.created="$$(date -Iseconds --utc)" \
					 --label org.opencontainers.image.revision="$(GIT_REV)" \
					 --label org.opencontainers.image.source="$(GIT_REMOTE)" \
					 --label org.opencontainers.image.vendor=Timescale \
					 $(DOCKER_EXTRA_BUILDARGS) \
					 .

DOCKER_EXEC_COMMAND=docker exec -i $(DOCKER_TAG_PREPARE) timeout 60

# We provide the fast target as the first (=default) target, as it will skip installing
# many optional extensions, and it will only install a single timescaledb (master) version.
# This is basically useful for developers of this repository, to allow fast feedback cycles.
fast: PG_VERSIONS=12
fast: PG_AUTH_MON=
fast: POSTGIS_VERSIONS=
fast: PG_LOGERRORS=
fast: DOCKER_EXTRA_BUILDARGS= --build-arg GITHUB_TAG=master
fast: prepare

# The prepare step does not build the final image, as we need to use introspection
# to find out what versions of software are installed in this image
prepare:
	$(DOCKER_BUILD_COMMAND) --tag $(DOCKER_TAG_PREPARE)

version_info-%.log: prepare
	# In these steps we do some introspection to find out some details of the versions
	# that are inside the Docker image. As we use the Debian packages, we do not know until
	# after we have built the image, what patch version of PostgreSQL, or PostGIS is installed.
	#
	# We will then attach this information as OCI labels to the final Docker image
	docker stop $(DOCKER_TAG_PREPARE) || true
	docker run -d --rm --name $(DOCKER_TAG_PREPARE) -e PGDATA=/tmp/pgdata --user=postgres $(DOCKER_TAG_PREPARE) \
		sh -c 'initdb && timeout 60 postgres'
	$(DOCKER_EXEC_COMMAND) sh -c 'while ! pg_isready; do sleep 1; done'
	cat scripts/install_extensions.sql | $(DOCKER_EXEC_COMMAND) psql -AtXq  --set ON_ERROR_STOP=1
	cat scripts/version_info.sql | $(DOCKER_EXEC_COMMAND) psql -AtXq > $(VAR_VERSION_INFO)
	docker stop $(DOCKER_TAG_PREPARE) || true
	if [ ! -z "$(TIMESCALE_TSDB_ADMIN)" -a "$(POSTFIX)" != "-oss" ]; then echo "tsdb_admin=$(TIMESCALE_TSDB_ADMIN)" >> $(VAR_VERSION_INFO); fi

# RENAME TO build
build_ok: $(VAR_VERSION_INFO)
	echo "FROM $(DOCKER_TAG_PREPARE)" | docker build --tag "$(DOCKER_TAG_LABELED)" - \
	  $$(awk -F '=' '{printf "--label com.timescaledb.image."$$1".version="$$2" "}' $(VAR_VERSION_INFO)) \
	  --label com.timescaledb.image.install_method=$(INSTALL_METHOD)

# REMOVE THIS TARGET
build: prepare
	touch $(VAR_VERSION_INFO)
	echo "FROM $(DOCKER_TAG_PREPARE)" | docker build --tag "$(DOCKER_TAG_LABELED)" - \
	  $$(awk -F '=' '{printf "--label com.timescaledb.image."$$1".version="$$2" "}' $(VAR_VERSION_INFO)) \
	  --label com.timescaledb.image.install_method=$(INSTALL_METHOD)

# The purpose of publishing the images under many tags, is to provide
# some choice to the user as to their appetite for volatility.
#
#  1. timescaledev/timescaledb-ha:pg12-latest
#  2. timescaledev/timescaledb-ha:pg12-ts1.7-latest
#  3. timescaledev/timescaledb-ha:pg12.3-ts1.7-latest
#  4. timescaledev/timescaledb-ha:pg12.3-ts1.7.1-latest
#  5. timescaledev/timescaledb-ha:pg12.3-ts1.7.1-pN
#
# Tag 5 is immutable, and for every time we publish that image, we increase N by 1,
# we start with N=0
# Our method of finding a patch version is quite brute force (`docker pull image`), 
# however, we should not be publishing that often, so we take the hit for now.
publish: publish-mutable publish-immutable

publish-mutable: build
	if [ "$${CI}" != "true" ]; then echo "CI is not true, are you running this in Github Actions?"; exit 1; fi
	for latest in pg$(PG_MAJOR) pg$(PG_MAJOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMINOR); do \
		docker tag $(DOCKER_TAG_LABELED) $(DOCKER_PUBLISH_URL):$${latest}$(DOCKER_TAG_POSTFIX)-latest || exit 1; \
		docker push $(DOCKER_PUBLISH_URL):$${latest}$(DOCKER_TAG_POSTFIX)-latest || exit 1 ; \
	done

publish-immutable: build
	if [ "$${CI}" != "true" ]; then echo "CI is not true, are you running this in Github Actions?"; exit 1; fi
	for i in $$(seq 0 100); do \
		export IMMUTABLE_TAG=pg$(VAR_PGMINOR)-ts$(VAR_TSMINOR)$(DOCKER_TAG_POSTFIX)-p$${i}; \
		export DOCKER_HUB_HTTP_CODE="$$(curl -s -o /dev/null -w '%{http_code}' "$(DOCKER_CANONICAL_URL)/tags/$${IMMUTABLE_TAG}")"; \
		if [ "$${DOCKER_HUB_HTTP_CODE}" = "404" ]; then \
			docker tag $(DOCKER_TAG_LABELED) $(DOCKER_PUBLISH_URL):$${IMMUTABLE_TAG} || exit 1; \
			docker push $(DOCKER_PUBLISH_URL):$${IMMUTABLE_TAG} && exit 0 || exit 1 ; \
		elif [ "$${DOCKER_HUB_HTTP_CODE}" = "200" ]; then \
			echo "$${IMMUTABLE_TAG} already exists, incrementing patch number"; \
		else \
			echo "Unexpected HTTP return code: $${DOCKER_HUB_HTTP_CODE}"; \
			exit 1 ;\
		fi \
	done

build-tag: DOCKER_EXTRA_BUILDARGS = --build-arg GITHUB_REPO=$(GITHUB_REPO) --build-arg GITHUB_USER=$(GITHUB_USER) --build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) --build-arg GITHUB_TAG=$(GITHUB_TAG)
build-tag: DOCKER_TAG_POSTFIX?=$(GITHUB_TAG)
build-tag: build

push-sha:
ifndef GITHUB_SHA
	$(error GITHUB_SHA is undefined, are you running this in Github Actions?)
endif
	export FULL_TAG=$(DOCKER_PUBLISH_URL):cicd-$$(printf "%.8s" $${GITHUB_SHA}) \
	&& docker tag $(DOCKER_TAG_LABELED) $${FULL_TAG} \
	&& docker push $${FULL_TAG}

.PHONY: fast prepare build release build publish test tag build-tag publish-mutable publish-immutable
