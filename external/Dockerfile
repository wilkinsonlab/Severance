FROM ruby:3.2-slim

# Install build deps + gosu (for dropping privileges safely)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      gosu \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user/group
RUN groupadd -r barelythere && \
    useradd -r -g barelythere -d /app -s /sbin/nologin -c "Docker app user" barelythere

WORKDIR /app

# Gem caching layer
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy app + entrypoint
COPY app.rb .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Pre-create dirs (optional, but good for non-volume cases)
RUN mkdir -p /data/queue /data/results

# VOLUME declaration (Docker knows this is a mount point)
VOLUME /data

ENV PORT=4567
EXPOSE 4567

# Start as root → entrypoint will chown then drop to barelythere
ENTRYPOINT ["./entrypoint.sh"]