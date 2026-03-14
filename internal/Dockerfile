FROM ruby:3.2-slim
WORKDIR /app
COPY internal/internal.rb .
COPY queries /queries
CMD ["ruby", "internal.rb"]
