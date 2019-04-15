ARG PG_VERSION

FROM timescale/timescaledb:latest-pg${PG_VERSION}
RUN set -ex \
    && apk add --no-cache python3 \
    && apk add --no-cache --virtual .build-deps \
                coreutils \
                gcc \
                python3-dev \
                py3-pip \
                musl-dev \
                linux-headers \
    && pip3 install patroni kubernetes \
    && apk del .build-deps

ADD patroni_entrypoint.sh /
ENV LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 EDITOR=/usr/bin/editor
WORKDIR /var/lib/postgresql
EXPOSE 5432 8008
USER postgres

CMD ["/bin/bash", "/patroni_entrypoint.sh"]
