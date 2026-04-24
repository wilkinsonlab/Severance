#!/bin/sh
set -e

# Runs as root: ensure mounted volume directories exist and are owned by the
# severance user (uid 1000) so the application can read and write them.
# UID/GID default to 1000 if not set; external docker-compose does not inject
# them because this container uses a fixed service account rather than mirroring
# the host operator's uid (unlike the internal component).
mkdir -p /queries-metadata /data

chown -R "${UID:-1000}:${GID:-1000}" /queries-metadata /data
chmod -R u+rwX /queries-metadata /data

# Drop from root to the severance user before exec'ing the application.
# Using gosu rather than su avoids TTY issues and gives a clean process tree.
exec gosu severance bundle exec ruby outie.rb
