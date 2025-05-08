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
RUN apt-get update && apt-get install -y curl jq ca-certificates build-essential wget
# Manually install OpenSSL 1.1.1
WORKDIR /tmp
RUN wget https://www.openssl.org/source/openssl-1.1.1u.tar.gz && \
    tar xzf openssl-1.1.1u.tar.gz && \
    cd openssl-1.1.1u && \
    ./config --prefix=/opt/openssl-1.1 && \
    make -j"$(nproc)" && \
    make install

# Export runtime linker path
ENV LD_LIBRARY_PATH="/opt/openssl-1.1/lib:$LD_LIBRARY_PATH"
ENV PATH="/opt/openssl-1.1/bin:$PATH"
COPY --from=router-controller-builder /app/target/release/llm-router-gateway-api /usr/local/bin/
RUN mkdir -p /app
WORKDIR /app
COPY src/router-controller/config.yaml /app/config.yaml
ENV RUST_LOG=info

ENTRYPOINT ["llm-router-gateway-api"]
CMD ["--config-path", "/app/config.yaml"]
