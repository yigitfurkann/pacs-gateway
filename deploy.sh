#!/bin/bash
set -e

echo "=============================================="
echo "PACS Gateway - One-Click Deployment"
echo "=============================================="

# ============================================
# 0. PUBLIC IP'Yİ AL
# ============================================
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
if [[ -z "$PUBLIC_IP" ]]; then
    read -p "Public IP adresini manuel girin: " PUBLIC_IP
fi

# ============================================
# 1. DOCKER ve DOCKER COMPOSE KURULUMU
# ============================================
if ! command -v docker &> /dev/null; then
    echo "Docker kurulu değil, kuruluyor..."
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "Docker kurulumu tamamlandı."
else
    echo "Docker zaten kurulu."
fi

# ============================================
# 2. KULLANICIDAN BİLGİLERİ AL (ZORUNLU)
# ============================================
while [[ -z "$ACCESS_KEY" ]]; do
    read -p "Huawei OBS Access Key: " ACCESS_KEY
done

while [[ -z "$SECRET_KEY" ]]; do
    read -sp "Huawei OBS Secret Key: " SECRET_KEY
    echo
done

while [[ -z "$ENDPOINT" ]]; do
    read -p "OBS Endpoint (örn: obs.tr-west-1.myhuaweicloud.com): " ENDPOINT
done

while [[ -z "$BUCKET_NAME" ]]; do
    read -p "OBS Bucket Adı: " BUCKET_NAME
done

while [[ -z "$SMB_USER" ]]; do
    read -p "Samba Kullanıcı Adı (örn: pacsuser): " SMB_USER
done

while [[ -z "$SMB_PASS" ]]; do
    read -sp "Samba Şifresi: " SMB_PASS
    echo
done

while [[ -z "$SMTP_MAIL" ]]; do
    read -p "SMTP Mail Adresi: " SMTP_MAIL
done

while [[ -z "$SMTP_PASS" ]]; do
    read -sp "SMTP Uygulama Şifresi: " SMTP_PASS
    echo
done

while [[ -z "$ALERT_MAIL" ]]; do
    read -p "Alert E-posta Adresi: " ALERT_MAIL
done

read -p "Mount Dizini (varsayılan: /mnt/pacs-hot/archive): " MOUNT_PATH
MOUNT_PATH=${MOUNT_PATH:-/mnt/pacs-hot/archive}

# ============================================
# 3. PORT KONTROLLERİ
# ============================================
echo ""
echo "🔍 Port kontrolleri yapılıyor..."

REQUIRED_PORTS=(139 445 3000 5572 9090 9100 9393)
PORT_ERROR=0

for port in "${REQUIRED_PORTS[@]}"; do
    if sudo ss -tlnp | grep -q ":$port "; then
        echo "⚠️  Port $port zaten kullanımda!"
        PORT_ERROR=1
    else
        echo "✅ Port $port kullanıma uygun."
    fi
done

if [[ $PORT_ERROR -eq 1 ]]; then
    echo ""
    echo "❌ Bazı portlar zaten kullanımda!"
    echo "  sudo ss -tlnp | grep -E ':(139|445|3000|5572|9090|9100|9393)'"
    read -p "Devam etmek istiyor musunuz? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Kurulum iptal edildi."
        exit 1
    fi
fi

if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
    echo ""
    echo "🔒 UFW aktif. Gerekli portlar açılıyor..."
    sudo ufw allow 139,445/tcp comment 'SMB'
    sudo ufw allow 3000/tcp comment 'Grafana'
    sudo ufw allow 5572/tcp comment 'Rclone'
    sudo ufw allow 9090/tcp comment 'Prometheus'
    sudo ufw allow 9100/tcp comment 'Node-Exporter'
    sudo ufw allow 9393/tcp comment 'Alertmanager'
fi

# ============================================
# 4. DİZİNLERİ OLUŞTUR
# ============================================
echo ""
echo "📁 Dizinler oluşturuluyor..."
sudo mkdir -p /etc/rclone /opt/pacs-gateway/{config,prometheus,alertmanager,grafana/dashboards,provisioning/datasources,systemd,logs}
sudo mkdir -p "$MOUNT_PATH"
sudo chown -R root:root "$MOUNT_PATH"
sudo chmod 755 "$MOUNT_PATH"

cd /opt/pacs-gateway

# ============================================
# 5. RCLONE CONFIG
# ============================================
echo "📝 Rclone config oluşturuluyor..."
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

# ============================================
# 6. PROMETHEUS CONFIG
# ============================================
echo "📝 Prometheus config oluşturuluyor..."
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

# ============================================
# 7. ALARM KURALLARI
# ============================================
echo "📝 Alarm kuralları oluşturuluyor..."
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

# ============================================
# 8. ALERTMANAGER CONFIG
# ============================================
echo "📝 Alertmanager config oluşturuluyor..."
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

# ============================================
# 9. GRAFANA CONFIG + PROVISIONING
# ============================================
echo "📝 Grafana config ve provisioning oluşturuluyor..."

# Grafana ana config
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

# Grafana provisioning - datasources
mkdir -p provisioning/datasources
cat > provisioning/datasources/prometheus.yml <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

# Grafana provisioning - dashboards (otomatik import)
mkdir -p provisioning/dashboards
cat > provisioning/dashboards/default.yml <<EOF
apiVersion: 1
providers:
  - name: 'default'
    folder: ''
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Rclone dashboard (JSON)
cat > provisioning/dashboards/rclone.json <<'EOF'
{
  "title": "Rclone Dashboard",
  "uid": "rclone-dashboard",
  "panels": [
    {
      "title": "Transfer Rate",
      "targets": [
        {
          "expr": "rate(rclone_bytes_transferred_total[1m])",
          "legendFormat": "Bytes/s"
        }
      ]
    },
    {
      "title": "Total Transferred",
      "targets": [
        {
          "expr": "rclone_bytes_transferred_total",
          "legendFormat": "Total Bytes"
        }
      ]
    }
  ]
}
EOF

