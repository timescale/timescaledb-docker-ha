## The purpose of this Dockerfile is to build an image that contains:
## - timescale from (internal) sources
## - patroni for High Availability
## - spilo to allow the github.com/zalando/postgres-operator to be compatible
## - pgBackRest to allow good backups

## We have many base images to choose from, (alpine, bitnami) but as we're adding a lot
## of tools to the image anyway, the end result is that we would only
## reduce the final Docker image by single digit MB's, which is insignificant
## in relation to the total image size.
## By choosing a very basic base image, we do keep full control over every part
## of the build steps. This Dockerfile contains every piece of magic we want.
FROM debian:buster-slim AS builder

# We need full control over the running user, including the UID, therefore we
# create the postgres user as the first thing on our list
RUN adduser --home /home/postgres --uid 1000 --disabled-password --gecos "" postgres

# CI/CD may benefit a lot from using a specific package mirror
ARG DEBIAN_REPO_MIRROR=""
RUN echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend \
    && if [ "${DEBIAN_REPO_MIRROR}" != "" ]; then \
        sed -i "s{http://.*.debian.org{http://${DEBIAN_REPO_MIRROR}{g" /etc/apt/sources.list; \
    fi

# Install the highlest level dependencies, like the PostgreSQL repositories
RUN apt-get update \
    && apt-get install -y curl ca-certificates locales gnupg1 \
    && VERSION_CODENAME=$(awk -F '=' '/VERSION_CODENAME/ {print $2}' < /etc/os-release) \
    && for t in deb deb-src; do \
    echo "$t http://apt.postgresql.org/pub/repos/apt/ ${VERSION_CODENAME}-pgdg main" >> /etc/apt/sources.list.d/pgdg.list; \
    done \
    && curl -s -o - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Some tools that are not strictly required for running PostgreSQL, but have a tiny
# footprint and can be very valuable when troubleshooting a running container,
RUN apt-get update && apt-get install -y less jq strace procps
# These packages allow for a better integration for some containers, for example
# daemontools provides envdir, which is very convenient for passing backup
# environment variables around.
RUN apt-get update && apt-get install -y dumb-init daemontools

RUN apt-get update \
    && apt-get install -y postgresql-common pgbouncer pgbackrest lz4 libpq-dev libpq5 \
    # forbid creation of a main cluster when package is installed
    && sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf

# Setup locales
RUN find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete \
    && find /usr/share/i18n/locales/ -type f ! -name en_US ! -name en_GB ! -name i18n* ! -name iso14651_t1 ! -name iso14651_t1_common ! -name 'translit_*' -delete \
    && echo 'en_US.UTF-8 UTF-8' > /usr/share/i18n/SUPPORTED \
    ## Make sure we have a en_US.UTF-8 locale available
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

# Some Patroni prerequisites
RUN apt-get install -y python3-etcd python3-requests python3-pystache python3-kubernetes

# We install some build dependencies and mark the installed packages as auto-installed,
# this will cause the cleanup to get rid of all of these packages
ENV BUILD_PACKAGES="git binutils patchutils gcc libc-dev make cmake libssl-dev python2-dev python3-dev devscripts equivs libkrb5-dev"
RUN apt-get install -y ${BUILD_PACKAGES}
RUN apt-mark auto ${BUILD_PACKAGES}

# By including multiple versions of PostgreSQL we can use the same Docker image,
# regardless of the major PostgreSQL Version. It also allow us to support (eventually)
# pg_upgrade from 11 to 12, so we need all the postgres & timescale libraries for all versions
ARG PG_VERSIONS="12 11"

# We install the PostgreSQL build dependencies and mark the installed packages as auto-installed,
RUN for pg in ${PG_VERSIONS}; do \
        mk-build-deps postgresql-${pg} && apt-get install -y ./postgresql-${pg}-build-deps*.deb && apt-mark auto postgresql-${pg}-build-deps || exit 1; \
    done

RUN mkdir /build/
WORKDIR /build/

RUN for pg in ${PG_VERSIONS}; do \
        apt-get install -y postgresql-${pg} postgresql-${pg}-dbgsym postgresql-plpython3-${pg} postgresql-plperl-${pg} postgresql-server-dev-${pg} \
            postgresql-${pg}-pgextwlist postgresql-${pg}-hll postgresql-${pg}-pgrouting || exit 1; \
    done

# We put Postgis in first, so these layers can be reused
ARG POSTGIS_VERSIONS="2.5 3"
RUN for postgisv in ${POSTGIS_VERSIONS}; do \
        for pg in ${PG_VERSIONS}; do \
            apt-get install -y postgresql-${pg}-postgis-${postgisv} -o Dpkg::Options::="--force-overwrite" || exit 1; \
        done; \
    done

# Patroni and Spilo Dependencies
# This need to be done after the PostgreSQL packages have been installed,
# to ensure we have the preferred libpq installations etc.
RUN apt-get install -y patroni

