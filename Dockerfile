## The purpose of this Dockerfile is to build an image that contains:
## - timescale from (internal) sources
## - many PostgreSQL extensions
## - patroni for High Availability
## - spilo to allow the github.com/zalando/postgres-operator to be compatible
## - pgBackRest to allow good backups

## We have many base images to choose from, (alpine, bitnami) but as we're adding a lot
## of tools to the image anyway, the end result is that we would only
## reduce the final Docker image by single digit MB's, which is insignificant
## in relation to the total image size.
## By choosing a very basic base image, we do keep full control over every part
## of the build steps. This Dockerfile contains every piece of magic we want.

## To allow us to use specific glibc 2.33+ features, we need to find a way
## to run glibc 2.33. Running multiple glibc versions inside the same
## container is something we'd like to avoid, we've seen multiple glibc
## related bugs in our lifetime, adding multiple glibc versions in the mix
## would make debugging harder.

## Debian (and rust:debian) has served us well in the past, however even Debian's
## latest release (bullseye, August 2021) cannot give us glibc 2.33.
## Ubuntu however does give us glibc 2.33 - as Ubuntu is based upon Debian
## the changes required are not that big for this Docker Image. Most of the
## tools we use will be the same across the board, as most of our tools our
## installed using external repositories.
ARG DOCKER_FROM=ubuntu:22.04
FROM ${DOCKER_FROM} AS builder

# By including multiple versions of PostgreSQL we can use the same Docker image,
# regardless of the major PostgreSQL Version. It also allow us to support (eventually)
# pg_upgrade from one major version to another,
# so we need all the postgres & timescale libraries for all versions
ARG PG_VERSIONS="15 14 13"
ARG PG_MAJOR=15

ENV DEBIAN_FRONTEND=noninteractive

# We need full control over the running user, including the UID, therefore we
# create the postgres user as the first thing on our list
RUN adduser --home /home/postgres --uid 1000 --disabled-password --gecos "" postgres

RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/01norecommend
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/01norecommend

# Make sure we're as up-to-date as possible, and install the highlest level dependencies
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y ca-certificates curl gnupg1 gpg gpg-agent locales lsb-release wget unzip

RUN mkdir -p /build/scripts
RUN chmod 777 /build
WORKDIR /build/

RUN curl -Ls https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --output /usr/share/keyrings/postgresql.keyring
RUN for t in deb deb-src; do \
        echo "$t [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql.keyring] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -s -c)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list; \
    done

# timescaledb-tune, as well as timescaledb-parallel-copy
RUN curl -Ls https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor --output /usr/share/keyrings/timescaledb.keyring
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/timescaledb.keyring] https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/timescaledb.list

# The following tools are required for some of the processes we (TimescaleDB) regularly
# run inside the containers that use this Docker Image
# awscli is useful in many situations, for example, to list backup buckets etc
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y \
        less jq strace procps awscli vim-tiny gdb gdbserver dumb-init daemontools \
        postgresql-common pgbouncer pgbackrest lz4 libpq-dev libpq5 pgtop

# forbid creation of a main cluster when package is installed
RUN sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf

# The next 2 instructions (ENV + RUN) are directly copied from https://github.com/rust-lang/docker-rust/blob/d534735bae832da4c60ddf799a8dfbefa9939020/1.67.0/bullseye/Dockerfile
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH \
    RUST_VERSION=1.65.0

RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
        amd64) rustArch='x86_64-unknown-linux-gnu'; rustupSha256='bb31eaf643926b2ee9f4d8d6fc0e2835e03c0a60f34d324048aa194f0b29a71c' ;; \
        armhf) rustArch='armv7-unknown-linux-gnueabihf'; rustupSha256='6626b90205d7fe7058754c8e993b7efd91dedc6833a11a225b296b7c2941194f' ;; \
        arm64) rustArch='aarch64-unknown-linux-gnu'; rustupSha256='4ccaa7de6b8be1569f6b764acc28e84f5eca342f5162cd5c810891bff7ed7f74' ;; \
        i386) rustArch='i686-unknown-linux-gnu'; rustupSha256='34392b53a25c56435b411d3e575b63aab962034dd1409ba405e708610c829607' ;; \
        *) echo >&2 "unsupported architecture: ${dpkgArch}"; exit 1 ;; \
    esac; \
    url="https://static.rust-lang.org/rustup/archive/1.25.2/${rustArch}/rustup-init"; \
    wget "$url"; \
    echo "${rustupSha256} *rustup-init" | sha256sum -c -; \
    chmod +x rustup-init; \
    ./rustup-init -y --no-modify-path --profile minimal --default-toolchain $RUST_VERSION --default-host ${rustArch}; \
    rm rustup-init; \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME; \
    rustup --version; \
    cargo --version; \
    rustc --version;

