#!/bin/bash
set -e

log() {
    echo "[UOS-BUILD] $1"
}

########################################
# Carregar .env
########################################

log "Carregando variáveis de ambiente..."

if [ -f .env ]; then
    set -a
    source .env
    set +a
    log ".env carregado com sucesso."
else
    echo "[ERRO] Arquivo .env não encontrado!"
    exit 1
fi

########################################
# Variáveis
########################################

WORK_DIR="./unifi-os-image"
FIRMWARE_DIR="$WORK_DIR/firmware"
EXTRACT_DIR="$WORK_DIR/extract"

FW_FILE="$FIRMWARE_DIR/unifi-os-$UOS_SERVER_VERSION"
IMAGE_TAR="$EXTRACT_DIR/image.tar"

FINAL_IMAGE="uosserver:$UOS_SERVER_VERSION"

log "Versão do UniFi OS: $UOS_SERVER_VERSION"
log "Imagem final: $FINAL_IMAGE"

########################################
# 1. Verificar imagem docker
########################################

log "Etapa 1/3: Verificando se a imagem Docker já existe..."

if [[ "$(docker images -q $FINAL_IMAGE 2> /dev/null)" == "" ]]; then

    log "Imagem não encontrada. Iniciando processo de build..."

    mkdir -p "$FIRMWARE_DIR" "$EXTRACT_DIR"

    ########################################
    # Download firmware
    ########################################

    if [ ! -f "$FW_FILE" ]; then
        log "Firmware não encontrado localmente."
        log "Baixando firmware..."

        curl -L -o "$FW_FILE" "$URL_FIRMWARE"

        log "Download concluído."
    else
        log "Firmware já existente."
    fi

    ########################################
    # Extração firmware
    ########################################

    if [ ! -f "$IMAGE_TAR" ]; then

        log "Extraindo firmware..."

        sudo binwalk -e "$FW_FILE" --directory "$EXTRACT_DIR" --run-as=root > /dev/null

        log "Procurando image.tar dentro do firmware..."

        FOUND_TAR=$(sudo find "$EXTRACT_DIR" -name "image.tar" | head -n 1)

        if [ -z "$FOUND_TAR" ]; then
            echo "[ERRO] image.tar não encontrado após extração!"
            exit 1
        fi

        log "image.tar encontrado: $FOUND_TAR"

        sudo mv "$FOUND_TAR" "$IMAGE_TAR"
        sudo chown $(id -u):$(id -g) "$IMAGE_TAR"

        log "Firmware extraído com sucesso."

    else
        log "image.tar já existente."
    fi

    ########################################
    # Docker load
    ########################################

    log "Carregando imagem Docker..."

    LOAD_OUTPUT=$(docker load -i "$IMAGE_TAR")

    RAW_REF=$(echo "$LOAD_OUTPUT" | sed 's/Loaded image: //')

    log "Imagem carregada: $RAW_REF"

    docker tag "$RAW_REF" "$FINAL_IMAGE"

    log "Imagem marcada como: $FINAL_IMAGE"

else

    log "Imagem Docker já existente. Pulando build."

fi

########################################
# 2. Preparar volume
########################################

log "Etapa 2/3: Preparando volume persistente..."

mkdir -p "$DATA_PATH"

log "Volume criado/verificado: $DATA_PATH"

########################################
# 3. Subir container
########################################

log "Etapa 3/3: Iniciando container..."

docker compose up -d --remove-orphans

log "Container iniciado com sucesso."

echo
echo "============================================================"
echo "        UniFi OS Server iniciado com sucesso"
echo "============================================================"
echo