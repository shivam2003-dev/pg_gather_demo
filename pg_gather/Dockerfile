# =============================================================================
# pg_gather runner image
# Reuses the same postgres:16-bookworm base so psql version exactly matches
# the server.  All we add is git (to clone the tool) and the tool itself.
# =============================================================================
FROM postgres:16-bookworm

# git  : clone pg_gather from GitHub
# ca-certificates : needed for HTTPS clone
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone pg_gather into /pg_gather inside the image.
# Baking it into the image means the container works offline after first build.
RUN git clone --depth 1 https://github.com/jobinau/pg_gather.git /pg_gather

# Copy our setup script and make it executable
COPY setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

# Reports will be written here — docker-compose mounts ./reports to this path
VOLUME /reports

# Default command: run setup.sh
# Override with `docker compose run pg_gather bash` to explore interactively
CMD ["/usr/local/bin/setup.sh"]
