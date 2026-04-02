#!/bin/sh
set -e

# Fix ownership of the mounted volume (runs as root)
chown -R barelythere:barelythere /data

# Drop privileges and run app
# exec su-exec barelythere bundle exec ruby app.rb
exec gosu barelythere bundle exec ruby app.rb
