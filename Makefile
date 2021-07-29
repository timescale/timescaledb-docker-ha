PG_MAJOR?=12
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=12

# Additional PostgreSQL extensions we want to include with specific version/commit tags
POSTGIS_VERSIONS?="2.5 3"
PG_AUTH_MON?=v1.0
PG_LOGERRORS?=3c55887b
TIMESCALE_PROMSCALE_EXTENSION?=0.2.0
TIMESCALEDB_TOOLKIT_EXTENSION?=forge-stable-1.1.0
TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS?=forge-stable-0.3.0 forge-stable-1.0.0
TIMESCALE_TSDB_ADMIN?=
TIMESCALE_HOT_FORGE?=

DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescale/timescaledb-ha
DOCKER_PUBLISH_URLS?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)
DOCKER_TAG_POSTFIX?=
DOCKER_TAG_PREPARE=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_TAG_LABELED=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-labeled

# These parameters control which entrypoints we add to the scripts
GITHUB_DOCKERLIB_POSTGRES_REF=master
GITHUB_TIMESCALEDB_DOCKER_REF=master

ALLOW_ADDING_EXTENSIONS?=true

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
VAR_PGMINOR="$$(awk -F '=' '/postgresql.version=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMINOR="$$(awk -F '=' '/timescaledb.version=/ {print $$2}' $(VAR_VERSION_INFO))"
VAR_TSMAJOR="$$(awk -F '[.=]' '/timescaledb.version=/ {print $$3 "." $$4}' $(VAR_VERSION_INFO))"
VAR_VERSION_INFO=version_info-$(PG_MAJOR)$(DOCKER_TAG_POSTFIX).log

# We label all the Docker Images with the versions of PostgreSQL, TimescaleDB and some other extensions
# afterwards, by using introspection, as minor versions may differ even when using the same
# Dockerfile
DOCKER_BUILD_COMMAND=docker build  \
					 --build-arg ALLOW_ADDING_EXTENSIONS="$(ALLOW_ADDING_EXTENSIONS)" \
					 --build-arg DEBIAN_REPO_MIRROR=$(DEBIAN_REPO_MIRROR) \
					 --build-arg GITHUB_DOCKERLIB_POSTGRES_REF="$(GITHUB_DOCKERLIB_POSTGRES_REF)" \
					 --build-arg GITHUB_TIMESCALEDB_DOCKER_REF="$(GITHUB_TIMESCALEDB_DOCKER_REF)" \
					 --build-arg INSTALL_METHOD="$(INSTALL_METHOD)" \
					 --build-arg PG_AUTH_MON="$(PG_AUTH_MON)" \
					 --build-arg PG_LOGERRORS="$(PG_LOGERRORS)" \
					 --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_VERSIONS="$(PG_VERSIONS)" \
					 --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) \
					 --build-arg PRIVATE_REPO_TOKEN="$(PRIVATE_REPO_TOKEN)" \
					 --build-arg TIMESCALEDB_TOOLKIT_EXTENSION="$(TIMESCALEDB_TOOLKIT_EXTENSION)" \
					 --build-arg TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS="$(TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS)" \
					 --build-arg TIMESCALE_HOT_FORGE="$(TIMESCALE_HOT_FORGE)" \
					 --build-arg TIMESCALE_PROMSCALE_EXTENSION="$(TIMESCALE_PROMSCALE_EXTENSION)" \
					 --build-arg TIMESCALE_TSDB_ADMIN="$(TIMESCALE_TSDB_ADMIN)" \
					 --label org.opencontainers.image.created="$$(date -Iseconds --utc)" \
					 --label org.opencontainers.image.revision="$(GIT_REV)" \
					 --label org.opencontainers.image.source="$(GIT_REMOTE)" \
					 --label org.opencontainers.image.vendor=Timescale \
					 --label com.timescaledb.image.install_method=$(INSTALL_METHOD) \
					 $(DOCKER_EXTRA_BUILDARGS) \
					 .

DOCKER_EXEC_COMMAND=docker exec -i $(DOCKER_TAG_PREPARE) timeout 60

# We provide the fast target as the first (=default) target, as it will skip installing
# many optional extensions, and it will only install a single timescaledb (master) version.
# This is basically useful for developers of this repository, to allow fast feedback cycles.
fast: DOCKER_EXTRA_BUILDARGS= --build-arg GITHUB_TAG=master
fast: PG_AUTH_MON=
fast: PG_LOGERRORS=
fast: PG_VERSIONS=12
fast: POSTGIS_VERSIONS=
fast: TIMESCALEDB_TOOLKIT_EXTENSION=
fast: TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS=
fast: TIMESCALE_PROMSCALE_EXTENSION=
fast: ALLOW_ADDING_EXTENSIONS=true
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
	if [ ! -z "$(TIMESCALE_TSDB_ADMIN)" -a "$(POSTFIX)" != "-oss" ]; then echo "tsdb_admin.version=$(TIMESCALE_TSDB_ADMIN)" >> $(VAR_VERSION_INFO); fi

