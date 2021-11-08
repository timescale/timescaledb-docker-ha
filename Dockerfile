## The purpose of this Dockerfile is to build an image that contains:
## - timescale from (internal) sources
## - many PostgreSQL extensions
## - patroni for High Availability
## - spilo to allow the github.com/zalando/postgres-operator to be compatible
## - pgBackRest to allow good backups

# By including multiple versions of PostgreSQL we can use the same Docker image,
# regardless of the major PostgreSQL Version. It also allow us to support (eventually)
# pg_upgrade from 12 to 13, so we need all the postgres & timescale libraries for all versions
ARG PG_VERSIONS="13 12"
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
FROM ubuntu:21.04 AS compiler

# We need full control over the running user, including the UID, therefore we
# create the postgres user as the first thing on our list
RUN adduser --home /home/postgres --uid 1000 --disabled-password --gecos "" postgres

RUN echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/01norecommend
RUN echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/01norecommend

# Install the highlest level dependencies
RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg1 gpg gpg-agent locales lsb-release wget

RUN mkdir -p /build
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

# The next 2 instructions (ENV + RUN) are directly copied from https://github.com/rust-lang/docker-rust/blob/878a3bd2f3d92e51b9984dba8f8fd8881367a063/1.55.0/bullseye/Dockerfile
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH \
    RUST_VERSION=1.55.0
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
RUN apt-get install -y python3-etcd python3-requests python3-pystache python3-kubernetes python3-pysyncobj

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


RUN for pg in ${PG_VERSIONS}; do \
        apt-get install -y postgresql-${pg} postgresql-${pg}-dbgsym postgresql-plpython3-${pg} postgresql-plperl-${pg} postgresql-server-dev-${pg} \
            postgresql-${pg}-pgextwlist postgresql-${pg}-hll postgresql-${pg}-pgrouting postgresql-${pg}-repack postgresql-${pg}-hypopg postgresql-${pg}-unit \
            postgresql-${pg}-pg-stat-kcache postgresql-${pg}-cron || exit 1; \
    done

# We put Postgis in first, so these layers can be reused
ARG POSTGIS_VERSIONS="3"
RUN for postgisv in ${POSTGIS_VERSIONS}; do \
        for pg in ${PG_VERSIONS}; do \
            apt-get install -y postgresql-${pg}-postgis-${postgisv} || exit 1; \
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

FROM compiler as builder
ARG PG_VERSIONS

# timescaledb-tune, as well as timescaledb-parallel-copy
RUN wget -O - https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor --output /usr/share/keyrings/timescaledb.keyring
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/timescaledb.keyring] https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -s -c) main" > /etc/apt/sources.list.d/timescaledb.list

RUN apt-get update && apt-get install -y timescaledb-tools

## Entrypoints as they are from the Timescale image and its default alpine upstream repositories.
## This ensures the default interface (entrypoint) equals the one of the github.com/timescale/timescaledb-docker one,
## which allows this Docker Image to be a drop-in replacement for those Docker Images.
ARG GITHUB_TIMESCALEDB_DOCKER_REF=master
ARG GITHUB_DOCKERLIB_POSTGRES_REF=master
RUN cd /build && git clone https://github.com/timescale/timescaledb-docker && cd /build/timescaledb-docker && git checkout ${GITHUB_TIMESCALEDB_DOCKER_REF}
RUN cp -a /build/timescaledb-docker/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d/
RUN curl -s -o /usr/local/bin/docker-entrypoint.sh https://raw.githubusercontent.com/docker-library/postgres/${GITHUB_DOCKERLIB_POSTGRES_REF}/13/alpine/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
# Satisfy assumptions of the entrypoint scripts
RUN ln -s /usr/bin/timescaledb-tune /usr/local/bin/timescaledb-tune
RUN ln -s /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh

