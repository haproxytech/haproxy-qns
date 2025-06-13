ARG SSLLIB=QuicTLS-1.1.1

FROM ubuntu:20.04 AS builder-ssl
ARG SSLLIB

# combined list of dependencies for QuicTLS, AWS-LC
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && apt-get -y install git g++ make gcc wget autoconf libtool cmake curl libasan5

# AWS-LC requirement
COPY --from=golang:latest /usr/local/go/ /usr/local/go/
ENV PATH="/usr/local/go/bin:${PATH}"

RUN if [ "$SSLLIB" = "QuicTLS-1.1.1" ]; \
      then git clone --depth 1 -b OpenSSL_1_1_1s+quic https://github.com/quictls/openssl.git && cd /openssl && ./config && make -j$(nproc) && make install_sw; \
      elif [ "$SSLLIB" = "QuicTLS" ]; \
      then git clone --depth 1 https://github.com/quictls/quictls.git openssl && cd /openssl && ./config --libdir=lib && make -j$(nproc) && make install_sw; \
      elif [ "$SSLLIB" = "AWS-LC" ]; \
      then git clone https://github.com/aws/aws-lc && cd aws-lc && cmake -DBUILD_SHARED_LIBS=1 -B build && make -C build && make -C build install; \
      elif [ "$SSLLIB" = "LibreSSL" ]; \
      then git clone https://github.com/libressl/portable.git libressl && cd /libressl && ./autogen.sh && autoreconf -fvi && ./configure && make && make install; \
      else echo "not supported SSLLIB"; exit 1; \
    fi

FROM ubuntu:20.04 AS builder
ARG SSLLIB

COPY --from=builder-ssl /usr/local/include/openssl/ /usr/local/include/openssl/
COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/

ADD *.patch /tmp/
ADD https://api.github.com/repos/haproxy/haproxy/git/refs/heads/quic-interop version.json
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && apt-get -y install git make gcc liblua5.3-0 liblua5.3-dev \
  && git clone --depth 1 -b quic-interop https://github.com/haproxy/haproxy.git haproxy \
  && cd /haproxy \
  && patch -p1 < /tmp/0001-Add-timestamps-to-stderr-sink.patch \
  && make -j $(nproc) \
    CC=gcc \
    TARGET=linux-glibc \
    CPU=generic \
    $(if [ "$SSLLIB" = "QuicTLS" ] || [ "$SSLLIB" = "QuicTLS-1.1.1" ]; then echo USE_OPENSSL=1; elif [ "$SSLLIB" = "LibreSSL" ]; then echo USE_OPENSSL=1; elif [ "$SSLLIB" = "AWS-LC" ]; then echo USE_OPENSSL_AWSLC=1; else echo "not supported SSLLIB"; exit 1; fi) \
    USE_QUIC=1 \
    SSL_INC=/usr/local/include/ \
    SSL_LIB=/usr/local/lib/ \
    SMALL_OPTS="" \
    CPU_CFLAGS.generic="-O0" \
    ARCH_FLAGS="-g -Wno-deprecated-declarations -fsanitize=address" \
    ERR=1 \
    DEBUG="-DDEBUG_DONT_SHARE_POOLS -DDEBUG_MEMORY_POOLS -DDEBUG_STRICT=2 -DDEBUG_TASK -DDEBUG_FAIL_ALLOC" \
    LDFLAGS="-fuse-ld=gold -fsanitize=address" \
    ARCH_FLAGS="-pg" \
    USE_LUA=1 LUA_LIB_NAME=lua5.3 \
    IGNOREGIT=1 VERSION=$(git log -1 --pretty=format:%H) \
  && make install

FROM martenseemann/quic-network-simulator-endpoint:latest
ARG SSLLIB

# Required for lighttpd
ENV TZ=Europe/Paris
RUN echo $TZ > /etc/timezone && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
RUN apt-get -y update && apt-get -y install lighttpd liblua5.3-0 libasan5 && rm -rf /var/lib/apt/lists/*

COPY --from=builder-ssl \
  /usr/local/lib/libssl.so* /usr/local/lib/libcrypto.so* /usr/local/lib/
COPY --from=builder /usr/local/sbin/haproxy /usr/local/sbin/
COPY quic.cfg quic-libressl.cfg lighttpd.cfg /
COPY sslkeylogger.lua /

RUN if [ "$SSLLIB" = "LibreSSL" ]; \
      then mv /quic-libressl.cfg /quic.cfg; \
    fi

COPY run_endpoint.sh .
RUN chmod +x run_endpoint.sh

STOPSIGNAL SIGUSR1

ENTRYPOINT [ "/run_endpoint.sh" ]
