# syntax=docker/dockerfile:1

# Build autocontido: baixa o instalador oficial da Ubiquiti, extrai a imagem
# OCI embutida com binwalk, achata as camadas num rootfs e sobe o entrypoint
# por cima. Não depende de nenhuma imagem base pré-pronta nem de extração
# manual no host (binwalk/sudo saem do setup.sh e entram aqui).

# ---------------------------------------------------------------------------
# Estágio 1 - extrai o rootfs do UniFi OS Server a partir do instalador
# ---------------------------------------------------------------------------
FROM ubuntu:22.04 AS extractor

ARG TARGETARCH
ARG INSTALLER_URL_AMD64
ARG INSTALLER_URL_ARM64

RUN apt-get update && apt-get install -y --no-install-recommends \
        binwalk jq p7zip-full curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN if [ "$TARGETARCH" = "arm64" ]; then \
      URL="$INSTALLER_URL_ARM64"; \
    else \
      URL="$INSTALLER_URL_AMD64"; \
    fi && \
    [ -n "$URL" ] || { echo "Nenhuma URL de instalador definida para $TARGETARCH"; exit 1; } && \
    curl -fL --retry 5 --retry-delay 2 -o installer.bin "$URL"

RUN binwalk --run-as=root -e installer.bin

RUN /bin/bash <<'EXTRACT'
set -eo pipefail

IMAGE_TAR=$(find /build -type f -name 'image.tar' -print -quit)
[ -n "$IMAGE_TAR" ] || { echo "image.tar não encontrado após a extração"; exit 1; }

mkdir oci
tar xf "$IMAGE_TAR" -C oci/

MANIFEST=$(jq -r '.manifests[0].digest' oci/index.json | cut -d: -f2)

mkdir /rootfs
jq -r '.layers[].digest' "oci/blobs/sha256/$MANIFEST" | cut -d: -f2 | \
while read -r layer; do
    echo "Extraindo camada $layer"
    tar xf "oci/blobs/sha256/$layer" -C /rootfs

    # marcadores de whiteout OCI
    find /rootfs -name '.wh.*' 2>/dev/null | while read -r wh; do
        base=$(basename "$wh"); dir=$(dirname "$wh")
        if [ "$base" = ".wh..wh..opq" ]; then
            find "$dir" -mindepth 1 -maxdepth 1 ! -name '.wh..wh..opq' -exec rm -rf {} +
        else
            rm -rf "$dir/${base#.wh.}"
        fi
        rm -f "$wh"
    done
done
EXTRACT

COPY uos-entrypoint.sh /rootfs/root/uos-entrypoint.sh
COPY site-localhost-bypass.conf /rootfs/root/site-localhost-bypass.conf
RUN chmod +x /rootfs/root/uos-entrypoint.sh

# ---------------------------------------------------------------------------
# Estágio 2 - imagem final a partir do rootfs extraído
# ---------------------------------------------------------------------------
FROM scratch

COPY --from=extractor /rootfs /

ARG UOS_SERVER_VERSION="5.0.6"
ARG FIRMWARE_PLATFORM="linux-custom"

ENV UOS_SERVER_VERSION="${UOS_SERVER_VERSION}" \
    FIRMWARE_PLATFORM="${FIRMWARE_PLATFORM}"
ENV PRODUCT_NAME="UniFi OS Server"

STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/root/uos-entrypoint.sh"]
