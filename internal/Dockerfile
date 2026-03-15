FROM ruby:3.2-slim
WORKDIR /app
RUN groupadd -r barelythere && \
    useradd -r -g barelythere -d /app -s /sbin/nologin -c "Docker app user" barelythere
COPY internal.rb .
COPY queries /queries
USER barelythere
CMD ["ruby", "internal.rb"]
