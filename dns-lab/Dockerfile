FROM debian:12-slim
RUN apt-get update && \
    apt-get install -y bind9 bind9utils dnsutils iproute2 iputils-ping nano && \
    rm -rf /var/lib/apt/lists/*
CMD ["/usr/sbin/named", "-g", "-u", "bind"]