RUN for file in $(find /usr/share/postgresql -name 'postgresql.conf.sample'); do \
        # We want timescaledb to be loaded in this image by every created cluster
        sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" $file \
        # We need to listen on all interfaces, otherwise PostgreSQL is not accessible
        && echo "listen_addresses = '*'" >> $file; \
    done

ARG OSS_ONLY
ARG GITHUB_USER
ARG GITHUB_TOKEN
ARG GITHUB_REPO=timescale/timescaledb
ARG GITHUB_TAG

RUN mkdir -p /build \
    && if [ "${GITHUB_TOKEN}" != "" ]; then \
            git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}" /build/timescaledb; \
       else \
            git clone "https://github.com/${GITHUB_REPO}" /build/timescaledb; \
       fi

# INSTALL_METHOD will show up in the telemetry, which makes it easier to identify these installations
ARG INSTALL_METHOD=docker-ha

# If a specific GITHUB_TAG is provided, we will build that tag only. Otherwise
# we build all the public (recent) releases
RUN TS_VERSIONS="1.6.0 1.6.1 1.7.0 1.7.1 1.7.2 1.7.3 2.0.0-rc3 2.0.0-rc4 2.0.0 1.7.4" \
    && if [ "${GITHUB_TAG}" != "" ]; then TS_VERSIONS="${GITHUB_TAG}"; fi \
    && cd /build/timescaledb && git pull \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        for ts in ${TS_VERSIONS}; do \
            if [ ${pg} -ge 12 ] && [ "$(expr substr ${ts} 1 3)" = "1.6" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && cd /build/timescaledb && git reset HEAD --hard && git checkout ${ts} \
            && rm -rf build \
            && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DCMAKE_BUILD_TYPE=RelWithDebInfo -DREGRESS_CHECKS=OFF -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}"${OSS_ONLY} \
            && cd build && make -j 6 install || exit 1; \
        done; \
    done \
    && cd / && rm -rf /build

# if PG_PROMETHEUS is set to an empty string, the pg_prometheus extension will not be added to the db
ARG PG_PROMETHEUS=
# add pg_prometheus to shared_preload_libraries also
RUN if [ ! -z "${PG_PROMETHEUS}" ]; then \
        for file in $(find /usr/share/postgresql -name 'postgresql.conf.sample'); do \
            # We want pg_prometheus to be loaded in this image by every created cluster
            sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'pg_prometheus,\2'/;s/,'/'/" $file || exit 1; \
        done; \
    fi
# build and install the pg_prometheus extension
RUN if [ ! -z "${PG_PROMETHEUS}" ]; then \
        mkdir -p /build \
        && git clone https://github.com/timescale/pg_prometheus.git /build/pg_prometheus \
        && set -e \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/pg_prometheus && git reset HEAD --hard && git checkout ${PG_PROMETHEUS} \
            && git clean -f -x \
            && PATH=/usr/lib/postgresql/${pg}/bin:${PATH} PG_VER=pg${pg} make install || exit 1; \
        done; \
    fi

ARG TIMESCALE_PROMETHEUS=
# DEPRECATED, to be removed from 2020-11 from this Docker Image
# build and install the pg_prometheus extension
RUN if [ ! -z "${TIMESCALE_PROMETHEUS}" ]; then \
        curl https://sh.rustup.rs -sSf | bash -s -- -y \
        && PATH="/root/.cargo/bin:${PATH}" \
        && mkdir -p /build \
        && git clone https://github.com/timescale/timescale-prometheus /build/timescale_prometheus \
        && set -e \
        && for pg in ${PG_VERSIONS}; do \
            if [ "${pg}" = "12" ]; then \
                cd /build/timescale_prometheus && git reset HEAD --hard && git checkout ${TIMESCALE_PROMETHEUS} \
                && git clean -f -x \
                && cd /build/timescale_prometheus/extension \
                && PATH=/usr/lib/postgresql/${pg}/bin:${PATH} PG_VER=pg${pg} make install || exit 1; \
            fi; \
        done; \
    fi

ARG TIMESCALE_PROMSCALE_EXTENSION=
# build and install the promscale_extension extension
RUN if [ ! -z "${TIMESCALE_PROMSCALE_EXTENSION}" ]; then \
        curl https://sh.rustup.rs -sSf | bash -s -- -y \
        && PATH="/root/.cargo/bin:${PATH}" \
        && mkdir -p /build \
        && git clone https://github.com/timescale/promscale_extension /build/promscale_extension \
        && set -e \
        && for pg in ${PG_VERSIONS}; do \
            if [ "${pg}" = "12" ]; then \
                cd /build/promscale_extension && git reset HEAD --hard && git checkout ${TIMESCALE_PROMSCALE_EXTENSION} \
                && git clean -f -x \
                && PATH=/usr/lib/postgresql/${pg}/bin:${PATH} PG_VER=pg${pg} make install || exit 1; \
            fi; \
        done; \
    fi

