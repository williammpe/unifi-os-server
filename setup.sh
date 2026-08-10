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
# Validações
########################################

if [ -z "$UOS_SERVER_VERSION" ]; then
    echo "[ERRO] UOS_SERVER_VERSION não definido no .env!"
    exit 1
fi

if [ -z "$INSTALLER_URL_AMD64" ] && [ -z "$INSTALLER_URL_ARM64" ]; then
    echo "[ERRO] Defina INSTALLER_URL_AMD64 e/ou INSTALLER_URL_ARM64 no .env!"
    exit 1
fi

if [ -z "$UOS_SYSTEM_IP" ]; then
    echo "[ERRO] UOS_SYSTEM_IP não definido no .env! (IP público/do host usado pelo UniFi)"
    exit 1
fi

FINAL_IMAGE="uosserver:$UOS_SERVER_VERSION"

log "Versão do UniFi OS: $UOS_SERVER_VERSION"
log "Imagem final: $FINAL_IMAGE"

########################################
# 1. Build da imagem (download + extração do firmware acontecem
#    dentro do Dockerfile, sem necessidade de binwalk/sudo no host)
########################################

log "Etapa 1/3: Buildando imagem Docker (isso baixa e extrai o firmware oficial)..."

docker compose build

log "Build concluído: $FINAL_IMAGE"

########################################
# 2. Preparar volumes
########################################

log "Etapa 2/3: Preparando volumes persistentes..."

mkdir -p "$DATA_PATH/uos" "$DATA_PATH/data" "$DATA_PATH/mongodb"

log "Volumes criados/verificados em: $DATA_PATH"

########################################
# 3. Subir container
########################################

log "Etapa 3/3: Iniciando containers..."

docker compose up -d --remove-orphans

log "Containers iniciados com sucesso."

echo
echo "============================================================"
echo "        UniFi OS Server iniciado com sucesso"
echo "        Acesse: https://localhost:11443"
echo "============================================================"
echo
