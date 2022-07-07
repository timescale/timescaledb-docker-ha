## The purpose of this Dockerfile is to build an image that contains:
## - timescale from (internal) sources
## - many PostgreSQL extensions
## - patroni for High Availability
## - spilo to allow the github.com/zalando/postgres-operator to be compatible
## - pgBackRest to allow good backups

# By including multiple versions of PostgreSQL we can use the same Docker image,
# regardless of the major PostgreSQL Version. It also allow us to support (eventually)
# pg_upgrade from one major version to another,
# so we need all the postgres & timescale libraries for all versions
ARG PG_VERSIONS="14 13"
ARG PG_MAJOR=13

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
FROM ubuntu:22.04 AS compiler

ENV DEBIAN_FRONTEND=noninteractive
# We need full control over the running user, including the UID, therefore we
# create the postgres user as the first thing on our list
RUN adduser --home /home/postgres --uid 1000 --disabled-password --gecos "" postgres

RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/01norecommend
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/01norecommend

# Make sure we're as up-to-date as possible, and install the highlest level dependencies
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y ca-certificates curl gnupg1 gpg gpg-agent locales lsb-release wget

RUN mkdir -p /build/scripts
RUN chmod 777 /build
WORKDIR /build/

RUN wget -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --output /usr/share/keyrings/postgresql.keyring
RUN for t in deb deb-src; do \
        echo "$t [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql.keyring] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -s -c)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list; \
    done

RUN apt-get clean
RUN apt-get update

# The following tools are required for some of the processes we (TimescaleDB) regularly
# run inside the containers that use this Docker Image
RUN apt-get install -y less jq strace procps

# For debugging it is very useful if the Docker Image contains gdb(server). Even though it is
# not expected to be running gdb in a live instance often, it simplifies getting backtraces from
# containers using this image
RUN apt-get install -y gdb gdbserver

# The next 2 instructions (ENV + RUN) are directly copied from https://github.com/rust-lang/docker-rust/blob/aa8bed3870cb14ecf49f127bae0a212adebc2384/1.60.0/buster/Dockerfile
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH \
    RUST_VERSION=1.60.0

RUN set -eux; \
    dpkgArch="$(dpkg --print-architecture)"; \
    case "${dpkgArch##*-}" in \
        amd64) rustArch='x86_64-unknown-linux-gnu'; rustupSha256='3dc5ef50861ee18657f9db2eeb7392f9c2a6c95c90ab41e45ab4ca71476b4338' ;; \
        armhf) rustArch='armv7-unknown-linux-gnueabihf'; rustupSha256='67777ac3bc17277102f2ed73fd5f14c51f4ca5963adadf7f174adf4ebc38747b' ;; \
        arm64) rustArch='aarch64-unknown-linux-gnu'; rustupSha256='32a1532f7cef072a667bac53f1a5542c99666c4071af0c9549795bbdb2069ec1' ;; \
        i386) rustArch='i686-unknown-linux-gnu'; rustupSha256='e50d1deb99048bc5782a0200aa33e4eea70747d49dffdc9d06812fd22a372515' ;; \
        *) echo >&2 "unsupported architecture: ${dpkgArch}"; exit 1 ;; \
    esac; \
    url="https://static.rust-lang.org/rustup/archive/1.24.3/${rustArch}/rustup-init"; \
    wget "$url"; \
    echo "${rustupSha256} *rustup-init" | sha256sum -c -; \
    chmod +x rustup-init; \
    ./rustup-init -y --no-modify-path --profile minimal --default-toolchain $RUST_VERSION --default-host ${rustArch}; \
    rm rustup-init; \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME; \
    rustup --version; \
    cargo --version; \
    rustc --version;

# These packages allow for a better integration for some containers, for example
# daemontools provides envdir, which is very convenient for passing backup
# environment variables around.
RUN apt-get update && apt-get install -y dumb-init daemontools

RUN apt-get update \
    && apt-get install -y postgresql-common pgbouncer pgbackrest lz4 libpq-dev libpq5 pgtop \
    # forbid creation of a main cluster when package is installed
    && sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf

# Setup locales
RUN find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete \
    && find /usr/share/i18n/locales/ -type f ! -name en_US ! -name en_GB ! -name i18n* ! -name iso14651_t1 ! -name iso14651_t1_common ! -name 'translit_*' -delete \
    && echo 'en_US.UTF-8 UTF-8' > /usr/share/i18n/SUPPORTED \
    ## Make sure we have a en_US.UTF-8 locale available
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

