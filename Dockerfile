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
    && apt-get install -y curl ca-certificates locales gnupg1 jq \
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
ENV PG_VERSIONS="11"
ENV BUILD_PACKAGES="git patchutils binutils git gcc libc-dev make cmake libssl-dev"

# PostgreSQL, all versions
RUN apt-get install -y ${BUILD_PACKAGES}; \
    for pg in ${PG_MAJOR} ${PG_VERSIONS}; do \
        apt-get install -y postgresql-${pg} postgresql-server-dev-${pg} \
        # We get the perl and python dependencies in the image anyway (patroni, pgbackrest)
        # so why not allow their PL's to also be available in PostgreSQL
        && apt-get install -y postgresql-plpython3-${pg} postgresql-plperl-${pg} ; \
    done \
    ## We want timescaledb to be loaded in this image by every created cluster
    && find /usr/share/postgresql -name 'postgresql.conf.sample' -exec \
       sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" {} \;

# Timescale, all versions since 1.1.0. Building < 1.1.0 fails against PostgreSQL 11
RUN TS_VERSIONS=$(curl "https://api.github.com/repos/timescale/timescaledb/releases" \
        | jq -r '.[] | select(.draft == false) | select(.created_at > "2018-12-13") | .tag_name' | sort -V) \
    && mkdir -p /build \
    && git clone https://github.com/timescale/timescaledb /build/timescaledb \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        for ts in ${TS_VERSIONS}; do \
            cd /build/timescaledb && git reset HEAD --hard && git checkout ${ts} \
            && rm -rf build \
            && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DPROJECT_INSTALL_METHOD="docker"${OSS_ONLY} \
            && cd build && make -j 6 install || exit 1; \
        done; \
        apt-get remove -y postgresql-server-dev-${pg}; \
    done \
    && cd / && rm -rf /build

# Patroni and Spilo Dependencies
RUN apt-get install -y patroni python3-etcd python3-requests python3-pystache python3-kubernetes

# And we need some more pgBackRest dependencies for us to use an s3-bucket as a store
RUN apt-get install -y libio-socket-ssl-perl libxml-libxml-perl

## The postgres operator requires the Docker Image to be Spilo. That does not really entail much,  than a pretty
## tight coupling between environment variables and the `configure_spilo` script. As we don't want to all the
## logic, let's just use that script to configure to configure our container as well.
WORKDIR /scripts/
RUN curl -O -L https://raw.githubusercontent.com/zalando/spilo/${GH_SPILO_TAG}/postgres-appliance/scripts/configure_spilo.py



## Cleanup
RUN apt-get update \
    && apt-get remove -y ${BUILD_PACKAGES} \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_?? \
    && find /var/log -type f -exec truncate --size 0 {} \;

## Create a smaller Docker images from the builder image
FROM scratch
COPY --from=builder / /
## Docker entrypoints and configuration scripts
ADD patroni_entrypoint.sh /
## Some patroni callbacks are configured by default by the operator.
COPY scripts /scripts/


## The mount being used by the postgres-operator is /home/postgres/pgdata
## for Patroni to do it's work it will sometimes move an old/invalid data directory
## inside the parent directory; therefore we need a subdirectory inside the mount

ENV PGROOT=/home/postgres \
    PGDATA=/home/postgres/pgdata/data \
    PGLOG=/home/postgres/pg_log \
    PGSOCKET=/home/postgres/pgdata \
    BACKUPROOT=/home/postgres/pgdata/backup \
    PGBACKREST_CONFIG=/home/postgres/pgdata/backup/pgbackrest.conf \
    PGBACKREST_STANZA=poddb

## The postgres operator has strong opinions about the HOME directory of postgres, whereas we do not.  make
## the operator happy then
RUN usermod postgres --home ${PGROOT} --move-home

## The /etc/supervisor/conf.d directory is a very Spilo oriented directory. However, to make things work
## the user postgres currently needs to have write access to this directory
RUN install -o postgres -g postgres -m 0750 -d "${PGROOT}" "${PGLOG}" "${PGDATA}" "${BACKUPROOT}" /etc/supervisor/conf.d /scripts

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

CMD ["/bin/bash", "/patroni_entrypoint.sh"]
