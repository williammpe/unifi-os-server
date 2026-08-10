#!/bin/bash

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
    echo "[UOS-ENTRYPOINT][$(date -Iseconds)] $*"
}

# Define/atualiza uma chave no system.properties do UniFi (cria o arquivo se não existir).
set_unifi_property() {
    local key="$1" value="$2"
    local escaped_value="${value//\\/\\\\}"
    escaped_value="${escaped_value//&/\\&}"
    if grep -q "^${key}=" "$UNIFI_SYSTEM_PROPERTIES" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$UNIFI_SYSTEM_PROPERTIES"
    else
        echo "${key}=${value}" >> "$UNIFI_SYSTEM_PROPERTIES"
    fi
}

# Remove uma chave do system.properties (não faz nada se a chave/arquivo não existir).
remove_unifi_property() {
    local key="$1"
    sed -i "/^${key}=/d" "$UNIFI_SYSTEM_PROPERTIES" 2>/dev/null
}

# Cria um diretório com owner definido, se ele ainda não existir.
ensure_dir() {
    local dir="$1" owner="$2"
    if [ ! -d "$dir" ]; then
        log "Inicializando $dir"
        mkdir -p "$dir"
        chown "$owner" "$dir"
        chmod 755 "$dir"
    fi
}

log "Inicializando entrypoint do UniFi OS..."

# ---------------------------------------------------------------------------
# 1. UUID persistente
# ---------------------------------------------------------------------------

if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        log "Definindo UUID a partir da variável de ambiente: $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        log "UUID não encontrado. Gerando novo UUID compatível..."
        UUID=$(cat /proc/sys/kernel/random/uuid)

        # Falseia um UUID v5
        UOS_UUID=$(echo "$UUID" | sed s/./5/15)
        log "UUID gerado: $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
else
    log "UUID existente encontrado."
fi

export UOS_UUID=$(cat /data/uos_uuid)
log "UOS_UUID carregado: $UOS_UUID"

# ---------------------------------------------------------------------------
# 2. Versão / plataforma / metadados do produto
# ---------------------------------------------------------------------------

log "Configurando versão do sistema..."
echo "UOSSERVER.0000000.${UOS_SERVER_VERSION}.0000000.000000.0000" > /usr/lib/version
log "Configurando plataforma: ${FIRMWARE_PLATFORM}"
echo "${FIRMWARE_PLATFORM}" > /usr/lib/platform
log "Configurando nome do produto: ${PRODUCT_NAME}"
echo "${PRODUCT_NAME}" > /usr/lib/product_name

# ---------------------------------------------------------------------------
# 3. Rede — alias macvlan eth0
# ---------------------------------------------------------------------------

# Cria o alias eth0 se ainda não existir (requer capability NET_ADMIN e o
# módulo de kernel macvlan carregado no host). Verifica tap0 primeiro
# (ambientes de VPN/hypervisor), senão usa a interface de rota padrão do host.
if [ ! -d "/sys/devices/virtual/net/eth0" ]; then
    if [ -d "/sys/devices/virtual/net/tap0" ]; then
        PARENT_IF="tap0"
    else
        PARENT_IF=$(ip route show default 2>/dev/null | awk '/default via/ {print $5; exit}')
    fi

    if [ -n "$PARENT_IF" ]; then
        log "Criando alias macvlan eth0 a partir de $PARENT_IF"
        ip link add name eth0 link "$PARENT_IF" type macvlan
        ip link set eth0 up
    else
        log "AVISO: não foi possível determinar a interface pai para o alias eth0"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Diretórios de log e dados dos serviços
# ---------------------------------------------------------------------------

log "Preparando diretórios de log e dados..."

ensure_dir "/var/log/nginx"    "nginx:nginx"
ensure_dir "/var/log/mongodb"  "mongodb:mongodb"
ensure_dir "/var/log/rabbitmq" "rabbitmq:rabbitmq"

# Diretório de dados do MongoDB — sempre ajusta owner (pode vir de volume montado)
log "Garantindo ownership do MongoDB em /var/lib/mongodb"
chown -R mongodb:mongodb /var/lib/mongodb

# ---------------------------------------------------------------------------
# 5. MongoDB — interno vs. externo
# ---------------------------------------------------------------------------

# UOS_SYSTEM_IP é obrigatório para o UniFi funcionar.
if [ -z "${UOS_SYSTEM_IP}" ]; then
    log "ERRO: a variável UOS_SYSTEM_IP é obrigatória e não foi definida"
    exit 1
fi
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
set_unifi_property "system_ip" "$UOS_SYSTEM_IP"

# MONGO_INTERNAL=true  → deixa a UniFi Network App gerenciar seu próprio mongod
#                        (porta 27117, dbpath /usr/lib/unifi/data/db)
# MONGO_INTERNAL=false → usa um MongoDB externo (padrão, remove o mongod interno)
MONGO_INTERNAL="${MONGO_INTERNAL:-false}"

