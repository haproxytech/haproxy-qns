FROM ubuntu:20.04 AS builder-ssl

RUN apt-get -y update && apt-get -y install git make gcc

RUN git clone --depth 1 -b OpenSSL_1_1_1l+quic https://github.com/quictls/openssl.git
RUN cd /openssl && ./config enable-tls1_3 && make -j$(nproc) && make install

FROM ubuntu:20.04 AS builder

COPY --from=builder-ssl /usr/local/include/openssl/ /usr/local/include/openssl/
COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/

ADD https://api.github.com/repos/haproxytech/quic-dev/git/refs/heads/qns version.json
RUN apt-get -y update && apt-get -y install git make gcc \
  && git clone -b qns https://github.com/haproxytech/quic-dev.git haproxy \
  && cd /haproxy && make -j $(nproc) \
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
    DEFINE="-DDEBUG_FULL -DDEBUG_DONT_SHARE_POOLS -DDEBUG_MEMORY_POOLS -DDEBUG_STRICT -DDEBUG_TASK -DDEBUG_FAIL_ALLOC" \
    LDFLAGS="-fuse-ld=gold" \
    ARCH_FLAGS="-pg" \
    USE_TFO=1 \
  && make install

FROM martenseemann/quic-network-simulator-endpoint:latest

RUN apt-get -y update && apt-get -y install python3 && rm -rf /var/lib/apt/lists/*

COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/
COPY --from=builder /usr/local/sbin/haproxy /usr/local/sbin/
COPY quic.cfg /

COPY run_endpoint.sh .
RUN chmod +x run_endpoint.sh

STOPSIGNAL SIGUSR1

ENTRYPOINT [ "./run_endpoint.sh" ]
