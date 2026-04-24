FROM ruby:3.2-slim

# Install build deps + gosu (for dropping privileges safely)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      gosu \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user/group
RUN groupadd -r severance && \
    useradd -r -g severance -d /app -s /sbin/nologin -c "Docker app user" severance

WORKDIR /app

# Gem caching layer
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy app + entrypoint
COPY outie.rb .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Pre-create dirs (optional, but good for non-volume cases)
RUN mkdir -p /data/queue /data/results

# VOLUME declaration (Docker knows this is a mount point)
VOLUME /data

ENV PORT=3000
EXPOSE 3000

# Start as root → entrypoint will chown then drop to severance
ENTRYPOINT ["./entrypoint.sh"]
