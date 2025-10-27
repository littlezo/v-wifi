FROM debian:trixie-slim

USER root

RUN apt-get update && \
    apt-get install -y hostapd dnsmasq iproute2 iptables iputils-ping procps iw wireless-tools wavemon net-tools pciutils bc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]