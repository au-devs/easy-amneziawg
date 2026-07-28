FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git make gcc build-essential pkg-config \
      iproute2 iptables qrencode golang-go && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

ARG AWG_GO_VERSION=v3.0.2
ARG AWG_TOOLS_VERSION=v1.0.20260618-2

RUN git clone --branch "${AWG_GO_VERSION}" --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-go && \
    cd amneziawg-go && \
    make && \
    install -m 0755 amneziawg-go /usr/local/bin/amneziawg-go

RUN git clone --branch "${AWG_TOOLS_VERSION}" --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-tools && \
    cd amneziawg-tools/src && \
    make && \
    make install PREFIX=/usr/local

RUN ln -s /usr/local/bin/awg /usr/local/bin/wg && \
    ln -s /usr/local/bin/awg-quick /usr/local/bin/wg-quick

COPY awg_manage /usr/local/bin/awg_manage
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/awg_manage /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
