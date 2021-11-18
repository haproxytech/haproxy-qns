FROM martenseemann/quic-network-simulator-endpoint:latest

RUN apt -y update && apt -y install git make gcc python3

RUN git clone --depth 1 -b OpenSSL_1_1_1l+quic https://github.com/quictls/openssl.git
RUN cd /openssl && ./config enable-tls1_3 && make -j$(nproc) && make install

ADD https://api.github.com/repos/haproxytech/quic-dev/git/refs/heads/qns version.json
RUN git clone -b qns https://github.com/haproxytech/quic-dev.git haproxy
RUN cd /haproxy && make -j $(nproc) \
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
  USE_TFO=1

COPY quic.cfg /

COPY run_endpoint.sh .
RUN chmod +x run_endpoint.sh

STOPSIGNAL SIGUSR1

ENTRYPOINT [ "./run_endpoint.sh" ]