# We install some build dependencies and mark the installed packages as auto-installed,
# this will cause the cleanup to get rid of all of these packages
ENV BUILD_PACKAGES="binutils cmake devscripts equivs gcc git gpg gpg-agent libc-dev libc6-dev libkrb5-dev libperl-dev libssl-dev lsb-release make patchutils python2-dev python3-dev wget"
RUN apt-get install -y ${BUILD_PACKAGES}
RUN apt-mark auto ${BUILD_PACKAGES}

ARG PG_VERSIONS

# We install the PostgreSQL build dependencies and mark the installed packages as auto-installed,
RUN for pg in ${PG_VERSIONS}; do \
        mk-build-deps postgresql-${pg} && apt-get install -y ./postgresql-${pg}-build-deps*.deb && apt-mark auto postgresql-${pg}-build-deps || exit 1; \
    done

# For the compiler image, we want all the PostgreSQL versions to be installed,
# so tools that depend on `pg_config` or other parts to exist can be run
RUN for pg in ${PG_VERSIONS}; do apt-get install -y postgresql-${pg} postgresql-server-dev-${pg} || exit 1; done

FROM compiler as builder

RUN for pg in ${PG_VERSIONS}; do \
        apt-get install -y postgresql-${pg}-dbgsym postgresql-plpython3-${pg} postgresql-plperl-${pg} \
            postgresql-${pg}-pgextwlist postgresql-${pg}-hll postgresql-${pg}-pgrouting postgresql-${pg}-repack postgresql-${pg}-hypopg postgresql-${pg}-unit \
            postgresql-${pg}-pg-stat-kcache postgresql-${pg}-cron postgresql-${pg}-pldebugger || exit 1; \
    done

# We put Postgis in first, so these layers can be reused
ARG POSTGIS_VERSIONS="3"
RUN for postgisv in ${POSTGIS_VERSIONS}; do \
        for pg in ${PG_VERSIONS}; do \
            apt-get install -y postgresql-${pg}-postgis-${postgisv} || exit 1; \
        done; \
    done

# Some Patroni prerequisites
# This need to be done after the PostgreSQL packages have been installed,
# to ensure we have the preferred libpq installations etc.
RUN apt-get install -y python3-etcd python3-requests python3-pystache python3-kubernetes python3-pysyncobj
RUN echo 'deb http://cz.archive.ubuntu.com/ubuntu kinetic main universe' >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y patroni=2.1.4-\* && \
    head -n -1 /etc/apt/sources.list > /etc/apt/sources.list.tmp; mv /etc/apt/sources.list.tmp /etc/apt/sources.list; \
    apt-get update
# Patch Patroni code with changes from https://github.com/zalando/patroni/pull/2318.
# NOTE: This is a temporary solution until changes land upstream.
ARG TIMESCALE_STATIC_PRIMARY
RUN if [ "${TIMESCALE_STATIC_PRIMARY}" != "" ]; then \
    wget -qO- https://raw.githubusercontent.com/timescale/patroni/v2.2.0-beta.4/patroni/ha.py > /usr/lib/python3/dist-packages/patroni/ha.py && \
    wget -qO- https://raw.githubusercontent.com/timescale/patroni/v2.2.0-beta.4/patroni/config.py > /usr/lib/python3/dist-packages/patroni/config.py && \
    wget -qO- https://raw.githubusercontent.com/timescale/patroni/v2.2.0-beta.4/patroni/validator.py > /usr/lib/python3/dist-packages/patroni/validator.py; \
    fi

RUN for file in $(find /usr/share/postgresql -name 'postgresql.conf.sample'); do \
        # We want timescaledb to be loaded in this image by every created cluster
        sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" $file \
        # We need to listen on all interfaces, otherwise PostgreSQL is not accessible
        && echo "listen_addresses = '*'" >> $file; \
    done

ARG PG_VERSIONS

# timescaledb-tune, as well as timescaledb-parallel-copy
# TODO: Replace `focal` with `$(lsb_release -s -c)` once packages are available
# for Ubuntu 22.04
RUN wget -O - https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor --output /usr/share/keyrings/timescaledb.keyring
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/timescaledb.keyring] https://packagecloud.io/timescale/timescaledb/ubuntu/ focal main" > /etc/apt/sources.list.d/timescaledb.list

RUN apt-get update && apt-get install -y timescaledb-tools

