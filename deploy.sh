#!/bin/bash
set -e

echo "=============================================="
echo "PACS Gateway - One-Click Deployment"
echo "=============================================="

echo "   ██████╗██╗      ██████╗ ██╗   ██╗███████╗"
echo "  ██╔════╝██║     ██╔═══██╗██║   ██║██╔════╝"
echo "  ██║     ██║     ██║   ██║██║   ██║███████╗"
echo "  ██║     ██║     ██║   ██║██║   ██║╚════██║"
echo "  ╚██████╗███████╗╚██████╔╝╚██████╔╝███████║"
echo "   ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝"

# ============================================
# 0. PUBLIC ve PRIVATE IP'Yİ AL
# ============================================
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
if [[ -z "$PUBLIC_IP" ]]; then
    read -p "Public IP adresini manuel girin: " PUBLIC_IP
fi
PRIVATE_IP=$(hostname -I | awk '{print $1}')

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

# Region seçimi
echo ""
echo "📍 OBS Region seçin:"
echo "  1) tr-west-1 (Istanbul)"
echo "  2) eu-west-1 (Ireland)"
echo "  3) eu-west-2 (London)"
echo "  4) eu-west-3 (Paris)"
echo "  5) eu-west-4 (Frankfurt)"
echo "  6) ap-southeast-1 (Singapore)"
echo "  7) ap-southeast-2 (Tokyo)"
echo "  8) ap-southeast-3 (Seoul)"
echo "  9) cn-north-1 (Beijing)"
echo "  10) us-east-1 (Virginia)"
echo "  11) us-west-1 (California)"
read -p "Seçiminiz (1-11): " REGION_CHOICE

case $REGION_CHOICE in
    1) ENDPOINT="obs.tr-west-1.myhuaweicloud.com" ;;
    2) ENDPOINT="obs.eu-west-1.myhuaweicloud.com" ;;
    3) ENDPOINT="obs.eu-west-2.myhuaweicloud.com" ;;
    4) ENDPOINT="obs.eu-west-3.myhuaweicloud.com" ;;
    5) ENDPOINT="obs.eu-west-4.myhuaweicloud.com" ;;
    6) ENDPOINT="obs.ap-southeast-1.myhuaweicloud.com" ;;
    7) ENDPOINT="obs.ap-southeast-2.myhuaweicloud.com" ;;
    8) ENDPOINT="obs.ap-southeast-3.myhuaweicloud.com" ;;
    9) ENDPOINT="obs.cn-north-1.myhuaweicloud.com" ;;
    10) ENDPOINT="obs.us-east-1.myhuaweicloud.com" ;;
    11) ENDPOINT="obs.us-west-1.myhuaweicloud.com" ;;
    *) echo "Geçersiz seçim, varsayılan tr-west-1 kullanılıyor."; ENDPOINT="obs.tr-west-1.myhuaweicloud.com" ;;
esac
echo "✅ Seçilen endpoint: $ENDPOINT"

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

# RC Kimlik Bilgileri (ZORUNLU)
while [[ -z "$RC_USER" ]]; do
    read -p "Rclone RC Kullanıcı Adı: " RC_USER
done
while [[ -z "$RC_PASS" ]]; do
    read -sp "Rclone RC Şifresi: " RC_PASS
    echo
done

read -p "Mount Dizini (varsayılan: /mnt/pacs-hot/archive): " MOUNT_PATH
MOUNT_PATH=${MOUNT_PATH:-/mnt/pacs-hot/archive}
if [[ ! "$MOUNT_PATH" =~ ^/ ]]; then
    MOUNT_PATH="/$MOUNT_PATH"
    echo "⚠️  Mount dizini '/' ile düzeltildi: $MOUNT_PATH"
fi

# ============================================
# 2.1 DİNAMİK PARAMETRELER (DETAYLI AÇIKLAMALI)
# ============================================

# --- VFS CACHE SÜRESİ ---
echo ""
echo "📦 VFS CACHE SÜRESİ AYARI:"
echo "   Dosyaların yerel diskte ne kadar süre tutulacağını belirler."
echo "   Süre dolunca dosya yerel diskten silinir ama OBS'te kalır."
echo "   Kullanıcı dosyaya tıkladığında OBS'ten tekrar indirilir."
echo "   Birimler: d = gün, h = saat, m = dakika"
echo "   Örnekler: 720h (30 gün - prod), 3h (3 saat - test), 30m (30 dakika - hızlı test)"
read -p "VFS Cache Süresi (varsayılan: 720h): " VFS_CACHE_AGE_RAW
VFS_CACHE_AGE=${VFS_CACHE_AGE_RAW:-720h}
if [[ ! "$VFS_CACHE_AGE" =~ (s|m|h|d)$ ]]; then
  echo "⚠️  Birim belirtilmedi, saat (h) varsayılıyor."
  VFS_CACHE_AGE="${VFS_CACHE_AGE}h"