# Setup locales, and make sure we have a en_US.UTF-8 locale available
RUN set -eux; \
    find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete; \
    find /usr/share/i18n/locales/ -type f ! -name en_US ! -name en_GB ! -name i18n* ! -name iso14651_t1 ! -name iso14651_t1_common ! -name 'translit_*' -delete; \
    echo 'en_US.UTF-8 UTF-8' > /usr/share/i18n/SUPPORTED; \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

# We install some build dependencies and mark the installed packages as auto-installed,
# this will cause the cleanup to get rid of all of these packages
ENV BUILD_PACKAGES="binutils cmake devscripts equivs gcc git gpg gpg-agent libc-dev libc6-dev libkrb5-dev libperl-dev libssl-dev lsb-release make patchutils python2-dev python3-dev wget"
RUN apt-get install -y ${BUILD_PACKAGES}
RUN apt-mark auto ${BUILD_PACKAGES}

# We install the PostgreSQL build dependencies and mark the installed packages as auto-installed,
RUN set -eux; \
    for pg in ${PG_VERSIONS}; do \
        mk-build-deps postgresql-${pg} && apt-get install -y ./postgresql-${pg}-build-deps*.deb && apt-mark auto postgresql-${pg}-build-deps || exit 1; \
    done

RUN set -eux; \
    packages=""; \
    for pg in ${PG_VERSIONS}; do \
        packages="$packages postgresql-${pg} postgresql-server-dev-${pg} postgresql-${pg}-dbgsym \
            postgresql-plpython3-${pg} postgresql-plperl-${pg} postgresql-${pg}-pgextwlist postgresql-${pg}-hll \
            postgresql-${pg}-pgrouting postgresql-${pg}-repack postgresql-${pg}-hypopg postgresql-${pg}-unit \
            postgresql-${pg}-pg-stat-kcache postgresql-${pg}-cron postgresql-${pg}-pldebugger \
            postgresql-${pg}-pglogical postgresql-${pg}-wal2json"; \
    done; \
    apt-get install -y $packages

ARG POSTGIS_VERSIONS="3"
RUN set -eux; \
    for postgisv in ${POSTGIS_VERSIONS}; do \
        for pg in ${PG_VERSIONS}; do \
            apt-get install -y postgresql-${pg}-postgis-${postgisv}; \
        done; \
    done

# Some Patroni prerequisites
# This need to be done after the PostgreSQL packages have been installed,
# to ensure we have the preferred libpq installations etc.
RUN apt-get install -y python3-etcd python3-requests python3-pystache python3-kubernetes python3-pysyncobj patroni

RUN apt-get install -y timescaledb-tools

## Entrypoints as they are from the Timescale image and its default alpine upstream repositories.
## This ensures the default interface (entrypoint) equals the one of the github.com/timescale/timescaledb-docker one,
## which allows this Docker Image to be a drop-in replacement for those Docker Images.
ARG GITHUB_TIMESCALEDB_DOCKER_REF=main
ARG GITHUB_DOCKERLIB_POSTGRES_REF=master

RUN set -ex; \
    cd /build; \
    git clone https://github.com/timescale/timescaledb-docker; \
    cd timescaledb-docker; \
    git checkout ${GITHUB_TIMESCALEDB_DOCKER_REF}; \
    cp -a docker-entrypoint-initdb.d /docker-entrypoint-initdb.d/

# Add custom entrypoint to install timescaledb_toolkit
COPY scripts/010_install_timescaledb_toolkit.sh /docker-entrypoint-initdb.d/

RUN set -ex; \
    curl -s -o /usr/local/bin/docker-entrypoint.sh https://raw.githubusercontent.com/docker-library/postgres/${GITHUB_DOCKERLIB_POSTGRES_REF}/14/alpine/docker-entrypoint.sh; \
    chmod +x /usr/local/bin/docker-entrypoint.sh; \
    ln -s /usr/bin/timescaledb-tune /usr/local/bin/timescaledb-tune; \
    ln -s /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh

