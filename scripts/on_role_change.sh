#!/bin/bash

cat <<EOT
$(date) - $0 - I was called with the following parameters: $@
EOT

# Keep synchronized_standby_slots correct for logical-replication-slot failover:
# only the primary should advertise the physical standby slots; standbys clear it.
# Patroni appends "<action> <role> <scope>" to the configured command, so the new
# role is always the second-to-last argument regardless of any leading args.
set -euo pipefail

role="${@: -2:1}"

case "$role" in
  master|primary)
    # List the physical slots currently streamed by connected standbys. "active"
    # guarantees the slot exists (naming a missing slot stalls logical decoding)
    # and needs no member-naming convention, so this stays generic to the image.
    # ponytail: includes ANY active physical streamer; if a separate read-replica
    #           cluster streams from this primary and must be excluded, filter by
    #           this cluster's Patroni members (patronictl list / REST /cluster).
    slots="$(psql -qtAX -d postgres -c \
      "SELECT coalesce(string_agg(slot_name, ','), '') FROM pg_replication_slots \
        WHERE slot_type = 'physical' AND NOT temporary AND active")"
    psql -qtAX -d postgres -c "ALTER SYSTEM SET synchronized_standby_slots = '${slots}'"
    ;;
  *)
    # replica / standby_leader / demoted: a non-primary must not advertise slots.
    psql -qtAX -d postgres -c "ALTER SYSTEM RESET synchronized_standby_slots"
    ;;
esac

psql -qtAX -d postgres -c "SELECT pg_reload_conf()"
