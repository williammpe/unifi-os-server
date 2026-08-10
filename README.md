# UniFi OS Server on Docker

![Docker](https://img.shields.io/badge/docker-ready-blue)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos-green)
![Status](https://img.shields.io/badge/status-working-success)

Run **UniFi OS Server** inside a Docker container using the official firmware distributed by Ubiquiti.

The build is fully self-contained inside the `Dockerfile`: it downloads the
official installer, extracts the embedded OCI image with `binwalk`, flattens
its layers into a rootfs, and layers a custom entrypoint on top. No manual
extraction on the host is required — `setup.sh` only orchestrates
`docker compose build` + `docker compose up -d`.

Compatible with Linux and macOS hosts (amd64/arm64).

---

# Features

✔ Uses **official firmware**, extracted entirely inside the Docker build
✔ Full persistent storage (UniFi config + external MongoDB)
✔ Automatic firmware download & extraction (no host `binwalk`/`sudo` needed)
✔ Simple one-command install
✔ macvlan `eth0` alias, PostgreSQL exposure, journal forwarding to `docker logs`
✔ Optional direct Network App access, bypassing UOS SSO (debug only)

Runs the complete **UniFi OS environment**, including the **UniFi Network Application**.

---

# Requirements

Install:

* Docker
* Docker Compose

```
sudo apt install docker.io docker-compose-plugin
```

`binwalk`/`jq`/`p7zip` run **inside** the build stage — you don't need them on the host.

---

# Project Structure

```
.
├── .env
├── example.env
├── docker-compose.yaml
├── Dockerfile
├── setup.sh
├── uos-entrypoint.sh
├── site-localhost-bypass.conf
├── .gitignore
└── volume-data/            # created at runtime (persistent data)
```

---

# Configuration

Copy the example configuration:

```
cp example.env .env
```

Edit `.env`:

```
UOS_SERVER_VERSION=5.0.6

INSTALLER_URL_AMD64=https://fw-download.ubnt.com/data/unifi-os-server/...
INSTALLER_URL_ARM64=

UOS_SYSTEM_IP=203.0.113.10      # public/host IP used by UniFi (required)

TZ=America/Sao_Paulo
EXPOSE_NETWORK_APP=false        # true = bypass SSO on 127.0.0.1:7443 (debug only)
MONGO_INTERNAL=false            # false = use the external MongoDB service

DATA_PATH=./volume-data
```

---

# Install

Run the setup script:

```
./setup.sh
```

This will:

1. build the image (download firmware + extract system image, all inside Docker)
2. create the persistent volume folders
3. start the containers (`unifi-os-server` + `unifi-os-server-mongodb`)

---

# Access UniFi

After startup:

```
https://localhost:11443
```

or

```
https://SERVER_IP:11443
```

---

# Ports

| Port             | Service                              |
| ---------------- | ------------------------------------- |
| 11443            | UniFi OS Web UI                       |
| 8443              | UniFi Controller API                  |
| 8444              | Secure Portal (Hotspot)               |
| 8080              | Device Inform / HTTP redirect         |
| 8880-8882         | Hotspot portal redirection (HTTP)     |
| 3478/udp          | STUN                                  |
| 10001/udp, 10003/udp | Discovery                          |
| 5514/udp          | Syslog                                |
| 6789              | Speed test                            |
| 127.0.0.1:7443    | Network App bypass (debug, SSO-free)  |
| 127.0.0.1:5432    | PostgreSQL (localhost only)           |

---

# Persistent Data

All data is stored inside `DATA_PATH`:

```
volume-data
├── uos           # UniFi config, certs, users (/var/lib/unifi)
├── data           # UOS core data (/data)
└── mongodb        # external MongoDB database
```

---

# Logs

View container logs:

```
docker logs -f unifi-os-server
```

View system logs (forwarded from journald):

```
docker logs -f unifi-os-server
```

---

# Update Version

Edit `.env`:

```
UOS_SERVER_VERSION=NEW_VERSION
INSTALLER_URL_AMD64=NEW_URL
```

Then run:

```
./setup.sh
```

---

# Stop Container

```
docker compose down
```

Persistent data will remain intact.

---

# Troubleshooting

### Build fails downloading the installer

Check `INSTALLER_URL_AMD64`/`INSTALLER_URL_ARM64` in `.env` — they must point
to a valid `fw-download.ubnt.com` installer for your architecture.

---

### Container fails to start

Check logs:

```
docker logs unifi-os-server
```

Make sure `UOS_SYSTEM_IP` is set in `.env`.

---

### Port already in use

Edit `docker-compose.yaml` and change the port mapping.

---

# Disclaimer

This project is **not affiliated with Ubiquiti**.

It only automates usage of publicly available firmware. Build architecture
adapted from [unihosted/unifi-os-server-docker](https://github.com/unihosted/unifi-os-server-docker).

Use at your own risk.

---

# License

MIT
