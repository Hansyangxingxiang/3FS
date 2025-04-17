FROM ubuntu:20.04 as builder

RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    curl \
    pkg-config \
    libfuse3-dev \
    fuse3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app
COPY . .

RUN cargo build --release --bin fuse_client

FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    fuse3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/fuse_client /usr/local/bin/

RUN chmod +x /usr/local/bin/fuse_client
VOLUME /mnt/fuse

CMD ["fuse_client", "--mount-point=/mnt/fuse"]
