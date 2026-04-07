# UniFi OS Server on Docker

![Docker](https://img.shields.io/badge/docker-ready-blue)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos-green)
![Status](https://img.shields.io/badge/status-working-success)

Run **UniFi OS Server** inside a Docker container using the official firmware distributed by Ubiquiti.

This project automatically:

* downloads the official firmware
* extracts the internal system image
* imports it into Docker
* launches a fully functional UniFi OS environment

Compatible with Linux and macOS hosts.

---

# Features

✔ Uses **official firmware**
✔ Full persistent storage
✔ Automatic firmware extraction
✔ Simple one-command install
✔ Clean Docker architecture

Runs the complete **UniFi OS environment**, including the **UniFi Network Application**.

---

# Requirements

Install:

* Docker
* Docker Compose
* curl
* binwalk
* sudo

Example (Debian / Ubuntu):

```
sudo apt install docker.io docker-compose curl binwalk
```

---

# Project Structure

```
.
├── .env
├── example.env
├── docker-compose.yaml
├── Dockerfile
├── build.sh
├── uos-entrypoint.sh
├── .gitignore
└── unifi-os-image/
    ├── firmware/
    └── extract/
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

URL_FIRMWARE=https://fw-download.ubnt.com/data/unifi-os-server/...

DATA_PATH=./unifi-data
```

---

# Install

Run the build script:

```
./build.sh
```

This will:

1. download firmware
2. extract system image
3. load Docker image
4. start container

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

| Port      | Service          |
| --------- | ---------------- |
| 11443     | UniFi OS Web     |
| 8443      | UniFi Controller |
| 8080      | Device Inform    |
| 3478/udp  | STUN             |
| 10001/udp | Discovery        |
| 10003/udp | Discovery        |

---

# Persistent Data

All data is stored inside:

```
DATA_PATH
```

Structure:

```
unifi-data
├── data
├── persistent
├── srv
├── var-lib-unifi
├── var-lib-mongodb
└── etc-rabbitmq-ssl
```

Includes:

* configuration
* users
* MongoDB database
* PostgreSQL database
* certificates

---

# Logs

View container logs:

```
docker logs -f unifi-os-server
```

View system logs:

```
docker exec -it unifi-os-server journalctl -f
```

---

# Update Version

Edit `.env`:

```
UOS_SERVER_VERSION=NEW_VERSION
```

Then run:

```
./build.sh
```

---

# Stop Container

```
docker compose down
```

Persistent data will remain intact.

---

# Troubleshooting

### Firmware extraction fails

Make sure `binwalk` is installed:

```
sudo apt install binwalk
```

---

### Container fails to start

Check logs:

```
docker logs unifi-os-server
```

---

### Port already in use

Edit `docker-compose.yaml` and change the port mapping.

---

# Disclaimer

This project is **not affiliated with Ubiquiti**.

It only automates usage of publicly available firmware.

Use at your own risk.

---

# License

MIT
