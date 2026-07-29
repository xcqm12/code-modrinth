FROM rust:1.85-slim-bookworm AS chef
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev libclang-dev clang lld \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install cargo-chef

WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

COPY . .
RUN cargo build -p labrinth --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates dumb-init curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/labrinth /labrinth/labrinth
COPY apps/labrinth/migrations /labrinth/migrations
COPY apps/labrinth/assets /labrinth/assets

WORKDIR /labrinth
ENTRYPOINT ["dumb-init", "--"]
CMD ["/labrinth/labrinth"]

EXPOSE 8000
