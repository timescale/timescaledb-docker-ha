#!/bin/sh
python3 /configure_spilo.py patroni patronictl certificate

exec patroni /home/postgres/postgres.yml

