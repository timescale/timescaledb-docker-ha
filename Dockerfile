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
FROM debian:stretch-slim AS builder

ARG PG_MAJOR=11
ARG GH_SPILO_TAG=1.5-p7

# Install the highlest level dependencies, like the PostgreSQL repositories,
# the common PostgreSQL package etc.
RUN echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend \
    && apt-get update \
    && apt-get install -y curl ca-certificates locales gnupg1 jq \
    && for t in deb deb-src; do \
    echo "$t http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" >> /etc/apt/sources.list.d/pgdg.list; \
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
        apt-get install -y postgresql-${pg} postgresql-server-dev-${pg}; \
    done \
    ## We want timescaledb to be loaded in this image by every created cluster
    && find /usr/share/postgresql -name 'postgresql.conf.sample' -exec \
       sed -r -i "s/[#]*\s*(shared_preload_libraries)\s*=\s*'(.*)'/\1 = 'timescaledb,\2'/;s/,'/'/" {} \;

ENV TS_VERSIONS="0.10.1 0.11.0 0.12.0 0.12.1 1.0.0-rc1 1.0.0-rc2 1.0.0-rc3 1.0.0 1.0.1 1.1.0 1.1.1 1.2.0 1.2.1 1.2.2 1.3.0 1.3.1"
# Timescale, all versions, for all pg versions
RUN mkdir -p /build \
    && git clone https://github.com/timescale/timescaledb /build/timescaledb \
    && set -e \
    && for pg in ${PG_VERSIONS}; do \
        for ts in ${TS_VERSIONS}; do \
            # Older versions (< 1.1) of TimescaleDB can only be built against PostgreSQL 9.6 or 10.
            # As we need to carefully compare semantic versions, bash comparisons may be a bit awkward
            # - if not flat out wrong -
            # luckily dpkg has a useful flag to compare versions
            if dpkg --compare-versions ${pg} lt 11 || dpkg --compare-versions ${ts} ge 1.1; then \
                cd /build/timescaledb && git reset HEAD --hard && git checkout ${ts} \
                && rm -rf build \
                && PATH="/usr/lib/postgresql/${pg}/bin:${PATH}" ./bootstrap -DPROJECT_INSTALL_METHOD="docker"${OSS_ONLY} \
                && cd build && make -j 6 install || exit 1; \
            else \
                echo "Skipping building TimescaleDB ${ts} for PostgreSQL ${pg}"; \
            fi; \
        done; \
    done \
    && cd / && rm -rf /build

# Patroni and Spilo Dependencies
RUN apt-get install -y patroni python3-etcd python3-requests python3-pystache

# Kubernetes requires some newer stuff, so we use pip3 to get that installed
RUN apt-get install -y python3-oauthlib python3-certifi python3-requests-oauthlib python3-pip python3-wheel python3-dev
RUN pip3 install setuptools && true \
    && pip3 install kubernetes \
    && for d in /usr/local/lib/python3.? /usr/lib/python3; do \
        cd $d/dist-packages \
        && find . -type d -name tests | xargs rm -fr \
        && find . -type f -name 'test_*.py*' -delete; \
    done \
    && find . -type f -name 'unittest_*.py*' -delete \
    && find . -type f -name '*_test.py' -delete \
    && find . -type f -name '*_test.cpython*.pyc' -delete

WORKDIR /
## The postgres operator requires the Docker Image to be Spilo. That does not really entail much,  than a pretty
## tight coupling between environment variables and the `configure_spilo` script. As we don't want to all the
## logic, let's just use that script to configure to configure our container as well.
RUN curl -O -L https://raw.githubusercontent.com/zalando/spilo/${GH_SPILO_TAG}/postgres-appliance/scripts/configure_spilo.py

## Docker entrypoints and configuration scripts
ADD patroni_entrypoint.sh /
## Some patroni callbacks are configured by default by the operator.
COPY scripts /scripts/

## Cleanup
RUN apt-get update \
    && apt-get remove -y ${BUILD_PACKAGES} postgresql-server-dev-${PG_MAJOR} python3-pip python3-wheel python3-dev jq \
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


ENV PGROOT=/home/postgres \
    PGDATA=/home/postgres/data \
    PGLOG=/home/postgres/pg_log

## The postgres operator has strong opinions about the HOME directory of postgres, whereas we do not.  make
## the operator happy then
RUN usermod postgres --home ${PGROOT} --move-home

## The /etc/supervisor/conf.d directory is a very Spilo oriented directory. However, to make things work
## the user postgres currently needs to have write access to this directory
RUN install -o postgres -g postgres -m 0750 -d "${PGROOT}" "${PGLOG}" "${PGDATA}" /etc/supervisor/conf.d /scripts

## Some configurations allow daily csv files, with foreign data wrappers pointing to the files.
## to make this work nicely, they need to exist though
RUN for i in $(seq 0 7); do touch "${PGLOG}/postgresql-$i.log" "${PGLOG}/postgresql-$i.csv"; done

## Fix permissions
RUN chown postgres:postgres "${PGLOG}" "${PGROOT}" "${PGDATA}" /var/run/postgresql/ /etc/pgbackrest.conf /var/log/pgbackrest/ -R
## END SPILO compatibility

WORKDIR /home/postgres
EXPOSE 5432 8008
USER postgres

CMD ["/bin/bash", "/patroni_entrypoint.sh"]
