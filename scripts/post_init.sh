#!/bin/bash
echo "$(date '+%Y-%m-%d %H:%M:%S') - creating pgBackRest stanza"
pgbackrest stanza-create --stanza=poddb --log-level-stderr=info

echo "$(date '+%Y-%m-%d %H:%M:%S') - Waiting for pgBackRest API to become responsive"
while ! timeout 1 bash -c "echo > /dev/tcp/localhost/8081"; do
  sleep 1
done
echo "$(date '+%Y-%m-%d %H:%M:%S') - triggering backup"
curl -i -X POST http://localhost:8081/backups