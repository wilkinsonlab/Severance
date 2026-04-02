#!/bin/sh
set -e

# Fix ownership of the mounted volume (runs as root)
chown -R severance:severance /data /metadata
exec gosu severance bundle exec ruby outie.rb
# Drop privileges and run app
# exec su-exec barelythere bundle exec ruby app.rb
exec gosu severance bundle exec ruby outie.rb
