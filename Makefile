PG_MAJOR?=14
# All PG_VERSIONS binaries/libraries will be included in the Dockerfile
# specifying multiple versions will allow things like pg_upgrade etc to work.
PG_VERSIONS?=14 13 12

# Additional PostgreSQL extensions we want to include with specific version/commit tags
POSTGIS_VERSIONS?="3"
PG_AUTH_MON?=v1.0
PG_STAT_MONITOR?=1.0.0-rc.1
PG_LOGERRORS?=3c55887b
TIMESCALE_PROMSCALE_EXTENSIONS?=0.3.2 0.5.0 0.5.1
TIMESCALE_PROMSCALE_REPO?=github.com/timescale/promscale_extension
TIMESCALEDB_TOOLKIT_EXTENSIONS?=forge-stable-1.3.1 1.5.1-cloud 1.6.0 1.7.0
TIMESCALEDB_TOOLKIT_REPO?=github.com/timescale/timescaledb-toolkit
TIMESCALE_TSDB_ADMIN?=
TIMESCALE_HOT_FORGE?=
TIMESCALE_OOM_GUARD?=
TIMESCALE_CLOUDUTILS?=
TIMESCALE_STATIC_PRIMARY?=

DOCKER_EXTRA_BUILDARGS?=
DOCKER_REGISTRY?=localhost:5000
DOCKER_REPOSITORY?=timescale/timescaledb-ha
DOCKER_PUBLISH_URLS?=$(DOCKER_REGISTRY)/$(DOCKER_REPOSITORY)
DOCKER_TAG_POSTFIX?=
DOCKER_TAG_PREPARE=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)
DOCKER_TAG_LABELED=$(PG_MAJOR)$(DOCKER_TAG_POSTFIX)-labeled
DOCKER_TAG_COMPILER=pg$(PG_MAJOR)-compiler
DOCKER_CACHE_FROM?=scratch

# These parameters control which entrypoints we add to the scripts
GITHUB_DOCKERLIB_POSTGRES_REF=master
GITHUB_TIMESCALEDB_DOCKER_REF=main

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
GITHUB_REPO?=timescale/timescaledb
GITHUB_TAG?=

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
DOCKER_BUILD_COMMAND=docker build --progress=plain \
					 --build-arg ALLOW_ADDING_EXTENSIONS="$(ALLOW_ADDING_EXTENSIONS)" \
					 --build-arg GITHUB_DOCKERLIB_POSTGRES_REF="$(GITHUB_DOCKERLIB_POSTGRES_REF)" \
					 --build-arg GITHUB_REPO="$(GITHUB_REPO)" \
					 --build-arg GITHUB_TAG=$(GITHUB_TAG) \
					 --build-arg GITHUB_TIMESCALEDB_DOCKER_REF="$(GITHUB_TIMESCALEDB_DOCKER_REF)" \
					 --build-arg INSTALL_METHOD="$(INSTALL_METHOD)" \
					 --build-arg PG_AUTH_MON="$(PG_AUTH_MON)" \
					 --build-arg PG_LOGERRORS="$(PG_LOGERRORS)" \
					 --build-arg PG_MAJOR=$(PG_MAJOR) \
					 --build-arg PG_STAT_MONITOR="$(PG_STAT_MONITOR)" \
					 --build-arg PG_VERSIONS="$(PG_VERSIONS)" \
					 --build-arg POSTGIS_VERSIONS=$(POSTGIS_VERSIONS) \
					 --build-arg TIMESCALE_CLOUDUTILS="$(TIMESCALE_CLOUDUTILS)" \
					 --build-arg TIMESCALE_HOT_FORGE="$(TIMESCALE_HOT_FORGE)" \
					 --build-arg TIMESCALE_OOM_GUARD="$(TIMESCALE_OOM_GUARD)" \
					 --build-arg TIMESCALE_PROMSCALE_EXTENSIONS="$(TIMESCALE_PROMSCALE_EXTENSIONS)" \
					 --build-arg TIMESCALE_PROMSCALE_REPO="$(TIMESCALE_PROMSCALE_REPO)" \
					 --build-arg TIMESCALE_TSDB_ADMIN="$(TIMESCALE_TSDB_ADMIN)" \
					 --build-arg TIMESCALEDB_TOOLKIT_EXTENSIONS="$(TIMESCALEDB_TOOLKIT_EXTENSIONS)" \
					 --build-arg TIMESCALEDB_TOOLKIT_REPO="$(TIMESCALEDB_TOOLKIT_REPO)" \
					 --build-arg TIMESCALE_STATIC_PRIMARY="$(TIMESCALE_STATIC_PRIMARY)" \
					 --cache-from "$(DOCKER_CACHE_FROM)" \
					 --label com.timescaledb.image.install_method=$(INSTALL_METHOD) \
					 --label org.opencontainers.image.created="$$(date -Iseconds --utc)" \
					 --label org.opencontainers.image.revision="$(GIT_REV)" \
					 --label org.opencontainers.image.source="$(GIT_REMOTE)" \
					 --label org.opencontainers.image.vendor=Timescale \
					 --secret id=private_repo_token,env=PRIVATE_REPO_TOKEN \
					 --secret id=AWS_ACCESS_KEY_ID,env=AWS_ACCESS_KEY_ID \
					 --secret id=AWS_SECRET_ACCESS_KEY,env=AWS_SECRET_ACCESS_KEY \
					 $(DOCKER_EXTRA_BUILDARGS) \
					 .