# hot-forge is a project that allows hot-patching of postgres containers
# It is currently a private timescale project and is therefore not included/built by default,
# and never included in the OSS image.
ARG PRIVATE_REPO_TOKEN=
ARG TIMESCALE_HOT_FORGE=
RUN if [ ! -z "${PRIVATE_REPO_TOKEN}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_HOT_FORGE}" ]; then \
        GH_REPO="https://api.github.com/repos/timescale/hot-forge"; \
        ASSET_ID="$(curl -sL --header "Authorization: token ${PRIVATE_REPO_TOKEN}" "${GH_REPO}/releases/tags/${TIMESCALE_HOT_FORGE}" | jq '.assets[0].id')"; \
        curl -sL --header "Authorization: token ${PRIVATE_REPO_TOKEN}" \
                 --header 'Accept: application/octet-stream' \
                 "${GH_REPO}/releases/assets/${ASSET_ID}" > /usr/local/bin/hot-forge || exit 1; \
        chmod 0755 /usr/local/bin/hot-forge ; \
        hot-forge -V || exit 1 ; \
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

ARG OSS_ONLY
ARG GITHUB_USER
ARG GITHUB_TOKEN
ARG GITHUB_REPO=timescale/timescaledb
ARG GITHUB_TAG
RUN if [ "${GITHUB_TOKEN}" != "" ]; then \
        git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}" /build/timescaledb; \
    else \
        git clone "https://github.com/${GITHUB_REPO}" /build/timescaledb; \
    fi

# INSTALL_METHOD will show up in the telemetry, which makes it easier to identify these installations
ARG INSTALL_METHOD=docker-ha

