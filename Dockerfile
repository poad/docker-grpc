ARG PROTOCOL_BUFFERS_VERSION="3.12.3"

ARG GRPC_VERSION="1.30.0"
ARG GRPC_JAVA_VERSION="1.30.1"

ARG COMPOSE_VERSION="1.26.2"

ARG OTP_VERSION="23.0.2"

ARG OTP_DOWNLOAD_URL="https://github.com/erlang/otp/archive/OTP-${OTP_VERSION}.tar.gz"
ARG OTP_DOWNLOAD_SHA256="6bab92d1a1b20cc319cd845c23db3611cc99f8c99a610d117578262e3c108af3"

ARG ELIXIR_VERSION="v1.10.3"
ARG ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz"
ARG ELIXIR_DOWNLOAD_SHA256="f3035fc5fdade35c3592a5fa7c8ee1aadb736f565c46b74b68ed7828b3ee1897"

ARG BASE=erlang:23

FROM buildpack-deps:stable-curl AS download

ARG PROTOCOL_BUFFERS_VERSION

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
 && echo "${OTP_DOWNLOAD_SHA256}  /tmp/otp-src.tar.gz" | sha256sum -c -


FROM debian:buster-slim AS default

ENV LANG=C.UTF-8

ARG PROTOCOL_BUFFERS_VERSION

COPY --from=download /tmp/llvm-snapshot.gpg.key /tmp/llvm-snapshot.gpg.key

WORKDIR /tmp

ARG buildDeps=' \
		autoconf \
		dpkg-dev \
		gcc \
		g++ \
		make \
		libncurses-dev \
		unixodbc-dev \
		libssl-dev \
		libsctp-dev'

RUN mkdir -p /usr/share/man/man1/ \
 && apt-get update -qq \
 && apt-get install --no-install-recommends -qqy ca-certificates gnupg2 binutils apt-utils \
 && cat /tmp/llvm-snapshot.gpg.key | apt-key add - \
 && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9 \
 && DISTRIBUTION=$(cat /etc/os-release | grep ^ID= | cut -d "=" -f2) \
 && echo "deb http://repos.azulsystems.com/${DISTRIBUTION} stable main" >> /etc/apt/sources.list.d/zulu.list \
 && cat /etc/apt/sources.list.d/zulu.list \
 && echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-10 main" >> /etc/apt/sources.list.d/llvm-toolchain.list \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends \
        automake \
        libtool \
        clang-10 \
        lld-10 \
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
        zulu-repo \
        ${buildDeps} \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends \
         zulu-11 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/alternatives.log /var/log/dpkg.log /var/log/faillog /var/log/lastlog


COPY --from=download /tmp/rustup-init.sh /tmp/rustup-init.sh
RUN chmod +x /tmp/rustup-init.sh \
 && /tmp/rustup-init.sh -y \
 && rm -rf /var/lib/apt/lists/* /tmp/rustup-init.sh


COPY --from=download /tmp/otp-src.tar.gz /tmp/otp-src.tar.gz
RUN export ERL_TOP="/usr/src/otp_src_${OTP_VERSION%%@*}" \
 && mkdir -vp ${ERL_TOP} \
 && tar -xzf /tmp/otp-src.tar.gz -C ${ERL_TOP} --strip-components=1 \
 && rm otp-src.tar.gz \
 && ( cd ${ERL_TOP} \
    && ./otp_build autoconf \
    && gnuArch="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
    && ./configure --build="$gnuArch" \
    && make -j$(nproc) \
    && make install ) \
 && find /usr/local -name examples | xargs rm -rf \
 && rm -rf ${ERL_TOP} /var/lib/apt/lists/* 

ENV PARH="/root/.mix/escripts:${PATH}"

COPY --from=download /tmp/protobuf /tmp/protobuf
RUN cd /tmp/protobuf \
 && ./autogen.sh \
 && ./configure --prefix=/usr \
 && make \
 && make check \
 && make install \
 && ldconfig \
 && rm -rf /tmp/protobuf /var/lib/apt/lists/* 

COPY --from=download /usr/local/src/elixir /usr/local/src/elixir
RUN cd /usr/local/src/elixir \
 && make install clean \
 && rm -rf /var/lib/apt/lists/* /usr/local/src/elixir /tmp/*

ENV PATH="/root/.cargo/bin/:${PATH}"
RUN cargo install protobuf-codegen grpcio-compiler grpc-compiler

WORKDIR /root

FROM default as compose

ARG COMPOSE_VERSION

RUN curl -sSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
 && chmod +x /usr/local/bin/docker-compose
