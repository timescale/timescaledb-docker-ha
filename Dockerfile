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

ARG PG_MAJOR=11
ARG GH_SPILO_TAG=1.5-p9

# We need full control over the running user, including the UID, therefore we
# create the postgres user as the first thing on our list
RUN adduser --home /home/postgres --uid 1000 --disabled-password --gecos "" postgres

# Install the highlest level dependencies, like the PostgreSQL repositories,
# the common PostgreSQL package etc.
RUN echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend \
    && apt-get update \
    && apt-get install -y curl ca-certificates locales gnupg1 \
    && for t in deb deb-src; do \
    echo "$t http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main" >> /etc/apt/sources.list.d/pgdg.list; \
    done \
    && curl -s -o - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get install -y postgresql-common pgbackrest \
    # forbid creation of a main cluster when package is installed
    && sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf

# Setup locales
RUN find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete \
    && find /usr/share/i18n/locales/ -type f ! -name en_US ! -name en_GB ! -name i18n* ! -name iso14651_t1 ! -name iso14651_t1_common ! -name 'translit_*' -delete \
    && echo 'en_US.UTF-8 UTF-8' > /usr/share/i18n/SUPPORTED \
    ## Make sure we have a en_US.UTF-8 locale available
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

# We currently only build 11, but in future release we may need to support
# pg_upgrade from 11 to 12, so we need all the postgres & timescale libraries for
# all supported versions. If we add 10 to this line, the Docker image grows with 90MB,
# so for now, we'll just leave it out
ENV PG_VERSIONS="${PG_MAJOR}"

ENV BUILD_PACKAGES="git binutils patchutils gcc libc-dev make cmake libkrb5-dev libssl-dev jq python2-dev python3-dev devscripts equivs"

# PostgreSQL, all versions
RUN apt-get install -y ${BUILD_PACKAGES}

# We install the build dependencies and mark the installed packages as auto-installed,
# this will cause the cleanup to get rid of all of these packages
RUN mk-build-deps postgresql-${PG_MAJOR} && apt-get install -y ./postgresql-11-build-deps*.deb && apt-mark auto postgresql-11-build-deps
RUN apt-mark auto ${BUILD_PACKAGES}
RUN apt-get install -y libpq-dev libpq5

RUN mkdir /build/
WORKDIR /build/

COPY customizations /build/customizations
ARG TS_CUSTOMIZATION=""

RUN for pg in ${PG_VERSIONS}; do \
        if [ -z "${TS_CUSTOMIZATION}" ]; then \
            # If no customizations are necessary, we'll just use the pgdg binary packages
            apt-get install -y postgresql-${pg} postgresql-plpython3-${pg} postgresql-plperl-${pg} postgresql-server-dev-${pg}; \
        else \
            # We'll fetch the sources, let the customizations script have its way at the sources
            # and then compile and install the customized packages
            cd /build/ && apt-get source postgresql-${pg} \
            && cd $(find /build/ -maxdepth 1 -name "postgresql-${pg}-*") \
            && PGVERSION=${pg} sh ../customizations/${TS_CUSTOMIZATION}* \
            && DEB_BUILD_OPTIONS="parallel=6 nocheck" /usr/bin/debuild -b -uc -us \
            && cd /build/ \
            && dpkg -i postgresql-${pg}_*.deb postgresql-client-${pg}_*.deb postgresql-server-dev-${pg}_*.deb postgresql-plpython3-${pg}_*.deb postgresql-plperl-${pg}_*.deb postgresql-client-${pg}_*.deb; \
        fi; \
    done

RUN for file in $(find /usr/share/postgresql -name 'postgresql.conf.sample'); do \
        # We want timescaledb to be loaded in this image by every created cluster
        sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" $file \
        # We need to listen on all interfaces, otherwise PostgreSQL is not accessible
        && echo "listen_addresses = '*'" >> $file; \
    done

RUN mkdir -p /build

ARG OSS_ONLY
# Timescale, all versions since 1.1.0. Building < 1.1.0 fails against PostgreSQL 11
RUN TS_VERSIONS=$(curl "https://api.github.com/repos/timescale/timescaledb/releases" \
        | jq -r '.[] | select(.draft == false) | select(.created_at > "2018-12-13") | .tag_name' | sort -V) \
    && git clone https://github.com/timescale/timescaledb /build/timescaledb \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        for ts in ${TS_VERSIONS}; do \
            cd /build/timescaledb && git reset HEAD --hard && git checkout ${ts} \
            && rm -rf build \
            && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DPROJECT_INSTALL_METHOD="docker"${OSS_ONLY} \
            && cd build && make -j 6 install || exit 1; \
        done; \
    done

