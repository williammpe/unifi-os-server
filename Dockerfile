ARG BASE_IMAGE=debian:bullseye-slim
FROM ${BASE_IMAGE}

ARG UOS_SERVER_VERSION
ENV UOS_SERVER_VERSION=${UOS_SERVER_VERSION}
ENV container docker

STOPSIGNAL SIGRTMIN+3

RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    dbus \
    curl \
    procps \
    iproute2 \
 && apt-get clean

COPY uos-entrypoint.sh /root/uos-entrypoint.sh
RUN chmod +x /root/uos-entrypoint.sh

ENTRYPOINT ["/root/uos-entrypoint.sh"]