#!/bin/bash

function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - post_init - $1"
}

log "Waiting for pgBackRest API to become responsive"
while sleep 1; do
    if [ $SECONDS -gt 10 ]; then
        log "pgBackRest API did not respond within $SECONDS seconds, will not trigger a backup"
        exit 0
    fi
    timeout 1 bash -c "echo > /dev/tcp/localhost/8081" 2>/dev/null && break
done

log "Triggering backup"
curl -i -X POST http://localhost:8081/backups

# We always exit 0 this script, otherwise the database initialization fails.
exit 0