DOCKER_EXEC_COMMAND=docker exec -i $(DOCKER_TAG_PREPARE) timeout 90

# We provide the fast target as the first (=default) target, as it will skip installing
# many optional extensions, and it will only install a single timescaledb (master) version.
# This is basically useful for developers of this repository, to allow fast feedback cycles.
fast: DOCKER_EXTRA_BUILDARGS= --build-arg GITHUB_TAG=master
fast: PG_AUTH_MON=
fast: PG_LOGERRORS=
fast: PG_VERSIONS=14
fast: POSTGIS_VERSIONS=
fast: TIMESCALEDB_TOOLKIT_EXTENSIONS=
fast: TIMESCALE_PROMSCALE_EXTENSION=
fast: ALLOW_ADDING_EXTENSIONS=true
fast: prepare

.PHONY: compiler
compiler:
	$(DOCKER_BUILD_COMMAND) --target compiler --tag $(DOCKER_TAG_COMPILER)

.PHONY: publish-compiler
publish-compiler: compiler
	for url in $(DOCKER_PUBLISH_URLS); do \
		docker tag $(DOCKER_TAG_COMPILER) $(DOCKER_PUBLISH_URLS):$(DOCKER_TAG_COMPILER) || exit 1 ; \
		docker push $(DOCKER_PUBLISH_URLS):$(DOCKER_TAG_COMPILER) || exit 1 ; \
		PGMINOR=$$(docker run -ti $(DOCKER_TAG_COMPILER) psql --version | awk '{print $$3}') ;\
		docker tag $(DOCKER_TAG_COMPILER) $(DOCKER_PUBLISH_URLS):pg$${PGMINOR}-compiler || exit 1 ; \
		docker push $(DOCKER_PUBLISH_URLS):pg$${PGMINOR}-compiler || exit 1 ; \
	done

# This target always succeeds, as it is purely an speed optimization
.PHONY: pull-cached-image
pull-cached-image:
	@if [ "$(DOCKER_CACHE_FROM)" != "scratch" ]; then docker pull "$(DOCKER_CACHE_FROM)" || true ; fi

# The prepare step does not build the final image, as we need to use introspection
# to find out what versions of software are installed in this image
prepare: pull-cached-image
	$(DOCKER_BUILD_COMMAND) --tag $(DOCKER_TAG_PREPARE)

version_info-%.log: prepare
	# In these steps we do some introspection to find out some details of the versions
	# that are inside the Docker image. As we use the Ubuntu packages, we do not know until
	# after we have built the image, what patch version of PostgreSQL, or PostGIS is installed.
	#
	# We will then attach this information as OCI labels to the final Docker image
	docker rm -f $(DOCKER_TAG_PREPARE) || true
	docker run -d --name $(DOCKER_TAG_PREPARE) -e PGDATA=/tmp/pgdata --user=postgres $(DOCKER_TAG_PREPARE) sleep 90
	docker cp ./cicd $(DOCKER_TAG_PREPARE):/cicd/
	$(DOCKER_EXEC_COMMAND) /cicd/smoketest.sh || (docker logs $(DOCKER_TAG_PREPARE) && exit 1)
	docker cp $(DOCKER_TAG_PREPARE):/tmp/version_info.log $(VAR_VERSION_INFO)
	docker kill $(DOCKER_TAG_PREPARE) || true
	if [ ! -z "$(TIMESCALE_TSDB_ADMIN)" -a "$(POSTFIX)" != "-oss" ]; then echo "tsdb_admin.version=$(TIMESCALE_TSDB_ADMIN)" >> $(VAR_VERSION_INFO); fi

build: $(VAR_VERSION_INFO)
	echo "FROM $(DOCKER_TAG_PREPARE)" | docker build --tag "$(DOCKER_TAG_LABELED)" - \
	  $$(awk -F '=' '{printf "--label com.timescaledb.image."$$1"="$$2" "}' $(VAR_VERSION_INFO))

build-oss: DOCKER_EXTRA_BUILDARGS= --build-arg OSS_ONLY=" -DAPACHE_ONLY=1"
build-oss: DOCKER_TAG_POSTFIX=-oss
build-oss: build

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
	docker images --filter "label=com.timescaledb.image.install_method=$(INSTALL_METHOD)" --filter "dangling=false"

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

.PHONY: fast prepare build-oss release build publish test tag build-tag publish-next-patch-version publish-mutable publish-immutable is_ci list-images