fi

# --- VFS CACHE BOYUTU ---
echo ""
echo "📦 VFS CACHE BOYUTU AYARI:"
echo "   Yerel diskin en fazla ne kadarını cache için kullanacağını belirler."
echo "   Örnekler: 100G, 500G, 1T"
read -p "VFS Cache Max Boyut (varsayılan: 100G): " VFS_CACHE_SIZE
VFS_CACHE_SIZE=${VFS_CACHE_SIZE:-100G}

# --- MOUNT İZİNLERİ ---
echo ""
echo "=============================================="
echo "🔐 DOSYA İZİN AYARLARI (MOUNT_PERMS)"
echo "=============================================="
echo "Linux İzin Kodu: 4=Oku, 2=Yaz, 1=Çalıştır"
echo ""
echo "Dizin İzinleri (İlk 3 hane):"
echo "  0755 = Sahip(rwx), Grup(r-x), Diğerleri(r-x) -> Sadece Sahip yazabilir"
echo "  0775 = Sahip(rwx), Grup(rwx), Diğerleri(r-x) -> Sahip ve Grup yazabilir (Önerilen)"
echo "  0777 = Herkes yazabilir (Test için, riskli)"
echo ""
echo "Dosya İzinleri (Son 3 hane):"
echo "  0644 = Sahip(rw-), Grup(r--), Diğerleri(r--) -> Sadece Sahip yazabilir"
echo "  0664 = Sahip(rw-), Grup(rw-), Diğerleri(r--) -> Sahip ve Grup yazabilir (Önerilen)"
echo "  0666 = Herkes yazabilir (Test için, riskli)"
echo ""
echo "Umask (Yeni dosya iznini kısıtlar):"
echo "  0   = Hiç kısıtlama yok (Önerilen test)"
echo "  022 = Klasik kısıtlama (755/644) -> Prod için standart"
echo "  077 = Çok katı (700/600) -> Sadece sahip erişebilir"
read -p "Mount izinleri (dir/file/umask - varsayılan: 0775 0664 0): " MOUNT_PERMS_RAW
MOUNT_PERMS=${MOUNT_PERMS_RAW:-"0775 0664 0"}
read DIR_PERMS FILE_PERMS UMASK_VAL <<< "$MOUNT_PERMS"

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
    echo "Lütfen aşağıdaki komutla hangi servislerin bu portları kullandığını kontrol edin:"
    echo "  sudo ss -tlnp | grep -E ':(139|445|3000|5572|9090|9100|9393)'"
    read -p "Devam etmek istiyor musunuz? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Kurulum iptal edildi."
        exit 1
    fi
fi

# Güvenlik duvarı kontrolü (UFW)
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
sudo mkdir -p /etc/rclone /opt/pacs-gateway/{config,prometheus,alertmanager,grafana/dashboards,systemd,logs}
sudo mkdir -p "$MOUNT_PATH"

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
      username: '$RC_USER'
      password: '$RC_PASS'
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
# 9. GRAFANA CONFIG (ŞİFRE SORULMAZ, admin/admin KALIR)
# ============================================
echo "📝 Grafana config oluşturuluyor..."
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

# ============================================
# 10. DOCKER COMPOSE DOSYASI (admin/admin Varsayılan)
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
# 11. SYSTEMD SERVİSLERİ (Rclone RC)
# ============================================
echo "📝 Systemd servisleri oluşturuluyor..."
mkdir -p /opt/pacs-gateway/systemd

cat > /opt/pacs-gateway/systemd/rclone-rcd.service <<EOF
[Unit]
Description=Rclone Remote Control Daemon
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/rclone rcd \
  --rc-addr=0.0.0.0:5572 \
  --rc-user=$RC_USER \
  --rc-pass=$RC_PASS \
  --rc-enable-metrics \
  --rc-web-gui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo cp /opt/pacs-gateway/systemd/rclone-rcd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rclone-rcd

# ============================================
# 12. SAMBA KULLANICISI OLUŞTUR ve RCLONE MONTE ET (DİNAMİK)
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
   create mask = 0666
   directory mask = 0777
EOF

sudo systemctl enable smbd
sudo systemctl restart smbd

# --- KRİTİK DÜZELTME: Dinamik Cache ve İzin Ayarları ---
SMB_UID=$(id -u "$SMB_USER")
SMB_GID=$(id -g "$SMB_USER")

echo "Rclone mount servisi, ${SMB_USER} (UID: ${SMB_UID}, GID: ${SMB_GID}) için yapılandırılıyor..."
echo "🔧 Cache: $VFS_CACHE_AGE / $VFS_CACHE_SIZE | İzinler: D=$DIR_PERMS F=$FILE_PERMS U=$UMASK_VAL"

