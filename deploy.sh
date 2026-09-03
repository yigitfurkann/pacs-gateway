#!/bin/bash
set -e

echo "=============================================="
echo "PACS Gateway - One-Click Deployment"
echo "=============================================="

# Değişkenleri sor
read -p "Huawei OBS Access Key: " ACCESS_KEY
read -sp "Huawei OBS Secret Key: " SECRET_KEY
echo
read -p "OBS Endpoint (örn: obs.tr-west-1.myhuaweicloud.com): " ENDPOINT
read -p "OBS Bucket Adı: " BUCKET_NAME
read -p "Samba Kullanıcı Adı (varsayılan: pacsuser): " SMB_USER
SMB_USER=${SMB_USER:-pacsuser}
read -sp "Samba Şifresi (varsayılan: 1Huawei9): " SMB_PASS
SMB_PASS=${SMB_PASS:-1Huawei9}
echo
read -p "SMTP Mail Adresi: " SMTP_MAIL
read -sp "SMTP Uygulama Şifresi: " SMTP_PASS
echo
read -p "Alert E-posta Adresi: " ALERT_MAIL
read -p "Mount Dizini (varsayılan: /mnt/pacs-hot/archive): " MOUNT_PATH
MOUNT_PATH=${MOUNT_PATH:-/mnt/pacs-hot/archive}

# Dizinleri oluştur
sudo mkdir -p /etc/rclone /opt/pacs-gateway/{config,prometheus,alertmanager,grafana/dashboards,systemd,logs}
cd /opt/pacs-gateway

# Rclone config oluştur
cat > config/rclone.conf <<EOF
[obs]
type = s3
provider = HuaweiOBS
access_key_id = $ACCESS_KEY
secret_access_key = $SECRET_KEY
endpoint = $ENDPOINT
acl = private
bucket_acl = private
EOF
sudo cp config/rclone.conf /etc/rclone/rclone.conf
sudo chmod 600 /etc/rclone/rclone.conf

# Prometheus config
cat > prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
rule_files:
  - "alert.rules.yml"
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9393']
scrape_configs:
  - job_name: 'rclone'
    static_configs:
      - targets: ['host.docker.internal:5572']
    basic_auth:
      username: 'monitor'
      password: '1Huawei9'
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

# Alert rules
cat > prometheus/alert.rules.yml <<'EOF'
groups:
  - name: pacs_alerts
    rules:
      - alert: RcloneServiceDown
        expr: up{job="rclone"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Rclone servisi çöktü!"
          description: "RC API yanıt vermiyor. OBS erişimi kesildi."
      - alert: SambaServiceDown
        expr: up{job="samba"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Samba servisi çalışmıyor!"
          description: "Windows client'lar paylaşıma erişemiyor."
      - alert: RcloneTransferStalled
        expr: rate(rclone_bytes_transferred_total[5m]) == 0 and rclone_active_transfers > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Transfer kilitlendi!"
          description: "Aktif transfer olmasına rağmen 5 dakikadır veri akışı 0 B/s."
      - alert: HotStorageDiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/mnt/pacs-hot"} / node_filesystem_size_bytes{mountpoint="/mnt/pacs-hot"} * 100) < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Hot disk %90 dolu!"
          description: "Disk alanı kritik seviyede. Hemen müdahale edin."
EOF

# Alertmanager config
cat > alertmanager/alertmanager.yml <<EOF
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '$SMTP_MAIL'
  smtp_auth_username: '$SMTP_MAIL'
  smtp_auth_password: '$SMTP_PASS'
  smtp_require_tls: true
route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'email-admin'
receivers:
  - name: 'email-admin'
    email_configs:
      - to: '$ALERT_MAIL'
        send_resolved: true
        headers:
          Subject: '[PACS-ALERT] {{ .GroupLabels.alertname }}'
EOF

# Grafana config
cat > grafana/grafana.ini <<EOF
[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning

[smtp]
enabled = true
host = smtp.gmail.com:587
user = $SMTP_MAIL
password = $SMTP_PASS
skip_verify = false
from_address = $SMTP_MAIL
from_name = PACS Grafana Alarm
EOF

# Docker Compose dosyası
cat > docker-compose.yml <<'EOF'
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: pacs-node-exporter
    restart: always
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)'
    ports:
      - "9100:9100"

  prometheus:
    image: prom/prometheus:latest
    container_name: pacs-prometheus
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    extra_hosts:
      - "host.docker.internal:host-gateway"

  alertmanager:
    image: prom/alertmanager:latest
    container_name: pacs-alertmanager
    restart: always
    ports:
      - "9393:9393"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--web.listen-address=:9393'

  grafana:
    image: grafana/grafana:latest
    container_name: pacs-grafana
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/grafana.ini:/etc/grafana/grafana.ini:ro
    environment:
      - GF_INSTALL_PLUGINS=grafana-piechart-panel

volumes:
  prometheus_data:
  grafana_data:
EOF

# Systemd servisleri
sudo cp /opt/pacs-gateway/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rclone-rcd rclone-mount-obs
sudo systemctl start rclone-rcd rclone-mount-obs

# Docker compose başlat
sudo docker compose up -d

echo "=============================================="
echo "Kurulum tamamlandı!"
echo "SMB Paylaşımı: \\\\$(hostname -I | awk '{print $1}')\\PACS_Archive"
echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/admin)"
echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "=============================================="
