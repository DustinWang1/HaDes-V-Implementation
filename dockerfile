# HaDes-V build image (Ubuntu 24.04)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/riscv32i/bin:/usr/local/bin:/usr/bin:/bin

# Base tools & build deps (git, make, compilers, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates curl wget \
    pkg-config autoconf automake libtool \
    g++ make cmake ninja-build \
    # Verilator deps per guide
    libfl-dev help2man \
    # RISC-V toolchain deps per guide
    texinfo zlib1g-dev libexpat-dev libgmp-dev \
    # Helpful extras commonly needed by the toolchain build
    libmpc-dev libmpfr-dev gawk bison flex python3 \
    # Wave viewer (per guide)
    gtkwave \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# ---------- Build & install Verilator v5.006 ----------
RUN git clone --branch v5.006 https://github.com/verilator/verilator && \
    cd verilator && \
    autoconf && \
    ./configure && \
    make -j"$(nproc)" && \
    make install && \
    cd /opt && rm -rf verilator

# ---------- Build RV32I GNU toolchain (2023.01.31) ----------
# Installs to /opt/riscv32i (as in the guide)
RUN git clone --branch 2023.01.31 https://github.com/riscv-collab/riscv-gnu-toolchain.git && \
    cd riscv-gnu-toolchain && \
    ./configure --with-arch=rv32i --prefix=/opt/riscv32i && \
    make -j"$(nproc)" && \
    cd /opt && rm -rf riscv-gnu-toolchain

# Workspace for your repo
WORKDIR /workspace

# Default shell
CMD ["/bin/bash"]