if [ "$MONGO_INTERNAL" = "false" ]; then
    MONGO_HOST="${MONGO_HOST:-unifi-os-server-mongodb}"
    MONGO_PORT="${MONGO_PORT:-27017}"
    MONGO_USER="${MONGO_USER:-}"
    MONGO_PASS="${MONGO_PASS:-}"
    MONGO_TLS="${MONGO_TLS:-false}"
    MONGO_AUTH_SOURCE="${MONGO_AUTH_SOURCE-admin}"

    if [ -n "${MONGO_USER}" ] && [ -n "${MONGO_PASS}" ]; then
        MONGO_URI="mongodb\\://${MONGO_USER}\\:${MONGO_PASS}@${MONGO_HOST}\\:${MONGO_PORT}"
    else
        MONGO_URI="mongodb\\://${MONGO_HOST}\\:${MONGO_PORT}"
    fi

    MONGO_PARAMS="tls\\=${MONGO_TLS}"
    if [ -n "${MONGO_USER}" ] && [ -n "${MONGO_AUTH_SOURCE}" ]; then
        MONGO_PARAMS="${MONGO_PARAMS}&authSource\\=${MONGO_AUTH_SOURCE}"
    fi

    log "MongoDB externo: ${MONGO_HOST}:${MONGO_PORT}"
    set_unifi_property "db.mongo.local" "false"
    set_unifi_property "db.mongo.uri" "${MONGO_URI}/ace?${MONGO_PARAMS}"
    set_unifi_property "statdb.mongo.uri" "${MONGO_URI}/ace_stat?${MONGO_PARAMS}"

    if [ -f "/usr/bin/mongod" ]; then
        log "Removendo binário mongod interno"
        rm -f /usr/bin/mongod
    fi
else
    log "Usando MongoDB interno (gerenciado pela UniFi Network App)"
    set_unifi_property "db.mongo.local" "true"
    # Remove URIs externas obsoletas para o app cair de volta no padrão
    # interno (porta 27117) em vez de tentar conectar numa instância inexistente.
    remove_unifi_property "db.mongo.uri"
    remove_unifi_property "statdb.mongo.uri"

    # O app inicia seu próprio mongod na porta 27117, então desativa o
    # mongodb.service do sistema para evitar um ciclo de start/stop inútil.
    rm -f /etc/systemd/system/multi-user.target.wants/mongodb.service
fi

# ---------------------------------------------------------------------------
# 6. Bypass da Network App (porta 7443)
# ---------------------------------------------------------------------------
#
# Por padrão, a UniFi Network Application fica atrás do SSO do UOS — é
# preciso autenticar pelo console UniFi OS antes de acessar a UI do
# controller ou sua API REST. Isso dificulta automação e acesso direto à API.
#
# Quando EXPOSE_NETWORK_APP=true, um server block do nginx é injetado
# escutando na porta 7443 e fazendo proxy direto para a Network App em
# 127.0.0.1:8081, pulando o SSO inteiramente.
#
#   *** NÃO USAR EM PRODUÇÃO — NÃO EXPOR PUBLICAMENTE ***
#
# Esse bypass contorna a autenticação SSO. Deve ficar vinculado apenas a
# localhost (o docker-compose.yaml mapeia como 127.0.0.1:7443:7443) e nunca
# ser publicado numa interface pública. Expô-lo à rede permitiria acesso
# não autenticado à Network Application.
#
# A injeção é aplicada no hook de pre-start do unifi-core para sobreviver
# à limpeza do diretório de config que acontece em todo restart.

EXPOSE_NETWORK_APP="${EXPOSE_NETWORK_APP:-false}"

if [ "$EXPOSE_NETWORK_APP" = "true" ]; then
    PRE_START="/usr/share/unifi-core/app/hooks/pre-start"
    INJECT='cp /root/site-localhost-bypass.conf /data/unifi-core/config/http/site-localhost-bypass.conf'
    if ! grep -qF "$INJECT" "$PRE_START" 2>/dev/null; then
        echo "$INJECT" >> "$PRE_START"
        log "Bypass da Network App: aplicado em $PRE_START"
    fi
fi

# ---------------------------------------------------------------------------
# 7. PostgreSQL — exposto em todas as interfaces para o mapeamento de porta do Docker
# ---------------------------------------------------------------------------

# listen_addresses exige restart (reload não é suficiente).
(
    PG_CONF="/etc/postgresql/14/main/postgresql.conf"
    PG_HBA="/etc/postgresql/14/main/pg_hba.conf"

    log "Worker de exposição do PostgreSQL iniciado"
    while [ ! -f "$PG_CONF" ]; do sleep 5; done

    if grep -q "^#\?listen_addresses" "$PG_CONF"; then
        sed -i "s/^#\?listen_addresses.*/listen_addresses = '*' /" "$PG_CONF"
    else
        echo "listen_addresses = '*'" >> "$PG_CONF"
    fi

    if ! grep -q "^host all all 0.0.0.0/0" "$PG_HBA" 2>/dev/null; then
        echo "host all all 0.0.0.0/0 trust" >> "$PG_HBA"
    fi

    # Espera o systemd subir e então reinicia o PostgreSQL para aplicar listen_addresses
    while ! systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; do sleep 2; done
    systemctl restart postgresql@14-main 2>/dev/null || systemctl restart postgresql 2>/dev/null || true

    log "PostgreSQL: exposto na porta 5432"
) &

# ---------------------------------------------------------------------------
# 8. Encaminhamento do journal & systemd
# ---------------------------------------------------------------------------

# Encaminha o journalctl para o stream de log do Docker.
# Salva o stdout do Docker antes do systemd substituí-lo por /dev/null.
exec 3>&1
(
    # Espera até o systemd-journald criar seus arquivos de journal.
    # journalctl sai com 0 mesmo sem arquivos, então checa a saída.
    while journalctl -n 0 2>&1 | grep -q "No journal files were found"; do
        sleep 1
    done
    exec journalctl -f --no-hostname -o short >&3 2>&3
) &

log "Iniciando systemd..."

exec /sbin/init
