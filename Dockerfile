# The purpose of this Dockerfile is to build an image that contains:
# - timescale from (internal) sources
# - patroni for High Availability
# - spilo to allow the github.com/zalando/postgres-operator to be compatible
#
# As the postgres-operator is only compatible with a Spilo image, we need to do some things that may not seem obvious
# those items are clearly marked with a
#
# START/END Spilo
#
# tag.
ARG PG_MAJOR

FROM timescale/timescaledb:latest-pg${PG_MAJOR}
ENV SPILO_TAG 1.5-p7
ENV PGBACKREST_TAG 2.13
ENV PGROOT=/home/postgres \
    PGDATA=$PGROOT/data \
    PGLOG=$PGROOT/pg_log
ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 EDITOR=/usr/bin/editor
RUN set -ex \
    && apk add --no-cache python3 openssl perl \
    && apk add --no-cache --virtual .build-deps \
                coreutils \
                gcc \
                python3-dev \
                py3-pip \
                musl-dev \
                linux-headers \
                curl \
                shadow \
                make \
                perl-dev \
                zlib-dev \
                openssl-dev \
                libxml2-dev \
    ## START pgBackrest https://pgbackrest.org/user-guide.html#build
    && mkdir -p /tmp/pgbackrest \
    && pwd \
    && curl -L https://github.com/pgbackrest/pgbackrest/archive/release/${PGBACKREST_TAG}.tar.gz > /tmp/pgbackrest/pgbackrest.tar.gz \
    && cd /tmp/pgbackrest/ && tar xzfp pgbackrest.tar.gz \
    && make -s -C /tmp/pgbackrest/pg*/src \
    && cp -a /tmp/pgbackrest/pg*/src/pgbackrest /usr/bin \
    && chmod 755 /usr/bin/pgbackrest \
    && install -o postgres -g postgres -m 0770 -d /etc/pgbackrest/ /etc/pgbackrest/conf.d /var/log/pgbackrest \
    && rm -rf /tmp/pgbackrest && cd -\
    ## END pgBackrest
    ## START SPILO compatibility
    ## The postgres operator requires the Docker Image to be Spilo. That does not really entail much, other than a pretty
    ## tight coupling between environment variables and the `configure_spilo` script. As we don't want to copy all the
    ## logic, let's just use that script to configure to configure our container as well.
    && curl -O -L https://raw.githubusercontent.com/zalando/spilo/${SPILO_TAG}/postgres-appliance/scripts/configure_spilo.py \
    && mkdir -p /usr/lib/postgresql/${PG_MAJOR} && ln -s /usr/local/bin /usr/lib/postgresql/${PG_MAJOR} \
    ## The postgres operator has strong opinions about the HOME directory of postgres, whereas we do not. Let's make
    ## the operator happy then
    && usermod postgres --home /home/postgres --move-home \
    ## The /etc/supervisor/conf.d directory is a very Spilo oriented directory. However, to make things work
    ## the user postgres currently needs to have write access to this directory
    && install -o postgres -g postgres -m 0750 -d "${PGROOT}" "${PGLOG}" "${PGDATA}" /etc/supervisor/conf.d /scripts \
    ## Some configurations allow daily csv files, with foregin data wrappers pointing to the files.
    ## to make this work, they need to exist though
    && for i in $(seq 0 7); do touch "${PGLOG}/postgresql-$i.{csv,log}"; done && chown postgres:postgres -R "${PGLOG}" \
    ## END SPILO compatibility
    && pip3 install patroni kubernetes pystache "urllib3<1.25" "python-etcd>=0.4.3,<0.5" \
    && apk del .build-deps

ADD patroni_entrypoint.sh /
# Some patroni callbacks are configured by default by the operator.
COPY scripts /scripts/

WORKDIR "${PGROOT}"
EXPOSE 5432 8008
USER postgres

CMD ["/bin/bash", "/patroni_entrypoint.sh"]
