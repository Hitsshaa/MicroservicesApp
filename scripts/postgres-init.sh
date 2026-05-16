#!/bin/bash
# Postgres init script — creates the two application databases at first boot.
# Mounted by docker-compose.yml into /docker-entrypoint-initdb.d/, which the
# official postgres image executes once when initializing a fresh data volume.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE userservicedb;
    CREATE DATABASE productservicedb;
EOSQL
