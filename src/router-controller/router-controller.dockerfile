FROM rust:1.82.0-bullseye AS router-controller-builder
WORKDIR /app
COPY src/router-controller/crates/llm-router-gateway-api .

# Run as root and remove rustup
USER root
RUN rm -rf /usr/local/cargo/bin/rustup || true

# Patch Tokio and update dependencies
# RUN sed -i 's/tokio = .*}/tokio = { version = "1.46", features = ["full"] }/' Cargo.toml || true
RUN cargo update

ENV RUST_BACKTRACE=full
ENV CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=true
SHELL ["/bin/bash", "-c"]
RUN ulimit -u 65535 && cargo build --release --no-default-features
# RUN cargo build --release

FROM nvcr.io/nvidia/base/ubuntu:22.04_20240212
# RUN apt-get update && apt-get install -y curl jq ca-certificates
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl jq ca-certificates && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true
COPY --from=router-controller-builder /app/target/release/llm-router-gateway-api /usr/local/bin/
RUN mkdir -p /app
WORKDIR /app
COPY src/router-controller/config.yaml /app/config.yaml
ENV RUST_LOG=info

ENTRYPOINT ["llm-router-gateway-api"]
CMD ["--config-path", "/app/config.yaml"]
