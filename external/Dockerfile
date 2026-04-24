# ── Build stage ───────────────────────────────────────────────────────────────
# The -dev variant includes compilers (for native gem extensions) and apt, so
# we can install gosu here and copy only its binary to the runtime stage.
# This keeps the runtime image free of gosu's apt dependencies.
FROM dhi.io/ruby:3-debian13-dev AS builder

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/* && \
    # Debian Trixie installs gosu to /usr/sbin/gosu; copy to a stable path
    # that the COPY --from=builder line below can rely on across Debian versions.
    cp /usr/sbin/gosu /usr/local/bin/gosu && chmod 0755 /usr/local/bin/gosu

WORKDIR /app

# Gem layer cached separately so a code-only change skips re-bundling.
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3


# ── Runtime stage ─────────────────────────────────────────────────────────────
# All DHI Ruby runtime variants (ruby:3, ruby:3-debian13) are distroless —
# no /bin/sh — which is incompatible with the sh entrypoint script.
# The -dev image is the only DHI Ruby image that ships a shell.  Using it here
# still gives signed SBOMs, SLSA Level 3 provenance, and Docker-maintained
# security patching; it just retains build tools in the runtime layer.
# TODO: convert entrypoint.sh to a Ruby script to enable the truly minimal
#       distroless runtime (dhi.io/ruby:3).
FROM dhi.io/ruby:3-debian13-dev

# Use numeric UID 0 rather than the name "root": DHI hardened images strip the
# named root entry from /etc/passwd, so `USER root` causes Docker to fail with
# "no matching entries in passwd file".  Numeric UIDs bypass that lookup.
# Root is required here so the entrypoint can chown /data and /queries-metadata.
USER 0

# Copy only the gosu binary — no apt packages installed in the runtime image.
COPY --from=builder /usr/local/bin/gosu /usr/local/bin/gosu

# Create the non-root user the application runs as after the privilege drop.
# The DHI image does not ship groupadd/useradd, so we write directly to the
# passwd and group files — the standard approach for minimal/hardened images.
RUN echo "severance:x:1000:1000:Docker app user:/app:/sbin/nologin" >> /etc/passwd && \
    echo "severance:x:1000:" >> /etc/group

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY outie.rb .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Pre-create volume subdirectories so they are owned by root initially;
# the entrypoint chowns them to severance (1000) before the app starts.
RUN mkdir -p /data/queue /data/results

VOLUME /data

ENV PORT=3000
EXPOSE 3000

# Container starts as root (set above) so the entrypoint can fix volume
# ownership, then drops to severance via gosu.  See entrypoint.sh.
ENTRYPOINT ["./entrypoint.sh"]
