#!/bin/bash
set -eo pipefail

CONFIG_DIR="/opt/amnezia/awg"
CONF="${CONFIG_DIR}/wg0.conf"
PARAMS="${CONFIG_DIR}/client_params.env"

export WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
export WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1
export PATH="/usr/local/bin:${PATH}"

umask 077
mkdir -p "${CONFIG_DIR}/clients"

WG_ADDRESS="${WG_ADDRESS:-10.8.1.1/24}"
WG_PORT="${WG_PORT:-51820}"
VPN_PUBLIC_IP="${VPN_PUBLIC_IP:-}"
CLIENT_DNS="${CLIENT_DNS:-1.1.1.1, 8.8.8.8}"
CLIENT_MTU="${CLIENT_MTU:-1280}"

if [ -z "${VPN_PUBLIC_IP}" ]; then
  VPN_PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null \
    || curl -fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null || true)"
fi

if [ ! -f "${CONF}" ]; then
  echo "First run: generating server keys and obfuscated config..."
  SERVER_PRIV="$(awg genkey)"
  SERVER_PUB="$(printf '%s' "${SERVER_PRIV}" | awg pubkey)"
  printf '%s\n' "${SERVER_PUB}" > "${CONFIG_DIR}/server_public.key"

  # AmneziaWG obfuscation parameters (1.0 profile, broadly client-compatible).
  # Jc/Jmin/Jmax: junk-packet train. S1/S2: init/response size prefixes.
  # H1..H4: dynamic header magics, must be distinct and match on the client.
  Jc="${Jc:-4}"; Jmin="${Jmin:-40}"; Jmax="${Jmax:-70}"
  S1="${S1:-66}"; S2="${S2:-57}"
  H1="${H1:-$(( RANDOM*RANDOM % 500000000 + 1 ))}"
  H2="${H2:-$(( RANDOM*RANDOM % 500000000 + 500000000 ))}"
  H3="${H3:-$(( RANDOM*RANDOM % 500000000 + 1000000000 ))}"
  H4="${H4:-$(( RANDOM*RANDOM % 500000000 + 1500000000 ))}"

  cat > "${CONF}" <<EOF
[Interface]
PrivateKey = ${SERVER_PRIV}
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
Jc = ${Jc}
Jmin = ${Jmin}
Jmax = ${Jmax}
S1 = ${S1}
S2 = ${S2}
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}
EOF
  chmod 600 "${CONF}"

  cat > "${PARAMS}" <<EOF
SERVER_PUB='${SERVER_PUB}'
VPN_PUBLIC_IP='${VPN_PUBLIC_IP}'
WG_PORT='${WG_PORT}'
WG_SUBNET_BASE='$(printf '%s' "${WG_ADDRESS}" | cut -d/ -f1 | sed 's/\.[0-9]*$//')'
CLIENT_DNS='${CLIENT_DNS}'
CLIENT_MTU='${CLIENT_MTU}'
Jc='${Jc}'
Jmin='${Jmin}'
Jmax='${Jmax}'
S1='${S1}'
S2='${S2}'
H1='${H1}'
H2='${H2}'
H3='${H3}'
H4='${H4}'
EOF
  chmod 600 "${PARAMS}"
  echo "Server public key: ${SERVER_PUB}"
fi

# (Re)bring up the interface via userspace amneziawg-go
awg-quick down "${CONF}" >/dev/null 2>&1 || true
awg-quick up "${CONF}"

# NAT / forwarding for the VPN subnet
NET_IFACE="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
NET_IFACE="${NET_IFACE:-eth0}"
SUBNET="$(awk -F'= *' '/^Address/{print $2}' "${CONF}" | cut -d/ -f1 | sed 's/\.[0-9]*$/.0/')/24"

iptables -t nat -C POSTROUTING -s "${SUBNET}" -o "${NET_IFACE}" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "${SUBNET}" -o "${NET_IFACE}" -j MASQUERADE
iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT
iptables -C FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -C INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT

echo "AmneziaWG up on UDP/${WG_PORT}, NAT via ${NET_IFACE} for ${SUBNET}."
awg show || true

exec tail -f /dev/null
