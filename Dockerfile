ARG PROTOCOL_BUFFERS_VERSION="3.18.0"

ARG COMPOSE_VERSION="1.29.2"

ARG JAVA_VERSION=11

ARG LLVM_VERSION=11

ARG COMPOSE_VERSION="1.28.4"

# https://github.com/erlang/otp/releases
ARG OTP_VERSION="23.2.6"
ARG OTP_DOWNLOAD_URL="https://github.com/erlang/otp/archive/OTP-${OTP_VERSION}.tar.gz"
# by manual in docker `cuel -sSLo ${OTP_VERSION}.tar.gz https://github.com/elixir-lang/elixir/archive/${OTP_VERSION}.tar.gz && sha256sum ${OTP_VERSION}.tar.gz`
ARG OTP_DOWNLOAD_SHA256="5bc6b31b36b949bf06e84d51986311fc1d2ace5e717aae3186dc057d4838445d"

# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION="v1.11.3"
ARG ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz"
# by manual in docker `cuel -sSLo ${ELIXIR_VERSION}.tar.gz https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz && sha256sum ${ELIXIR_VERSION}.tar.gz`
ARG ELIXIR_DOWNLOAD_SHA256="d961305e893f4fe1a177fa00233762c34598bc62ff88b32dcee8af27e36f0564"

ARG BASE=erlang:23

FROM buildpack-deps:stable-curl AS download

ARG PROTOCOL_BUFFERS_VERSION

ARG LLVM_VERSION

ARG OTP_DOWNLOAD_URL
ARG OTP_DOWNLOAD_SHA256

ARG ELIXIR_VERSION
ARG ELIXIR_DOWNLOAD_URL
ARG ELIXIR_DOWNLOAD_SHA256

WORKDIR /tmp

RUN curl -sSLo /tmp/llvm-snapshot.gpg.key https://apt.llvm.org/llvm-snapshot.gpg.key \
 && curl -sSLo /tmp/protobuf-all-${PROTOCOL_BUFFERS_VERSION}.tar.gz https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOCOL_BUFFERS_VERSION}/protobuf-all-${PROTOCOL_BUFFERS_VERSION}.tar.gz \
 && tar xf protobuf-all-${PROTOCOL_BUFFERS_VERSION}.tar.gz \
 && rm -f tar xf protobuf-all-${PROTOCOL_BUFFERS_VERSION}.tar.gz \
 && mv /tmp/protobuf-${PROTOCOL_BUFFERS_VERSION} /tmp/protobuf \
 && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > /tmp/rustup-init.sh \
 && curl -fsSL -o elixir-src.tar.gz ${ELIXIR_DOWNLOAD_URL} \
 && echo "${ELIXIR_DOWNLOAD_SHA256}  elixir-src.tar.gz" | sha256sum -c - \
 && mkdir -p /usr/local/src/elixir \
 && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
 && rm elixir-src.tar.gz \
 && curl -fSL -o /tmp/otp-src.tar.gz ${OTP_DOWNLOAD_URL} \
 && echo "${OTP_DOWNLOAD_SHA256}  /tmp/otp-src.tar.gz" | sha256sum -c - \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker-archive-keyring.gpg.key


FROM debian:buster-slim AS default

ENV LANG=C.UTF-8

ARG PROTOCOL_BUFFERS_VERSION
ARG LLVM_VERSION

ARG JAVA_VERSION

COPY --from=download /tmp/llvm-snapshot.gpg.key /tmp/llvm-snapshot.gpg.key
COPY --from=download /tmp/docker-archive-keyring.gpg.key /tmp/docker-archive-keyring.gpg.key

WORKDIR /tmp

ARG buildDeps=' \
        autoconf \
        apt-transport-https \
        ca-certificates \
        curl \
        dpkg-dev \
        gcc \
        gnupg \
        g++ \
        make \
        libncurses-dev \
        lsb-release \
        unixodbc-dev \
        libssl-dev \
        libsctp-dev'

RUN mkdir -p /usr/share/man/man1/ \
 && apt-get update -qq \
 && apt-get install --no-install-recommends -qqy lsb-release ca-certificates gnupg2 binutils apt-utils \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
 && cat /tmp/docker-archive-keyring.gpg.key | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
 && apt-get update -qq \
 && cat /tmp/llvm-snapshot.gpg.key | apt-key add - \
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9 \
 && DISTRIBUTION=$(cat /etc/os-release | grep ^ID= | cut -d "=" -f2) \
 && echo "deb http://repos.azulsystems.com/${DISTRIBUTION} stable main" >> /etc/apt/sources.list.d/zulu.list \
 && cat /etc/apt/sources.list.d/zulu.list \
 && echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-${LLVM_VERSION} main" >> /etc/apt/sources.list.d/llvm-toolchain.list \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends \
        automake \
        libtool \
        clang-${LLVM_VERSION} \
        lld-${LLVM_VERSION} \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        unzip \
        zlib1g-dev \
        pkg-config \
        unzip \
        git \
        cmake \
        golang \
        libpq-dev \
        libodbc1 \
        libssl1.1 \
        libsctp1 \
        curl \
        python3 \
        python3-dev \
        zulu-repo \
        ${buildDeps} \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends \
        zulu${JAVA_VERSION}-ca-jdk-headless \
 && apt-get clean \
 && curl https://bootstrap.pypa.io/get-pip.py | python3 \
 && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/alternatives.log /var/log/dpkg.log /var/log/faillog /var/log/lastlog


COPY --from=download /tmp/rustup-init.sh /tmp/rustup-init.sh
RUN chmod +x /tmp/rustup-init.sh \
 && /tmp/rustup-init.sh -y \
 && rm -rf /var/lib/apt/lists/* /tmp/rustup-init.sh


COPY --from=download /tmp/otp-src.tar.gz /tmp/otp-src.tar.gz
RUN export ERL_TOP=/usr/src/otp_src_"${OTP_VERSION%%@*}" \
 && mkdir -vp "${ERL_TOP}" \
 && tar -xzf /tmp/otp-src.tar.gz -C "${ERL_TOP}" --strip-components=1 \
 && rm otp-src.tar.gz \
 && ( cd "${ERL_TOP}" \
    && ./otp_build autoconf \
    && gnuArch="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
    && ./configure --build="$gnuArch" \
    && make -j$(nproc) \
    && make install ) \
 && find /usr/local -name examples | xargs rm -rf \
 && rm -rf "${ERL_TOP}" /var/lib/apt/lists/* 

ENV PATH="/github/home/.mix/escripts:/root/.mix/escripts:${PATH}"

COPY --from=download /tmp/protobuf /tmp/protobuf
WORKDIR /tmp/protobuf 
RUN ./autogen.sh \
 && ./configure --prefix=/usr \
 && make \
 && make check \
 && make install \
 && ldconfig \
 && rm -rf /tmp/protobuf /var/lib/apt/lists/* 

COPY --from=download /usr/local/src/elixir /usr/local/src/elixir
WORKDIR /usr/local/src/elixir
RUN make install clean \
 && rm -rf /var/lib/apt/lists/* /usr/local/src/elixir /tmp/*

ENV PATH="/root/.cargo/bin/:/github/home/.mix/escripts:/root/.mix/escripts:${PATH}"
RUN cargo install protobuf-codegen grpcio-compiler grpc-compiler

WORKDIR /root

FROM default as compose

ARG COMPOSE_VERSION

RUN curl -sSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
 && chmod +x /usr/local/bin/docker-compose