## Entrypoints as they are from the Timescale image and its default alpine upstream repositories.
## This ensures the default interface (entrypoint) equals the one of the github.com/timescale/timescaledb-docker one,
## which allows this Docker Image to be a drop-in replacement for those Docker Images.
ARG GITHUB_TIMESCALEDB_DOCKER_REF=main
ARG GITHUB_DOCKERLIB_POSTGRES_REF=main
RUN cd /build && git clone https://github.com/timescale/timescaledb-docker && cd /build/timescaledb-docker && git checkout ${GITHUB_TIMESCALEDB_DOCKER_REF}
RUN cp -a /build/timescaledb-docker/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d/
# Add custom entrypoint to install timescaledb_toolkit
COPY scripts/010_install_timescaledb_toolkit.sh /docker-entrypoint-initdb.d/
RUN curl -s -o /usr/local/bin/docker-entrypoint.sh https://raw.githubusercontent.com/docker-library/postgres/${GITHUB_DOCKERLIB_POSTGRES_REF}/13/alpine/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
# Satisfy assumptions of the entrypoint scripts
RUN ln -s /usr/bin/timescaledb-tune /usr/local/bin/timescaledb-tune
RUN ln -s /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh

ENV REPO_SECRET_FILE=/run/secrets/private_repo_token

# hot-forge is a project that allows hot-patching of postgres containers
# It is currently a private timescale project and is therefore not included/built by default,
# and never included in the OSS image.
ARG TIMESCALE_HOT_FORGE=
RUN --mount=type=secret,uid=1000,id=private_repo_token \
    if [ -f "${REPO_SECRET_FILE}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_HOT_FORGE}" ]; then \
        GH_REPO="https://api.github.com/repos/timescale/hot-forge"; \
        ASSET_ID="$(curl -sL --header "Authorization: token $(cat "${REPO_SECRET_FILE}")" "${GH_REPO}/releases/tags/${TIMESCALE_HOT_FORGE}" | jq '.assets[0].id')"; \
        curl -sL --header "Authorization: token $(cat "${REPO_SECRET_FILE}")" \
                 --header 'Accept: application/octet-stream' \
                 "${GH_REPO}/releases/assets/${ASSET_ID}" > /usr/local/bin/hot-forge || exit 1; \
        chmod 0755 /usr/local/bin/hot-forge ; \
        hot-forge -V || exit 1 ; \
    fi

# OOM Guard is a library that enables us to mitigate OOMs by blocking allocations above a limit.
# It is a private timescale project and is therefore not included/built by default
ARG TIMESCALE_OOM_GUARD=
RUN --mount=type=secret,uid=1000,id=private_repo_token \
    if [ -f "${REPO_SECRET_FILE}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_OOM_GUARD}" ]; then \
        mkdir /usr/local/bin/oom-guard; \
        cd /build \
        && git clone https://github-actions:$(cat "${REPO_SECRET_FILE}")@github.com/timescale/oom_guard \
        && cd /build/oom_guard && git reset HEAD --hard && git checkout ${TIMESCALE_OOM_GUARD} \
        && make all || exit 1; \
       chmod 0755 -R /usr/local/bin/oom-guard ;\
    fi

# The following allows *new* files to be created, so that extensions can be added to a running container.
# Existing files are still owned by root and have their sticky bit (the 1 in the 1775 permission mode) set,
# and therefore cannot be overwritten or removed by the unprivileged (postgres) user.
# This ensures the following:
# - libraries and supporting files that have been installed *before this step* are immutable
# - libraries and supporting files that have been installed *after this step* are mutable
# - files owned by postgres can be overwritten in a running container
# - new files can be added to the directories mentioned here
RUN for pg in ${PG_VERSIONS}; do \
        for dir in "$(/usr/lib/postgresql/${pg}/bin/pg_config --sharedir)/extension" "$(/usr/lib/postgresql/${pg}/bin/pg_config --pkglibdir)" "$(/usr/lib/postgresql/${pg}/bin/pg_config --bindir)"; do \
            install --directory "${dir}" --group postgres --mode 1775 \
            && find "${dir}" -type d -exec install --directory {} --group postgres --mode 1775 \; || exit 1 ; \
        done; \
    done

USER postgres

ENV MAKEFLAGS=-j8

ARG GITHUB_REPO=timescale/timescaledb
RUN --mount=type=secret,uid=1000,id=private_repo_token \
    if [ -f "{REPO_SECRET_FILE}" ]; then \
        git clone "https://github-actions:$(cat "${REPO_SECRET_FILE}")@github.com/${GITHUB_REPO}" /build/timescaledb; \
    else \
        git clone "https://github.com/${GITHUB_REPO}" /build/timescaledb; \
    fi

# INSTALL_METHOD will show up in the telemetry, which makes it easier to identify these installations
ARG INSTALL_METHOD=docker-ha
ARG GITHUB_TAG
ARG OSS_ONLY

