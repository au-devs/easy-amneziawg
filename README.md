# easy-amnezia

Self-hosted, DPI-resistant VPN based on **AmneziaWG** (an obfuscated WireGuard fork),
packaged to run entirely in Docker in **userspace** — no kernel module, no DKMS, no host
changes beyond Docker itself. Drop the folder on any Linux server with Docker and run one
command.

AmneziaWG hides the fixed WireGuard packet signature (headers, handshake sizes) that Deep
Packet Inspection systems fingerprint, while keeping WireGuard's cryptography and speed. This
is useful where plain WireGuard is throttled or blocked.

## Features

- Runs AmneziaWG via `amneziawg-go` (userspace) — works on any host kernel, no module to build.
- Obfuscation parameters are generated uniquely on first start (no shared DPI signature).
- One-command bring-up; server keys and config auto-generated on first run.
- Simple client management with QR output (`client-add.sh`, `client-qr.sh`, ...).
- Public IP auto-detected on first start (override for NAT setups).
- Full-tunnel by default, with private/LAN subnets excluded from the tunnel out of the box.
- Persistent state in a bind-mounted `data/` directory.

## Requirements

- A Linux server with a public IP and Docker + Docker Compose v2.
- The container needs `NET_ADMIN` and `/dev/net/tun` (already set in the compose file).
- The VPN UDP port reachable from the internet (default `60686`) — open it in your
  provider's firewall / security group.
- An **AmneziaWG-compatible client** on your devices (see below). Plain WireGuard clients
  will NOT connect — they don't understand the obfuscation parameters.

## Quick start

```bash
cd easy-amnezia
docker compose up -d --build      # first build compiles amneziawg-go, ~2-4 min
docker logs amneziawg             # shows the server public key and interface status
```

Then add your first client and get a QR code:

```bash
./client-add.sh phone
```

Scan the QR with the AmneziaWG app, or grab the saved config from `clients/phone.conf`.

## Client management

All scripts wrap `awg_manage` inside the container.

| Command | Description |
|---|---|
| `./client-add.sh <name>` | Create a client, save `clients/<name>.conf`, print its QR code |
| `./client-qr.sh <name>` | Print the QR code for an existing client |
| `./client-list.sh` | List existing clients |
| `./client-rm.sh <name> [-y]` | Remove a client (`-y` skips the confirmation prompt) |

Each client gets its own key pair, preshared key, and tunnel IP (`10.8.1.2`, `10.8.1.3`, ...).
Saved `clients/*.conf` files are written by your user (readable), unlike a raw `docker cp`.

### Pulling client configs to your machine

`fetch-clients.sh` downloads client configs from a server by name mask and stores them
locally (files are `chmod 600`, owned by you). Run it from your workstation, not the server.

```bash
./fetch-clients.sh <ssh-host> [mask] [dest-dir]

./fetch-clients.sh lit-vps 'utsg-*'          # only utsg-* clients
./fetch-clients.sh lit-vps 'mila-*' ./mila   # mila-* into ./mila
./fetch-clients.sh pol-vps                    # all clients (mask defaults to *)
```

Quote the mask so your shell doesn't expand `*` against local files. The default destination
is `./amneziawg-clients/<host>/`. Override the container name with `CONTAINER=... ./fetch-clients.sh ...`.

## Configuration

Edit the `environment:` block in `docker-compose.yml`. All values are optional.

| Variable | Default | Description |
|---|---|---|
| `WG_ADDRESS` | `10.8.1.1/24` | Server interface address / VPN subnet |
| `WG_PORT` | `60686` | UDP listen port (also update the `ports:` mapping if changed) |
| `VPN_PUBLIC_IP` | auto-detected | Public IP written into client `Endpoint`; set explicitly behind NAT |
| `CLIENT_DNS` | `1.1.1.1, 8.8.8.8` | DNS servers pushed to clients |
| `CLIENT_MTU` | `1280` | Client MTU; conservative value that survives most mobile/DPI networks |
| `CLIENT_EXCLUDE_NETS` | RFC1918 + CGNAT + link-local + multicast | Networks kept off the tunnel; set empty for a plain full tunnel |
| `CLIENT_ALLOWED_IPS` | computed | Verbatim `AllowedIPs`; overrides `CLIENT_EXCLUDE_NETS` |

### Split tunnel / excluded networks