build: $(VAR_VERSION_INFO)
	echo "FROM $(DOCKER_TAG_PREPARE)" | docker build --tag "$(DOCKER_TAG_LABELED)" - \
	  $$(awk -F '=' '{printf "--label com.timescaledb.image."$$1"="$$2" "}' $(VAR_VERSION_INFO))


# The purpose of publishing the images under many tags, is to provide
# some choice to the user as to their appetite for volatility.
#
#  1. timescale/timescaledb-ha:pg12-latest
#  2. timescale/timescaledb-ha:pg12-ts1.7-latest
#  3. timescale/timescaledb-ha:pg12.3-ts1.7-latest
#  4. timescale/timescaledb-ha:pg12.3-ts1.7.1-latest
#  5. timescale/timescaledb-ha:pg12.3-ts1.7.1-pN
#
# Tag 5 is immutable, and for every time we publish that image, we increase N by 1,
# we start with N=0
publish: publish-mutable publish-next-patch-version

is_ci:
	@if [ "$${CI}" != "true" ]; then echo "environment variable CI is not set to \"true\", are you running this in Github Actions?"; exit 1; fi

publish-mutable: is_ci build
	for latest in pg$(PG_MAJOR) pg$(PG_MAJOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMAJOR) pg$(VAR_PGMINOR)-ts$(VAR_TSMINOR); do \
		for url in $(DOCKER_PUBLISH_URLS); do \
			docker tag $(DOCKER_TAG_LABELED) $${url}:$${latest}$(DOCKER_TAG_POSTFIX)-latest || exit 1; \
			docker push $${url}:$${latest}$(DOCKER_TAG_POSTFIX)-latest || exit 1 ; \
		done \
	done


publish-immutable: MAX_PATCH_NUMBER=100
publish-immutable: is_ci build
	for i in $$(seq 0 $(MAX_PATCH_NUMBER)); do \
		export IMMUTABLE_TAG=pg$(VAR_PGMINOR)-ts$(VAR_TSMINOR)$(DOCKER_TAG_POSTFIX)-p$${i}; \
		export DOCKER_HUB_HTTP_CODE="$$(curl -s -o /dev/null -w '%{http_code}' "$(DOCKER_CANONICAL_URL)/tags/$${IMMUTABLE_TAG}")"; \
		if [ $$i -ge $(MAX_PATCH_NUMBER) ]; then \
			echo "There are already $$i patch versions, aborting"; \
			exit 1 ; \
		elif [ "$${DOCKER_HUB_HTTP_CODE}" = "404" ]; then \
			for url in $(DOCKER_PUBLISH_URLS); do \
				docker tag $(DOCKER_TAG_LABELED) $${url}:$${IMMUTABLE_TAG} || exit 1; \
				docker push $${url}:$${IMMUTABLE_TAG} || exit 1 ; \
			done; \
			exit 0; \
		elif [ "$${DOCKER_HUB_HTTP_CODE}" = "200" ]; then \
			echo "$${IMMUTABLE_TAG} already exists, incrementing patch number"; \
		else \
			echo "Unexpected HTTP return code: $${DOCKER_HUB_HTTP_CODE}"; \
			exit 1 ;\
		fi \
	done

list-images:
	docker images --filter "label=org.opencontainers.image.revision=$(GIT_REV)" --filter "dangling=false" --filter "label=com.timescaledb.image.postgresql.version"

build-tag: DOCKER_EXTRA_BUILDARGS = --build-arg GITHUB_REPO=$(GITHUB_REPO) --build-arg GITHUB_USER=$(GITHUB_USER) --build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) --build-arg GITHUB_TAG=$(GITHUB_TAG)
build-tag: DOCKER_TAG_POSTFIX?=$(GITHUB_TAG)
build-tag: build

push-sha: is_ci build
ifndef GITHUB_SHA
	$(error GITHUB_SHA is undefined, are you running this in Github Actions?)
endif
	for url in $(DOCKER_PUBLISH_URLS); do \
		export FULL_TAG=$${url}:cicd-$$(printf "%.8s" $${GITHUB_SHA}) \
		&& docker tag $(DOCKER_TAG_LABELED) $${FULL_TAG} \
		&& docker push $${FULL_TAG} || exit 1 ; \
	done

.PHONY: fast prepare release build publish test tag build-tag publish-next-patch-version publish-mutable publish-immutable is_ci list-images