COPY build_scripts /build/scripts

# If a specific GITHUB_TAG is provided, we will build that tag only. Otherwise
# we build all the public (recent) releases
RUN TS_VERSIONS="1.7.5 2.1.0 2.1.1 2.2.0 2.2.1 2.3.0 2.3.1 2.4.0 2.4.1 2.4.2 2.5.0 2.5.1 2.5.2 2.6.0 2.6.1 2.7.0 2.7.1" \
    && if [ "${GITHUB_TAG}" != "" ]; then TS_VERSIONS="${GITHUB_TAG}"; fi \
    && cd /build/timescaledb && git pull \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        /build/scripts/install_timescaledb.sh ${pg} ${TS_VERSIONS} || exit 1 ; \
    done

RUN curl -L "https://github.com/mozilla/sccache/releases/download/v0.2.15/sccache-v0.2.15-x86_64-unknown-linux-musl.tar.gz" \
    | tar zxf -
RUN chmod +x sccache-*/sccache
RUN mkdir -p /build/bin
RUN mv sccache-*/sccache /build/bin/sccache
ENV RUSTC_WRAPPER=/build/bin/sccache
ENV SCCACHE_BUCKET=timescaledb-docker-ha-sccache

ARG TIMESCALE_PROMSCALE_EXTENSIONS=
ARG TIMESCALE_PROMSCALE_REPO=github.com/timescale/promscale_extension
# build and install the promscale_extension extension
RUN --mount=type=secret,uid=1000,id=AWS_ACCESS_KEY_ID --mount=type=secret,uid=1000,id=AWS_SECRET_ACCESS_KEY \
    if [ ! -z "${TIMESCALE_PROMSCALE_EXTENSIONS}" -a -z "${OSS_ONLY}" ]; then \
        [ -f "/run/secrets/AWS_ACCESS_KEY_ID" ] && export AWS_ACCESS_KEY_ID="$(cat /run/secrets/AWS_ACCESS_KEY_ID)" ; \
        [ -f "/run/secrets/AWS_SECRET_ACCESS_KEY" ] && export AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/AWS_SECRET_ACCESS_KEY)" ; \
        set -e \
        && git clone https://${TIMESCALE_PROMSCALE_REPO} /build/promscale_extension \
        && cd /build/promscale_extension \
        && for pg in ${PG_VERSIONS}; do \
            /build/scripts/install_promscale.sh ${pg} ${TIMESCALE_PROMSCALE_EXTENSIONS} || exit 1 ; \
        done; \
    fi

# Make sure to override this when upgrading to new PGX version
ARG PGX_VERSION=0.2.6
ARG TIMESCALE_CLOUDUTILS=
# build and install the cloudutils libarary and extension
RUN --mount=type=secret,uid=1000,id=private_repo_token --mount=type=secret,uid=1000,id=AWS_ACCESS_KEY_ID --mount=type=secret,uid=1000,id=AWS_SECRET_ACCESS_KEY \
    if [ -f "${REPO_SECRET_FILE}" -a ! -z "${TIMESCALE_CLOUDUTILS}" -a -z "${OSS_ONLY}" ]; then \
        [ -f "/run/secrets/AWS_ACCESS_KEY_ID" ] && export AWS_ACCESS_KEY_ID="$(cat /run/secrets/AWS_ACCESS_KEY_ID)" ; \
        [ -f "/run/secrets/AWS_SECRET_ACCESS_KEY" ] && export AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/AWS_SECRET_ACCESS_KEY)" ; \
        set -e \
        && cd /build \
        && cargo install cargo-pgx --git https://github.com/nikkhils/pgx.git --rev 4cc6a13; \
        for pg in ${PG_VERSIONS}; do \
            if [ ${pg} -ge "13" ]; then \
                [ -d "/build/timescaledb_cloudutils/.git" ] || git clone https://github-actions:$(cat "${REPO_SECRET_FILE}")@github.com/timescale/timescaledb_cloudutils || exit 1 ; \
                cd /build/timescaledb_cloudutils && git reset HEAD --hard && git checkout ${TIMESCALE_CLOUDUTILS} ; \
                export PG_CONFIG="/usr/lib/postgresql/${pg}/bin/pg_config"; \
                export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}"; \
                cargo pgx init --pg${pg} /usr/lib/postgresql/${pg}/bin/pg_config; \
                git clean -f -x; \
                make clean && make install -j1 || exit 1; \
            fi; \
        done; \
    fi

