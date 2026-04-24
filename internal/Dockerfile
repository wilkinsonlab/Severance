# ── Build stage ───────────────────────────────────────────────────────────────
# The -dev variant includes compilers and build tools needed to compile native
# gem extensions (C extensions).  Nothing from this stage lands in the final
# image except the compiled gem bundle, so build-essential is never present at
# runtime.
FROM dhi.io/ruby:3-debian13-dev AS builder

WORKDIR /app

# Gem layer cached separately so a code-only change skips re-bundling.
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Strip Windows CRLF line endings here while we have full tooling, so the
# runtime image does not need sed.
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh


# ── Runtime stage ─────────────────────────────────────────────────────────────
# All DHI Ruby runtime variants (ruby:3, ruby:3-debian13) are distroless —
# no /bin/sh — which is incompatible with the bash entrypoint script.
# The -dev image is the only DHI Ruby image that ships a shell.  Using it here
# still gives signed SBOMs, SLSA Level 3 provenance, and Docker-maintained
# security patching; it just retains build tools in the runtime layer.
# TODO: convert entrypoint.sh to a Ruby script to enable the truly minimal
#       distroless runtime (dhi.io/ruby:3).
FROM dhi.io/ruby:3-debian13-dev

# Use numeric UID 0 rather than the name "root": DHI hardened images strip the
# named root entry from /etc/passwd, so `USER root` causes Docker to fail with
# "no matching entries in passwd file".  Numeric UIDs bypass that lookup.
USER 0

WORKDIR /app

# Bring in the pre-compiled gem bundle — no compiler toolchain in this image.
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Application source and protected read-only demo query set.
COPY . .
COPY sample_queries /demo-queries

# Entrypoint already has CRLF stripped and +x set from the build stage.
COPY --from=builder /entrypoint.sh /entrypoint.sh

# No named user account is needed here: the DHI image does not ship groupadd/
# useradd, and more importantly the runtime UID/GID is injected entirely by
# docker-compose's `user: "${UID:-1000}:${GID:-1000}"` directive anyway.

# Pre-create /queries so Docker's bind-mount overlay starts from a known state.
# The entrypoint re-chowns this to the real runtime UID/GID on every startup.
RUN mkdir -p /queries && chown 1000:1000 /queries

# ── USER NOTE ─────────────────────────────────────────────────────────────────
# We intentionally do NOT set a USER directive here.  docker-compose injects:
#
#   user: "${UID:-1000}:${GID:-1000}"
#
# which overrides any image-default user and makes the container run as the
# host operator's own UID/GID.  That UID/GID is also passed as environment
# variables (UID=, GID=) so the entrypoint's chown can match the owner of the
# host-side ./queries bind-mount, ensuring the operator can edit query files
# directly on the host without permission errors.
#
# Do not add a USER directive here without also updating docker-compose.

ENTRYPOINT ["/entrypoint.sh"]
