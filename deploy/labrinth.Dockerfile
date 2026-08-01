FROM rust:1.95-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev libclang-dev clang lld cmake make libcurl4-openssl-dev libsasl2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Remove workspace members that depend on private git repos (not needed for labrinth)
# apps/app (theseus_gui) depends on private repos like modrinth/plugins-workspace
RUN sed -i '/"apps\/app",/d; /"apps\/app-playground",/d' Cargo.toml

# Sequential build (no parallelism) to minimize peak memory usage during linking
ENV CARGO_BUILD_JOBS=1
ENV CARGO_BUILD_INCREMENTAL=false

# Clean any stale artifacts and build
RUN cargo clean && cargo build --profile release-labrinth -p labrinth

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates dumb-init curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release-labrinth/labrinth /labrinth/labrinth
COPY --from=builder /app/apps/labrinth/migrations /labrinth/migrations
COPY --from=builder /app/apps/labrinth/assets /labrinth/assets

WORKDIR /labrinth
ENTRYPOINT ["dumb-init", "--"]
CMD ["/labrinth/labrinth"]

EXPOSE 8000