# ============================================
# 10. DOCKER COMPOSE DOSYASI (GÜNCELLENDİ)
# ============================================
echo "📝 Docker Compose dosyası oluşturuluyor..."
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
      - ./provisioning:/etc/grafana/provisioning:ro
    environment:
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
      - GF_AUTH_ANONYMOUS_ENABLED=false

volumes:
  prometheus_data:
  grafana_data:
EOF

# ============================================
# 11. SYSTEMD SERVİSLERİ
# ============================================
echo "📝 Systemd servisleri oluşturuluyor..."
mkdir -p /opt/pacs-gateway/systemd

cat > /opt/pacs-gateway/systemd/rclone-rcd.service <<'EOF'
[Unit]
Description=Rclone Remote Control Daemon
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/rclone rcd \
  --rc-addr=0.0.0.0:5572 \
  --rc-user=monitor \
  --rc-pass=1Huawei9 \
  --rc-enable-metrics \
  --rc-web-gui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/pacs-gateway/systemd/rclone-mount-obs.service <<EOF
[Unit]
Description=Rclone Mount OBS
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/rclone mount obs:${BUCKET_NAME} ${MOUNT_PATH} \
  --config /etc/rclone/rclone.conf \
  --allow-other \
  --vfs-cache-mode full \
  --vfs-cache-max-age 720h \
  --vfs-cache-max-size 100G \
  --dir-cache-time 168h \
  --buffer-size 256M
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp /opt/pacs-gateway/systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rclone-rcd rclone-mount-obs

# ============================================
# 12. SAMBA KULLANICISI OLUŞTUR
# ============================================
echo "👤 Samba kullanıcısı oluşturuluyor..."
sudo useradd -M -s /sbin/nologin "$SMB_USER" 2>/dev/null || true
echo -e "$SMB_PASS\n$SMB_PASS" | sudo smbpasswd -a -s "$SMB_USER"

sudo tee /etc/samba/smb.conf > /dev/null <<EOF
[global]
   server min protocol = SMB2
   server max protocol = SMB3
   client min protocol = SMB2
   client max protocol = SMB3
   workgroup = PACS
   interfaces = 0.0.0.0/0
   bind interfaces only = no

[PACS_Archive]
   path = ${MOUNT_PATH}
   browseable = yes
   read only = no
   guest ok = no
   valid users = $SMB_USER
   force user = $SMB_USER
   create mask = 0644
   directory mask = 0755
EOF

sudo systemctl enable smbd
sudo systemctl restart smbd

# ============================================
# 13. RCLONE SERVİSLERİNİ BAŞLAT
# ============================================
echo "🚀 Rclone servisleri başlatılıyor..."
sudo systemctl start rclone-rcd rclone-mount-obs

# ============================================
# 14. DOCKER COMPOSE BAŞLAT
# ============================================
echo "🐳 Docker Compose başlatılıyor..."
sudo docker compose up -d

# ============================================
# 15. KURULUM SONRASI KONTROLLER
# ============================================
echo ""
echo "🔍 Kurulum sonrası kontroller yapılıyor..."

if curl -s -u monitor:1Huawei9 http://localhost:5572/metrics > /dev/null 2>&1; then
    echo "✅ Rclone RC API çalışıyor."
else
    echo "❌ Rclone RC API çalışmıyor! Log: sudo journalctl -u rclone-rcd -f"
fi

if mount | grep -q "$MOUNT_PATH"; then
    echo "✅ Rclone mount başarılı."
else
    echo "❌ Rclone mount başarısız! Log: sudo journalctl -u rclone-mount-obs -f"
fi

if sudo systemctl is-active --quiet smbd; then
    echo "✅ Samba servisi çalışıyor."
else
    echo "❌ Samba servisi çalışmıyor! Log: sudo journalctl -u smbd -f"
fi

if docker ps | grep -q "pacs-prometheus"; then
    echo "✅ Prometheus çalışıyor."
else
    echo "❌ Prometheus çalışmıyor! Log: docker logs pacs-prometheus"
fi

if docker ps | grep -q "pacs-grafana"; then
    echo "✅ Grafana çalışıyor."
else
    echo "❌ Grafana çalışmıyor! Log: docker logs pacs-grafana"
fi

if docker ps | grep -q "pacs-alertmanager"; then
    echo "✅ Alertmanager çalışıyor."
else
    echo "❌ Alertmanager çalışmıyor! Log: docker logs pacs-alertmanager"
fi

# ============================================
# 16. KURULUM TAMAMLANDI
# ============================================
echo ""
echo "=============================================="
echo "✅ Kurulum tamamlandı!"
echo "=============================================="
echo ""
echo "📌 Erişim Bilgileri:"
echo "   SMB Paylaşımı: \\\\$PUBLIC_IP\\PACS_Archive"
echo "   Kullanıcı: $SMB_USER"
echo "   Şifre: (girilen şifre)"
echo ""
echo "   Grafana: http://$PUBLIC_IP:3000 (admin/admin)"
echo "   Prometheus: http://$PUBLIC_IP:9090"
echo "   Rclone Web GUI: http://$PUBLIC_IP:5572 (monitor/1Huawei9)"
echo ""
echo "📋 Servis Yönetimi:"
echo "   Systemd: sudo systemctl status rclone-mount-obs rclone-rcd smbd"
echo "   Docker: cd /opt/pacs-gateway && docker compose ps"
echo ""
echo "📁 Mount Dizini: $MOUNT_PATH"
echo "=============================================="