# Protected Roles is a library that restricts the CREATEROLE/CREATEDB privileges of non-superusers.
# It is a private timescale project and is therefore not included/built by default
ARG TIMESCALE_TSDB_ADMIN=
RUN --mount=type=secret,uid=1000,id=private_repo_token \
    if [ -f "${REPO_SECRET_FILE}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_TSDB_ADMIN}" ]; then \
        cd /build \
        && git clone https://github-actions:$(cat "${REPO_SECRET_FILE}")@github.com/timescale/protected_roles \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/protected_roles && git reset HEAD --hard && git checkout ${TIMESCALE_TSDB_ADMIN} \
            && make clean && PG_CONFIG=/usr/lib/postgresql/${pg}/bin/pg_config make install || exit 1 ; \
        done; \
    fi

# pg_stat_monitor is a Query Performance Monitoring tool for PostgreSQL
# https://github.com/percona/pg_stat_monitor
ARG PG_STAT_MONITOR=
RUN if [ ! -z "${PG_STAT_MONITOR}" ]; then \
        cd /build \
        && git clone https://github.com/percona/pg_stat_monitor \
        && for pg in ${PG_VERSIONS}; do \
            export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" \
            && cd /build/pg_stat_monitor && git reset HEAD --hard && git checkout "${PG_STAT_MONITOR}" \
            && make USE_PGXS=1 \
            && make USE_PGXS=1 install || exit 1 ; \
        done; \
    fi

# pg_auth_mon is an extension to monitor authentication attempts
# It is also useful to determine whether the DB is actively used
# https://github.com/RafiaSabih/pg_auth_mon
ARG PG_AUTH_MON=
RUN if [ ! -z "${PG_AUTH_MON}" ]; then \
        cd /build \
        && git clone https://github.com/RafiaSabih/pg_auth_mon \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/pg_auth_mon && git reset HEAD --hard && git checkout "${PG_AUTH_MON}" \
            && make clean && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make install || exit 1 ; \
        done; \
    fi

# logerrors is an extension to count the number of errors logged by postgrs, grouped by the error codes
# https://github.com/munakoiso/logerrors
ARG PG_LOGERRORS=
RUN if [ ! -z "${PG_LOGERRORS}" ]; then \
        cd /build \
        && git clone https://github.com/munakoiso/logerrors \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/logerrors && git reset HEAD --hard && git checkout "${PG_LOGERRORS}" \
            && make clean && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" make install || exit 1 ; \
        done; \
    fi

ARG TIMESCALEDB_TOOLKIT_EXTENSIONS=
ARG TIMESCALEDB_TOOLKIT_REPO=github.com/timescale/timescaledb-toolkit
# build and install the timescaledb-toolkit extension
RUN if [ ! -z "${TIMESCALEDB_TOOLKIT_EXTENSIONS}" -a -z "${OSS_ONLY}" ]; then \
        set -e \
        && git clone "https://${TIMESCALEDB_TOOLKIT_REPO}" /build/timescaledb-toolkit \
        && cd /build/timescaledb-toolkit \
        && for pg in ${PG_VERSIONS}; do \
            /build/scripts/install_timescaledb-toolkit.sh ${pg} ${TIMESCALEDB_TOOLKIT_EXTENSIONS} || exit 1 ; \
        done; \
    fi

# We can remove this at some point, useful for debugging builds for now
RUN /build/bin/sccache --show-stats

USER root

# All the tools that were built in the previous steps have their ownership set to postgres
# to allow mutability. To allow one to build this image with the default privileges (owned by root)
# one can set the ALLOW_ADDING_EXTENSIONS argument to anything but "true".
ARG ALLOW_ADDING_EXTENSIONS=true
RUN if [ "${ALLOW_ADDING_EXTENSIONS}" != "true" ]; then \
        for pg in ${PG_VERSIONS}; do \
            for dir in "$(/usr/lib/postgresql/${pg}/bin/pg_config --sharedir)/extension" "$(/usr/lib/postgresql/${pg}/bin/pg_config --pkglibdir)" "$(/usr/lib/postgresql/${pg}/bin/pg_config --bindir)"; do \
                chown root:root "{dir}" -R ; \
            done ; \
        done ; \
    fi

## Cleanup
FROM builder AS trimmed

RUN apt-get purge -y ${BUILD_PACKAGES}
RUN apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_?? \
            /home/postgres/.pgx \
            /build/ \
            /usr/local/rustup \
            /usr/local/cargo \
    && find /var/log -type f -exec truncate --size 0 {} \;

## Create a smaller Docker image from the builder image
FROM scratch
COPY --from=trimmed / /

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
