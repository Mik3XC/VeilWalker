FROM rust:1-bookworm AS build
WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends tor ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/trailbound-api /usr/local/bin/trailbound-api
COPY deploy/torrc /etc/tor/torrc
COPY deploy/start.sh /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/start.sh"]