# The following allows *new* files to be created, so that extensions can be added to a running container.
# Existing files are still owned by root and have their sticky bit (the 1 in the 1775 permission mode) set,
# and therefore cannot be overwritten or removed by the unprivileged (postgres) user.
# This ensures the following:
# - libraries and supporting files that have been installed *before this step* are immutable
# - libraries and supporting files that have been installed *after this step* are mutable
# - files owned by postgres can be overwritten in a running container
# - new files can be added to the directories mentioned here
RUN set -ex; \
    for pg in ${PG_VERSIONS}; do \
        for dir in /usr/share/doc "$(/usr/lib/postgresql/${pg}/bin/pg_config --sharedir)/extension" "$(/usr/lib/postgresql/${pg}/bin/pg_config --pkglibdir)" "$(/usr/lib/postgresql/${pg}/bin/pg_config --bindir)"; do \
            install --directory "${dir}" --group postgres --mode 1775; \
            find "${dir}" -type d -exec install --directory {} --group postgres --mode 1775 \;; \
        done; \
    done

RUN for file in $(find /usr/share/postgresql -name 'postgresql.conf.sample'); do \
        # We want timescaledb to be loaded in this image by every created cluster
        sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" $file \
        # We need to listen on all interfaces, otherwise PostgreSQL is not accessible
        && echo "listen_addresses = '*'" >> $file; \
    done

RUN chown -R postgres:postgres /usr/local/cargo

USER postgres

ENV MAKEFLAGS=-j4

# pg_stat_monitor is a Query Performance Monitoring tool for PostgreSQL
# https://github.com/percona/pg_stat_monitor
ARG PG_STAT_MONITOR
RUN set -ex; \
    if [ -n "${PG_STAT_MONITOR}" ]; then \
        git clone https://github.com/percona/pg_stat_monitor /build/pg_stat_monitor; \
        cd /build/pg_stat_monitor; \
        git checkout "${PG_STAT_MONITOR}"; \
        for pg in ${PG_VERSIONS}; do \
            git reset HEAD --hard; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make USE_PGXS=1 all; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make USE_PGXS=1 install; \
        done; \
    fi

# pg_auth_mon is an extension to monitor authentication attempts
# It is also useful to determine whether the DB is actively used
# https://github.com/RafiaSabih/pg_auth_mon
ARG PG_AUTH_MON
RUN set -ex; \
    if [ -n "${PG_AUTH_MON}" ]; then \
        git clone https://github.com/RafiaSabih/pg_auth_mon /build/pg_auth_mon; \
        cd /build/pg_auth_mon; \
        git checkout "${PG_AUTH_MON}"; \
        for pg in ${PG_VERSIONS}; do \
            git reset HEAD --hard; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make clean; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make install; \
        done; \
    fi

# logerrors is an extension to count the number of errors logged by postgrs, grouped by the error codes
# https://github.com/munakoiso/logerrors
ARG PG_LOGERRORS
RUN set -ex; \
    if [ -n "${PG_LOGERRORS}" ]; then \
        git clone https://github.com/munakoiso/logerrors /build/logerrors; \
        cd /build/logerrors; \
        git checkout "${PG_LOGERRORS}"; \
        for pg in ${PG_VERSIONS}; do \
            git reset HEAD --hard; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make clean; \
            PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make install; \
        done; \
    fi

COPY --chown postgres:postgres build_scripts/* /build/scripts/

# INSTALL_METHOD will show up in the telemetry, which makes it easier to identify these installations
ARG INSTALL_METHOD=docker-ha
ARG OSS_ONLY

# RUST_RELEASE for some packages passes this to --profile, but for promscale, if anything is set that means use
# release mode, and if it's empty, then debug mode.
ARG RUST_RELEASE=release

# TimescaleDB:
ARG TIMESCALEDB_VERSIONS
ARG GITHUB_REPO=timescale/timescaledb
RUN set -eux; \
    git clone "https://github.com/${GITHUB_REPO}" /build/timescaledb; \
    cd /build/timescaledb; \
    for pg in ${PG_VERSIONS}; do \
        OSS_ONLY="${OSS_ONLY}" /build/scripts/install_timescaledb ${pg} ${TIMESCALEDB_VERSIONS}; \
    done; \
    if [ "${OSS_ONLY}" = true ]; then \
        rm -f /usr/lib/postgresql/*/lib/timescaledb-tsl-*; \
    fi

