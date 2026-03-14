FROM ruby:3.2-slim

# Install build deps only for gem native extensions (thin needs them)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Gemfile first → better layer caching
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install --jobs 4 --retry 3

# Now copy the app code
COPY app.rb .

# /data is our volume for queue + results
VOLUME /data

ENV PORT=4567
EXPOSE 4567

CMD ["bundle", "exec", "ruby", "app.rb"]