cat > /etc/systemd/system/rclone-mount-obs.service <<EOF
[Unit]
Description=Rclone Mount OBS
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/rclone mount obs:${BUCKET_NAME} ${MOUNT_PATH} \
  --config /etc/rclone/rclone.conf \
  --allow-other \
  --uid $SMB_UID \
  --gid $SMB_GID \
  --dir-perms $DIR_PERMS \
  --file-perms $FILE_PERMS \
  --umask $UMASK_VAL \
  --vfs-cache-mode full \
  --vfs-cache-max-age $VFS_CACHE_AGE \
  --vfs-cache-max-size $VFS_CACHE_SIZE \
  --dir-cache-time 168h \
  --buffer-size 256M
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Mount dizininin sahipliğini SMB kullanıcısına ver
sudo chown -R "$SMB_USER:$SMB_USER" "$MOUNT_PATH"
sudo chmod -R "$DIR_PERMS" "$MOUNT_PATH"

sudo systemctl daemon-reload
sudo systemctl enable rclone-mount-obs

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

if curl -s -u ${RC_USER}:${RC_PASS} http://localhost:5572/metrics > /dev/null 2>&1; then
    echo "✅ Rclone RC API çalışıyor."
else
    echo "❌ Rclone RC API çalışmıyor! Logları kontrol edin: sudo journalctl -u rclone-rcd -f"
fi

if mount | grep -q "$MOUNT_PATH"; then
    echo "✅ Rclone mount başarılı."
else
    echo "❌ Rclone mount başarısız! Logları kontrol edin: sudo journalctl -u rclone-mount-obs -f"
fi

if sudo systemctl is-active --quiet smbd; then
    echo "✅ Samba servisi çalışıyor."
else
    echo "❌ Samba servisi çalışmıyor! Logları kontrol edin: sudo journalctl -u smbd -f"
fi

if docker ps | grep -q "pacs-prometheus"; then
    echo "✅ Prometheus çalışıyor."
else
    echo "❌ Prometheus çalışmıyor! Logları kontrol edin: docker logs pacs-prometheus"
fi

if docker ps | grep -q "pacs-grafana"; then
    echo "✅ Grafana çalışıyor."
else
    echo "❌ Grafana çalışmıyor! Logları kontrol edin: docker logs pacs-grafana"
fi

if docker ps | grep -q "pacs-alertmanager"; then
    if curl -s http://localhost:9393 > /dev/null 2>&1; then
        echo "✅ Alertmanager UI çalışıyor."
    else
        echo "❌ Alertmanager UI çalışmıyor! Logları kontrol edin: docker logs pacs-alertmanager"
    fi
else
    echo "❌ Alertmanager container'ı çalışmıyor!"
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
echo "   Private IP: $PRIVATE_IP"
echo "   Public IP: $PUBLIC_IP"
echo "   SMB Paylaşımı: \\\\$PUBLIC_IP\\PACS_Archive"
echo "   SMB Kullanıcı: $SMB_USER"
echo "   SMB Şifre: (girilen şifre)"
echo ""
echo "   Grafana: http://$PUBLIC_IP:3000 (Kullanıcı: admin | Şifre: admin)"
echo "   Prometheus: http://$PUBLIC_IP:9090"
echo "   Rclone Web GUI: http://$PUBLIC_IP:5572 ($RC_USER/$RC_PASS)"
echo "   Alertmanager: http://$PUBLIC_IP:9393"
echo ""
echo "📋 Servis Yönetimi:"
echo "   Systemd: sudo systemctl status rclone-mount-obs rclone-rcd smbd"
echo "   Docker: cd /opt/pacs-gateway && docker compose ps"
echo ""
echo "📁 Mount Dizini: $MOUNT_PATH"
echo "📦 VFS Cache Süresi: $VFS_CACHE_AGE"
echo "📦 VFS Cache Boyutu: $VFS_CACHE_SIZE"
echo "🔐 İzinler: Dizin=$DIR_PERMS, Dosya=$FILE_PERMS, Umask=$UMASK_VAL"
echo ""
echo "📝 HATA KONTROLÜ (Loglar):"
echo "   Rclone mount: sudo journalctl -u rclone-mount-obs -n 10 --no-pager"
echo "   Samba:        sudo journalctl -u smbd -n 10 --no-pager"
echo "   Docker:       cd /opt/pacs-gateway && docker compose logs --tail=10"
echo ""
echo ""
echo "   ██████╗██╗      ██████╗ ██╗   ██╗███████╗"
echo "  ██╔════╝██║     ██╔═══██╗██║   ██║██╔════╝"
echo "  ██║     ██║     ██║   ██║██║   ██║███████╗"
echo "  ██║     ██║     ██║   ██║██║   ██║╚════██║"
echo "  ╚██████╗███████╗╚██████╔╝╚██████╔╝███████║"
echo "   ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝"
echo "=============================================="
echo "   🚀 Developed by Furkan YIGIT | Cloud Solution Architect | Clous Cloud"
echo "=============================================="
