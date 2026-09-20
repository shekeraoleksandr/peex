#!/usr/bin/env bash
# Boot-time setup for the monitoring instance (Ubuntu 24.04): Docker +
# Prometheus + Grafana, with Prometheus scraping the web instance's
# node_exporter over the private VPC IP (templated in by Terraform).
set -euo pipefail
exec > >(tee /var/log/peex-userdata.log) 2>&1

# cloud-init races unattended-upgrades for the dpkg lock on fresh Ubuntu
# instances -- wait it out instead of dying on "Could not get lock".
wait_for_apt() {
    local i
    for i in $(seq 1 60); do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 &&
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            return 0
        fi
        echo "  waiting for apt/dpkg lock ($i)..."
        sleep 5
    done
    echo "WARN: apt lock still held after 5 min, continuing anyway"
}

wait_for_apt
apt-get update -y
wait_for_apt
apt-get install -y docker.io curl

# The "docker compose" v2 plugin has different package names depending on the
# repo: Ubuntu 24.04 ships it as docker-compose-v2, Docker's own apt repo calls
# it docker-compose-plugin. Try both; we fall back to plain `docker run` below
# if neither is available, so this must not abort the script.
wait_for_apt
apt-get install -y docker-compose-v2 \
    || apt-get install -y docker-compose-plugin \
    || echo "WARN: no docker compose plugin available, will use docker run"

systemctl enable docker
systemctl start docker

mkdir -p /opt/peex-monitoring/prometheus
mkdir -p /opt/peex-monitoring/grafana/provisioning/datasources
mkdir -p /opt/peex-monitoring/grafana/provisioning/dashboards

cat > /opt/peex-monitoring/prometheus/prometheus.yml <<YAML
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "web-instance"
    static_configs:
      - targets: ["${web_private_ip}:9100"]
        labels:
          instance_role: "web"

  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
YAML

cat > /opt/peex-monitoring/grafana/provisioning/datasources/datasources.yml <<'YAML'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
YAML

cat > /opt/peex-monitoring/docker-compose.yml <<'YAML'
services:
  prometheus:
    image: prom/prometheus:v2.54.1
    container_name: prometheus
    volumes:
      - ./prometheus:/etc/prometheus:ro
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.2.0
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=peexdemo123
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "3000:3000"
    restart: unless-stopped
YAML

cd /opt/peex-monitoring

if docker compose version >/dev/null 2>&1; then
    echo "==> starting via docker compose"
    docker compose up -d
else
    echo "==> docker compose unavailable, starting containers directly"
    # A user-defined network gives the containers DNS resolution by name, so
    # Grafana's provisioned datasource (http://prometheus:9090) still works.
    docker network create peex-mon 2>/dev/null || true

    docker rm -f prometheus grafana 2>/dev/null || true

    docker run -d --name prometheus --network peex-mon --restart unless-stopped \
        -p 9090:9090 \
        -v /opt/peex-monitoring/prometheus:/etc/prometheus:ro \
        prom/prometheus:v2.54.1

    docker run -d --name grafana --network peex-mon --restart unless-stopped \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_PASSWORD=peexdemo123 \
        -e GF_USERS_ALLOW_SIGN_UP=false \
        -v /opt/peex-monitoring/grafana/provisioning:/etc/grafana/provisioning:ro \
        grafana/grafana:11.2.0
fi

echo "==> containers now running:"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo "monitoring user-data DONE"
