#!/bin/sh
set -e

# create and/or Fix ownership of the mounted volume (runs as root)
mkdir -p /queries-metadata /data  

chown -R "${UID:-1000}:${GID:-1000}" /queries-metadata /data
chmod -R u+rwX /queries-metadata /data  

# Drop privileges and run app as current user
exec bundle exec ruby outie.rb
