#!/bin/bash
set -e

BOOTSTRAP_FLAG="/data/.bootstrapped"

log() {
    echo "[UOS-ENTRYPOINT] $1"
}

log "Inicializando entrypoint do UniFi OS..."

########################################
# UUID persistente
########################################

log "Verificando UUID do sistema..."

if [ ! -f /data/uos_uuid ]; then
    log "UUID não encontrado. Gerando novo UUID compatível..."
    UUID=$(cat /proc/sys/kernel/random/uuid | sed 's/./5/15')
    echo "$UUID" > /data/uos_uuid
    log "UUID gerado: $UUID"
else
    log "UUID existente encontrado."
fi

export UOS_UUID=$(cat /data/uos_uuid)
log "UOS_UUID carregado: $UOS_UUID"

########################################
# Version file
########################################

log "Configurando versão do sistema..."

echo "UOSSERVER.0000000.${UOS_SERVER_VERSION}.0000000.000000.0000" > /usr/lib/version

########################################
# Platform detection
########################################

log "Detectando arquitetura..."

if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    echo "linux-x64" > /usr/lib/platform
    log "Arquitetura detectada: linux-x64"
else
    echo "arm64" > /usr/lib/platform
    log "Arquitetura detectada: arm64"
fi

########################################
# Silenciar console
########################################

log "Silenciando console tty1..."

systemctl mask getty@tty1.service 2>/dev/null || true

########################################
# Preparar volumes
########################################

log "Preparando volumes persistentes..."

prepare_dir() {
    log "Preparando diretório: $1 (owner $2)"
    mkdir -p "$1"
    chown -R "$2" "$1" 2>/dev/null || true
}

prepare_dir /data postgres:postgres
prepare_dir /persistent root:root
prepare_dir /srv root:root
prepare_dir /var/lib/unifi unifi:unifi
prepare_dir /var/lib/mongodb mongodb:mongodb
prepare_dir /etc/rabbitmq/ssl rabbitmq:rabbitmq

prepare_dir /var/run/postgresql postgres:postgres
prepare_dir /var/run/mongodb mongodb:mongodb
prepare_dir /var/log/nginx www-data:www-data

chmod 2775 /var/run/postgresql

log "Permissões de runtime configuradas."

########################################
# Limpeza de locks antigos
########################################

log "Removendo arquivos de lock antigos..."

find /data -name "postmaster.pid" -delete 2>/dev/null || true
find /var/lib/mongodb -name "mongod.lock" -delete 2>/dev/null || true

log "Locks antigos removidos."

########################################
# policy-rc.d fix
########################################

log "Aplicando fix policy-rc.d..."

cat <<'EOF' >/usr/sbin/policy-rc.d
#!/bin/sh
exit 0
EOF

chmod +x /usr/sbin/policy-rc.d

log "policy-rc.d configurado."

########################################
# Evitar restore dpkg após bootstrap
########################################

if [ -f "$BOOTSTRAP_FLAG" ]; then
    log "Bootstrap já executado anteriormente. Desativando serviços de restore dpkg..."
    systemctl mask ubnt-dpkg-restore.service 2>/dev/null || true
    systemctl mask ubnt-dpkg-daemon.service 2>/dev/null || true
else
    log "Primeiro boot detectado."
fi

touch "$BOOTSTRAP_FLAG"

log "Bootstrap finalizado."

########################################
# Iniciar systemd
########################################

log "Inicializando systemd..."

exec /sbin/init --log-target=console