# Protected Roles is a library that restricts the CREATEROLE/CREATEDB privileges of non-superusers.
# It is a private timescale project and is therefore not included/built by default
ARG TIMESCALE_TSDB_ADMIN=
ARG CI_JOB_TOKEN=
RUN if [ ! -z "${CI_JOB_TOKEN}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_TSDB_ADMIN}" ]; then \
        cd /build \
        && git clone https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/timescale/protected_roles \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/protected_roles && git reset HEAD --hard && git checkout ${TIMESCALE_TSDB_ADMIN} \
            && make clean && PG_CONFIG=/usr/lib/postgresql/${pg}/bin/pg_config make install || exit 1 ; \
        done; \
    fi

## Cleanup
RUN apt-get remove -y ${BUILD_PACKAGES}
RUN apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_?? \
            /build/ \
            /root/.rustup \
            /root/.cargo \
    && find /var/log -type f -exec truncate --size 0 {} \;

## Create a smaller Docker image from the builder image
FROM scratch
COPY --from=builder / /

ARG PG_MAJOR=11

## Entrypoints as they are from the Timescale image
## We may want to reconsider this, for now this means we have the exact same interface
## for this Docker images as for our other Docker images
COPY --from=timescale/timescaledb:latest-pg11 /docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/
COPY --from=timescale/timescaledb:latest-pg11 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --from=timescale/timescaledb:latest-pg11 /usr/local/bin/timescaledb-tune /usr/local/bin/timescaledb-tune

# timescaledb-tune does not support PostgreSQL 12 yet, however the (global) pg_config shipped by Debian
# is PostgreSQL 12. Therefore we need to explicitly pass on the PostgreSQL version to timescaledb-tune
RUN sed -i "s/timescaledb-tune/timescaledb-tune --pg-version=11/g" /docker-entrypoint-initdb.d/*.sh

RUN ln -s /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["postgres"]

## TimescaleDB entrypoints and configuration scripts
## Within a k8s context, we expect the ENTRYPOINT/CMD to always be explicitly specified
COPY timescaledb_entrypoint.sh /
## Backwards compatibility, some older deployments use patroni_entrypoint.sh
RUN ln -s /timescaledb_entrypoint.sh /patroni_entrypoint.sh
COPY pgbackrest_entrypoint.sh /
## Some patroni callbacks are configured by default by the operator.
COPY scripts /scripts/

## The mount being used by the Zalando postgres-operator is /home/postgres/pgdata
## for Patroni to do it's work it will sometimes move an old/invalid data directory
## inside the parent directory; therefore we need a subdirectory inside the mount

ENV PGROOT=/home/postgres \
    PGDATA=/home/postgres/pgdata/data \
    PGLOG=/home/postgres/pg_log \
    PGSOCKET=/home/postgres/pgdata \
    BACKUPROOT=/home/postgres/pgdata/backup \
    PGBACKREST_CONFIG=/home/postgres/pgdata/backup/pgbackrest.conf \
    PGBACKREST_STANZA=poddb \
    PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:${PATH} \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    # When having an interactive psql session, it is useful if the PAGER is disable
    PAGER=""

## The Zalando postgres-operator has strong opinions about the HOME directory of postgres,
## whereas we do not. Make the operator happy then
RUN usermod postgres --home ${PGROOT} --move-home

## The /etc/supervisor/conf.d directory is a very Spilo (Zalando postgres-operator) oriented directory.
## However, to make things work the user postgres currently needs to have write access to this directory
## The /var/lib/postgresql/data is used as PGDATA by alpine/bitnami, which makes it useful to have it be owned by Postgres
RUN install -o postgres -g postgres -m 0750 -d "${PGROOT}" "${PGLOG}" "${PGDATA}" "${BACKUPROOT}" /etc/supervisor/conf.d /scripts /var/lib/postgresql

## Making sure that pgbackrest is pointing to the right file
RUN rm /etc/pgbackrest.conf && ln -s "${PGBACKREST_CONFIG}" /etc/pgbackrest.conf

## Some configurations allow daily csv files, with foreign data wrappers pointing to the files.
## to make this work nicely, they need to exist though
RUN for i in $(seq 0 7); do touch "${PGLOG}/postgresql-$i.log" "${PGLOG}/postgresql-$i.csv"; done

## Fix permissions
RUN chown postgres:postgres "${PGLOG}" "${PGROOT}" "${PGDATA}" /var/run/postgresql/ -R
RUN chown postgres:postgres /var/log/pgbackrest/ /var/lib/pgbackrest /var/spool/pgbackrest -R

WORKDIR /home/postgres
EXPOSE 5432 8008 8081
USER postgres
