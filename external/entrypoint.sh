#!/bin/sh
set -e

# create and/or Fix ownership of the mounted volume (runs as root)
mkdir -p /metadata /data  

chown -R "${UID:-1000}:${GID:-1000}" /metadata /data
chmod -R u+rwX /metadata /data  

# Drop privileges and run app
# exec su-exec barelythere bundle exec ruby app.rb
exec gosu severance bundle exec ruby outie.rb