# If a specific GITHUB_TAG is provided, we will build that tag only. Otherwise
# we build all the public (recent) releases
RUN TS_VERSIONS="1.6.0 1.6.1 1.7.0 1.7.1 1.7.2 1.7.3 1.7.4 1.7.5 2.0.0-rc3 2.0.0-rc4 2.0.0 2.0.1 2.0.2 2.1.0 2.1.1 2.2.0 2.2.1 2.3.0 2.3.1 2.4.0 2.4.1 2.4.2 2.5.0" \
    && if [ "${GITHUB_TAG}" != "" ]; then TS_VERSIONS="${GITHUB_TAG}"; fi \
    && cd /build/timescaledb && git pull \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        for ts in ${TS_VERSIONS}; do \
            if [ ${pg} -ge 13 ] && [ "$(expr substr ${ts} 1 1)" = "1" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && if [ ${pg} -ge 13 ] && [ "$(expr substr ${ts} 1 3)" = "2.0" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && if [ ${pg} -ge 12 ] && [ "$(expr substr ${ts} 1 3)" = "1.6" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && if [ ${pg} -lt 12 ] && [ "$(expr substr ${ts} 1 3)" = "2.4" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && if [ ${pg} -lt 12 ] && [ "$(expr substr ${ts} 1 3)" = "2.5" ]; then echo "Skipping: TimescaleDB ${ts} is not supported on PostgreSQL ${pg}" && continue; fi \
            && cd /build/timescaledb && git reset HEAD --hard && git clean -f -d -x && git checkout ${ts} \
            && rm -rf build \
            && if [ "${ts}" = "2.2.0" ]; then sed -i 's/RelWithDebugInfo/RelWithDebInfo/g' CMakeLists.txt; fi \
            && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DTAP_CHECKS=OFF -DWARNINGS_AS_ERRORS=off -DCMAKE_BUILD_TYPE=RelWithDebInfo -DREGRESS_CHECKS=OFF -DGENERATE_DOWNGRADE_SCRIPT=ON -DPROJECT_INSTALL_METHOD="${INSTALL_METHOD}"${OSS_ONLY} \
            && cd build && make install || exit 1; \
        done; \
    done

ARG TIMESCALE_PROMSCALE_EXTENSION=
# build and install the promscale_extension extension
RUN if [ ! -z "${TIMESCALE_PROMSCALE_EXTENSION}" -a -z "${OSS_ONLY}" ]; then \
        set -e \
        && cargo install --git https://github.com/JLockerman/pgx.git --branch timescale cargo-pgx \
        && git clone https://github.com/timescale/promscale_extension /build/promscale_extension \
        && for pg in ${PG_VERSIONS}; do \
            if [ ${pg} -ge "12" ]; then \
            export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}"; \
                cargo pgx init --pg${pg} /usr/lib/postgresql/${pg}/bin/pg_config \
                && cd /build/promscale_extension && git reset HEAD --hard && git checkout ${TIMESCALE_PROMSCALE_EXTENSION} \
                && git clean -f -x \
                && PG_VER=pg${pg} make install || exit 1; \
            fi; \
        done; \
    fi

# Make sure to override this when upgrading to new PGX version
ARG PGX_VERSION=0.1.21
ARG TIMESCALE_CLOUDUTILS=
# build and install the cloudutils libarary and extension
RUN if [ ! -z "${TIMESCALE_CLOUDUTILS}" -a -z "${OSS_ONLY}" ]; then \
        set -e \
        && cd /build \
        && cargo install cargo-pgx --version ${PGX_VERSION}; \
        for pg in ${PG_VERSIONS}; do \
            if [ ${pg} -ge "12" ]; then \
                [ -d "/build/timescaledb_cloudutils/.git" ] || git clone https://github-actions:${PRIVATE_REPO_TOKEN}@github.com/timescale/timescaledb_cloudutils || exit 1 ; \
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
RUN if [ ! -z "${PRIVATE_REPO_TOKEN}" -a -z "${OSS_ONLY}" -a ! -z "${TIMESCALE_TSDB_ADMIN}" ]; then \
        cd /build \
        && git clone https://github-actions:${PRIVATE_REPO_TOKEN}@github.com/timescale/protected_roles \
        && for pg in ${PG_VERSIONS}; do \
            cd /build/protected_roles && git reset HEAD --hard && git checkout ${TIMESCALE_TSDB_ADMIN} \
            && make clean && PG_CONFIG=/usr/lib/postgresql/${pg}/bin/pg_config make install || exit 1 ; \
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

ARG TIMESCALEDB_TOOLKIT_EXTENSION=
ARG TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS=
# build and install the timescaledb-toolkit extension
RUN if [ ! -z "${TIMESCALEDB_TOOLKIT_EXTENSION}" -a -z "${OSS_ONLY}" ]; then \
        set -e \
        && cargo install --git https://github.com/JLockerman/pgx.git --branch timescale cargo-pgx \
        && git clone https://github.com/timescale/timescaledb-toolkit /build/timescaledb-toolkit \
        && for pg in ${PG_VERSIONS}; do \
            if [ ${pg} -ge "12" ]; then \
                export PATH="/usr/lib/postgresql/${pg}/bin:${PATH}"; \
                cargo pgx init --pg${pg} /usr/lib/postgresql/${pg}/bin/pg_config \
                # build previous version if one was provided
                && for tookit in ${TIMESCALEDB_TOOLKIT_EXTENSION_PREVIOUS}; do \
                    echo "building previous toolkit version ${tookit} for pg${pg}" \
                    && cd /build/timescaledb-toolkit \
                    && git reset HEAD --hard \
                    && git checkout ${tookit} \
                    && git clean -f -x \
                    && cd extension && cargo pgx install --release \
                    && cargo run --manifest-path ../tools/post-install/Cargo.toml -- /usr/lib/postgresql/${pg}/bin/pg_config; \
                done \
                && echo "building toolkit version ${TIMESCALEDB_TOOLKIT_EXTENSION} for pg${pg}" \
                && cd /build/timescaledb-toolkit \
                && git reset HEAD --hard \
                && git checkout ${TIMESCALEDB_TOOLKIT_EXTENSION} \
                && git clean -f -x \
                && cd extension && cargo pgx install --release \
                && cargo run --manifest-path ../tools/post-install/Cargo.toml -- /usr/lib/postgresql/${pg}/bin/pg_config; \
            fi; \
        done; \
    fi

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