## For local development, or private branches, it is useful to build the Dockerfile from those branches.
## To allow this to happen, a directory can be specified that has the full sources available for it to be built.
## We do this *after* we build all the regular, publicly available TimescaleDB sources, as by installing
## this last, the TimescaleDB Extension will default to the development version when installed.

ARG TS_CUSTOM_BUILD_DIRECTORY=
## We need a conditional COPY, however that does not readily exist in a Dockerfile
## By adding a file that is known to exist and a wildcard expression for the TS_CUSTOM_BUILD_DIRECTORY
## this command should always succeed
COPY Dockerfile ${TS_CUSTOM_BUILD_DIRECTORY}* /build/${TS_CUSTOM_BUILD_DIRECTORY}/

RUN if [ ! -z "${TS_CUSTOM_BUILD_DIRECTORY}" ]; then \
        cd /build/${TS_CUSTOM_BUILD_DIRECTORY}; \
        for pg in ${PG_VERSIONS}; do \
            rm -rf build \
            && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DREGRESS_CHECKS=OFF -DPROJECT_INSTALL_METHOD="docker"${OSS_ONLY} \
            && cd build && make -j 6 install || exit 1; \
        done; \
    fi

RUN cd / && rm -rf /build


# Patroni and Spilo Dependencies
RUN apt-get install -y patroni python3-etcd python3-requests python3-pystache python3-kubernetes

# And we need some more pgBackRest dependencies for us to use an s3-bucket as a store
RUN apt-get install -y libio-socket-ssl-perl libxml-libxml-perl

## The postgres operator requires the Docker Image to be Spilo. That does not really entail much,  than a pretty
## tight coupling between environment variables and the `configure_spilo` script. As we don't want to all the
## logic, let's just use that script to configure to configure our container as well.
WORKDIR /scripts/
RUN curl -O -L https://raw.githubusercontent.com/zalando/spilo/${GH_SPILO_TAG}/postgres-appliance/scripts/configure_spilo.py

# To always know what the git context was during building, we add git metadata to the image itself.
# see https://stups.readthedocs.io/en/latest/user-guide/application-development.html#scm-source-json for
# some background. By using jq we ensure it's valid json, as well as it is formatted semi human readable
ARG GIT_INFO_JSON=""
RUN [ -z "${GIT_INFO_JSON}" ] || echo "${GIT_INFO_JSON}" | jq . > /scm-source.json

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
    && find /var/log -type f -exec truncate --size 0 {} \;

## Create a smaller Docker images from the builder image
FROM scratch
COPY --from=builder / /

## Entrypoints as they are from the bitnami/timescale image
## We may want to reconsider this, for now this means we have the exact same interface
## for this Docker images as for our other Docker images
COPY --from=timescale/timescaledb /docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/
COPY --from=timescale/timescaledb /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --from=timescale/timescaledb /usr/local/bin/timescaledb-tune /usr/local/bin/timescaledb-tune

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

ARG PG_MAJOR=11

## The mount being used by the postgres-operator is /home/postgres/pgdata
## for Patroni to do it's work it will sometimes move an old/invalid data directory
## inside the parent directory; therefore we need a subdirectory inside the mount

ENV PGROOT=/home/postgres \
    PGDATA=/home/postgres/pgdata/data \
    PGLOG=/home/postgres/pg_log \
    PGSOCKET=/home/postgres/pgdata \
    BACKUPROOT=/home/postgres/pgdata/backup \
    PGBACKREST_CONFIG=/home/postgres/pgdata/backup/pgbackrest.conf \
    PGBACKREST_STANZA=poddb \
    PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:${PATH}

## The postgres operator has strong opinions about the HOME directory of postgres, whereas we do not.  make
## the operator happy then
RUN usermod postgres --home ${PGROOT} --move-home

## The /etc/supervisor/conf.d directory is a very Spilo oriented directory. However, to make things work
## the user postgres currently needs to have write access to this directory
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

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