Client `AllowedIPs` is generated as `0.0.0.0/0` **minus** `CLIENT_EXCLUDE_NETS`, so LAN
resources (router, NAS, printer, corporate subnets) stay reachable directly instead of being
sent through the VPN. The default exclusion list is:

```
10.0.0.0/8  172.16.0.0/12  192.168.0.0/16  169.254.0.0/16  100.64.0.0/10  224.0.0.0/3
```

The VPN subnet itself is always added back, so the server and other peers remain reachable
through the tunnel. To get the old behaviour, set `CLIENT_EXCLUDE_NETS=` (empty) or
`CLIENT_ALLOWED_IPS=0.0.0.0/0`.

Both variables are read at client-creation time, so changing them takes effect on the next
`./client-add.sh` — no need to wipe `data/`.

```bash
docker exec amneziawg awg_manage --showallowedips     # preview the computed list
docker exec amneziawg awg_manage --updateallowedips   # rewrite it in all existing clients
```

`--updateallowedips` only touches the client-side config (keys and peers are untouched), so
re-fetch the configs afterwards (`./fetch-clients.sh` / `client-qr.sh`) and re-import them on
the devices.

Obfuscation parameters (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1`–`H4`) are generated on first
start and stored in `data/client_params.env`. You may pin them via the same `environment:`
block, but the defaults are sound — leave them auto-generated so each server has a unique
signature. Server and client must use the same `S1/S2/H1–H4`; the client scripts handle this
automatically.

## Client apps

Use an official **AmneziaWG** client (not plain WireGuard):

- Android / iOS / macOS / Windows: AmneziaWG or Amnezia VPN
- Linux: `amneziawg-tools`

## Deploying to another server

The folder is self-contained. Copy everything **except** `data/` and `clients/` (those are
per-server: keys, obfuscation params, and issued clients).

```bash
rsync -av --exclude data --exclude clients ./easy-amnezia/ new-server:/opt/easy-amnezia/
ssh new-server 'cd /opt/easy-amnezia && docker compose up -d --build'
```

On the new server the public IP is auto-detected and fresh obfuscation parameters are
generated. Open the UDP port in the provider firewall. Clients from one server do NOT work
against another.

To avoid rebuilding on every server, build once and push the image to a registry, then
replace `build: .` with `image: <your-registry>/amneziawg` in `docker-compose.yml`.

## Backup

Back up the `data/` directory — it holds the server keys, obfuscation parameters, and all
issued client configs. It is enough to restore an instance on the same IP and port.

## Troubleshooting

- **No internet after connecting, but handshake succeeds** — check `awg show` for a recent
  handshake and non-zero transfer; if present, the issue is NAT/MTU. Lower `CLIENT_MTU`
  (e.g. `1280` -> `1200`) and re-create the client.
- **No handshake at all** — UDP packets aren't reaching the server. Confirm the UDP port is
  open in the provider firewall, and try switching the client's network (mobile <-> Wi-Fi).
- **Client won't import / connects but drops** — make sure you are using an AmneziaWG client,
  not plain WireGuard.
- **Inspect state:**
  ```bash
  docker logs amneziawg
  docker exec amneziawg awg show
  ```

## How it works

- The image builds `amneziawg-go` and `amneziawg-tools` (providing `awg` / `awg-quick`).
- On first start, `entrypoint.sh` generates the server key pair and obfuscation parameters,
  writes `wg0.conf`, brings the interface up in userspace, and configures NAT/forwarding
  (MASQUERADE for the VPN subnet on the default egress interface).
- `awg_manage` (baked into the image) handles client add/list/show/remove; the `client-*.sh`
  wrappers call it over `docker exec`.

## Pinned versions

- `amneziawg-go` `v3.0.2`
- `amneziawg-tools` `v1.0.20260618-2`
- Base image `ubuntu:24.04`

Change the `ARG` values in the `Dockerfile` to upgrade.

## Notes and limitations

- Userspace AmneziaWG is slightly slower than the kernel module, but fully functional and
  requires no host changes. For maximum throughput, install the AmneziaWG kernel module on the
  host and adapt the setup accordingly.
- IPv6 is not configured; clients get IPv4-only `AllowedIPs` to avoid an IPv6 black-hole when
  the server has no public IPv6.
- This project bundles only wrapper scripts and configuration. AmneziaWG and its tools are
  subject to their own upstream licenses.
