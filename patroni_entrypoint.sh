#!/bin/sh

# Our upstream Dockerfile does not have pam included, therefore we need to ensure
# no pam configuration is added to the PostgreSQL cluster
export PAM_OAUTH2=""

PGVERSION=${PGMAJOR} python3 /configure_spilo.py patroni patronictl certificate

exec patroni /home/postgres/postgres.yml