ARG TIMESCALE_PROMSCALE_EXTENSIONS
ARG TIMESCALEDB_TOOLKIT_EXTENSIONS
RUN set -ex; \
    if [ "${OSS_ONLY}" != true ]; then \
        RUST_RELEASE="${RUST_RELEASE}" \
            PROMSCALE_VERSIONS="${TIMESCALE_PROMSCALE_EXTENSIONS}" \
            TOOLKIT_VERSIONS="${TIMESCALEDB_TOOLKIT_EXTENSIONS}" \
            /build/scripts/install_extensions; \
    fi

USER root

# All the tools that were built in the previous steps have their ownership set to postgres
# to allow mutability. To allow one to build this image with the default privileges (owned by root)
# one can set the ALLOW_ADDING_EXTENSIONS argument to anything but "true".
ARG ALLOW_ADDING_EXTENSIONS=true
RUN set -eux; \
    if [ "${ALLOW_ADDING_EXTENSIONS}" != "true" ]; then \
        for pg in ${PG_VERSIONS}; do \
            for dir in /usr/share/doc "$(/usr/lib/postgresql/${pg}/bin/pg_config --sharedir)/extension" "$(/usr/lib/postgresql/${pg}/bin/pg_config --pkglibdir)" "$(/usr/lib/postgresql/${pg}/bin/pg_config --bindir)"; do \
                chown -R root:root "{dir}"; \
            done; \
        done; \
    fi

RUN set -eu; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_??; \
    find /var/log -type f -exec truncate --size 0 {} \;

ARG PG_MAJOR
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
    PAGER=""

## The Zalando postgres-operator has strong opinions about the HOME directory of postgres,
## whereas we do not. Make the operator happy then
RUN usermod postgres --home "${PGROOT}" --move-home

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
RUN set -ex; \
    chown -R postgres:postgres "${PGLOG}" "${PGROOT}" "${PGDATA}" /var/run/postgresql/; \
    chown -R postgres:postgres /var/log/pgbackrest/ /var/lib/pgbackrest /var/spool/pgbackrest; \
    chmod -x /usr/lib/postgresql/*/lib/*.so

RUN echo "TIMESCALEDB_VERSIONS=\"${TIMESCALEDB_VERSIONS}\"" > /.image_config; \
    echo "OSS_ONLY=\"$OSS_ONLY\"" >> /.image_config; \
    echo "PROMSCALE_VERSIONS=\"${TIMESCALE_PROMSCALE_EXTENSIONS}\"" >> /.image_config; \
    echo "TOOLKIT_VERSIONS=\"${TIMESCALEDB_TOOLKIT_EXTENSIONS}\"" >> /.image_config; \
    echo "PG_LOGERRORS=\"${PG_LOGERRORS}\"" >> /.image_config; \
    echo "PG_STAT_MONITOR=\"${PG_STAT_MONITOR}\"" >> /.image_config; \
    echo "POSTGIS_VERSIONS=\"${POSTGIS_VERSIONS}\"" >> /.image_config; \
    echo "PG_AUTH_MON=\"${PG_AUTH_MON}\"" >> /.image_config; \
    echo "PG_MAJOR=\"${PG_MAJOR}\"" >> /.image_config; \
    echo "PG_VERSIONS=\"${PG_VERSIONS}\"" >> /.image_config; \
    echo "FROM=\"${DOCKER_FROM}\"" >> /.image_config; \
    echo "BUILD_DATE=\"$(date -Iseconds)\"" >> /.image_config

WORKDIR /home/postgres
EXPOSE 5432 8008 8081
USER postgres


FROM builder as trimmed

USER root

ENV BUILD_PACKAGES="binutils cmake devscripts equivs gcc git gpg gpg-agent libc-dev libc6-dev libkrb5-dev libperl-dev libssl-dev lsb-release make patchutils python2-dev python3-dev wget"

RUN set -ex; \
    apt-get purge -y ${BUILD_PACKAGES}; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_?? \
            /home/postgres/.pgx \
            /build/ \
            /usr/local/rustup \
            /usr/local/cargo; \
    find /var/log -type f -exec truncate --size 0 {} \;

USER postgres


## Create a smaller Docker image from the builder image
FROM scratch as release
COPY --from=trimmed / /

ARG PG_MAJOR

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
    PAGER=""

WORKDIR /home/postgres
EXPOSE 5432 8008 8081
USER postgres

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["postgres"]
