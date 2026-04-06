FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN groupadd -r severance && \
    useradd -r -g severance -d /app -s /sbin/nologin -c "Docker app user" severance

WORKDIR /app

# Gem caching layer
COPY Gemfile Gemfile.lock annotation_parser.rb innie.rb ./
COPY queries /queries
RUN bundle install --jobs 4 --retry 3
USER severance

CMD ["ruby", "innie.rb"]
