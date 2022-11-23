FROM ubuntu:20.04 AS builder-ssl

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && apt-get -y install git make gcc

RUN git clone --depth 1 -b OpenSSL_1_1_1s+quic https://github.com/quictls/openssl.git
RUN cd /openssl && ./config && make -j$(nproc) && make install_sw

FROM ubuntu:20.04 AS builder

COPY --from=builder-ssl /usr/local/include/openssl/ /usr/local/include/openssl/
COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/

ADD *.patch /tmp/
ADD https://api.github.com/repos/haproxytech/quic-dev/git/refs/heads/qns version.json
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && apt-get -y install git make gcc \
  && git clone --depth 1 -b qns https://github.com/haproxytech/quic-dev.git haproxy \
  && cd /haproxy \
  && patch -p1 < /tmp/0001-MINOR-quic-activate-QUIC-traces-at-compilation.patch \
  && patch -p1 < /tmp/0002-MINOR-mux-quic-activate-qmux-traces-on-stdout-via-ma.patch \
  && make -j $(nproc) \
    CC=gcc \
    TARGET=linux-glibc \
    CPU=generic \
    USE_OPENSSL=1 \
    USE_QUIC=1 \
    SSL_INC=/usr/local/include/ \
    SSL_LIB=/usr/local/lib/ \
    SMALL_OPTS="" \
    CPU_CFLAGS.generic="-O0" \
    DEBUG_CFLAGS="-g -Wno-deprecated-declarations" \
    ERR=1 \
    DEBUG="-DDEBUG_DONT_SHARE_POOLS -DDEBUG_MEMORY_POOLS -DDEBUG_STRICT=2 -DDEBUG_TASK -DDEBUG_FAIL_ALLOC" \
    SILENT_DEFINE="-DENABLE_QUIC_STDOUT_TRACES" \
    LDFLAGS="-fuse-ld=gold" \
    ARCH_FLAGS="-pg" \
    IGNOREGIT=1 VERSION=$(git log -1 --pretty=format:%H) \
  && make install

FROM martenseemann/quic-network-simulator-endpoint:latest

# Required for lighttpd
ENV TZ=Europe/Paris
RUN echo $TZ > /etc/timezone && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
RUN apt-get -y update && apt-get -y install lighttpd && rm -rf /var/lib/apt/lists/*

COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/
COPY --from=builder /usr/local/sbin/haproxy /usr/local/sbin/
COPY quic.cfg lighttpd.cfg /

COPY run_endpoint.sh .
RUN chmod +x run_endpoint.sh

STOPSIGNAL SIGUSR1

ENTRYPOINT [ "/run_endpoint.sh" ]
