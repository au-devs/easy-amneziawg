FROM golang:1.25-bookworm AS build

WORKDIR /build

ARG AWG_GO_VERSION=v3.1.20260828
ARG AWG_TOOLS_VERSION=v3.1.20260812

ENV GOTOOLCHAIN=local CGO_ENABLED=0

RUN git clone --branch "${AWG_GO_VERSION}" --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-go && \
    make -C amneziawg-go && \
    install -D -m 0755 amneziawg-go/amneziawg-go /out/amneziawg-go

RUN git clone --branch "${AWG_TOOLS_VERSION}" --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-tools && \
    make -C amneziawg-tools/src && \
    install -m 0755 amneziawg-tools/src/wg /out/awg && \
    install -m 0755 amneziawg-tools/src/wg-quick/linux.bash /out/awg-quick

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl iproute2 iptables qrencode && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /out/ /usr/local/bin/
RUN ln -s /usr/local/bin/awg /usr/local/bin/wg && \
    ln -s /usr/local/bin/awg-quick /usr/local/bin/wg-quick

COPY awg_manage /usr/local/bin/awg_manage
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/awg_manage /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
