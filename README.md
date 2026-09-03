# 🏥 PACS Gateway - One-Click Deployment

Bu repo, hastane PACS verilerini **Huawei Cloud OBS**'ye taşıyan, **izlenebilir**, **alarmlı** ve **yüksek erişilebilir** (HA) bir gateway sisteminin kurulumunu otomatikleştirir.

---

## 📌 Özellikler

- ✅ **Rclone** ile OBS mount (VFS cache desteği)
- ✅ **Samba** ile Windows SMB paylaşımı
- ✅ **Prometheus + Grafana** ile gerçek zamanlı izleme
- ✅ **Alertmanager** ile e-posta alarmı
- ✅ **Node Exporter** ile sistem metrikleri
- ✅ **Tek script** ile sıfırdan kurulum
- ✅ **Systemd** ile otomatik başlatma
- ✅ **Docker Compose** ile container yönetimi

---

## 🏗️ Mimari

Sistem iki ana katmandan oluşur:

**1. Host'ta (Systemd) Çalışan Servisler**
- **Rclone mount** (`rclone-mount-obs.service`) → OBS bucket'ını `/mnt/pacs-hot/archive` dizinine bağlar
- **Rclone RC API** (`rclone-rcd.service`) → Metrik yayınlar (`:5572/metrics`)
- **Samba** (`smbd`) → `/mnt/pacs-hot/archive` dizinini Windows SMB ile paylaşır

**2. Docker Compose ile Çalışan Servisler**
- **Prometheus** → Metrik toplar
- **Grafana** → Görselleştirme ve alarm
- **Alertmanager** → E-posta alarm yönetimi
- **Node Exporter** → Sistem metrikleri (disk, CPU)

| Bileşen | Çalışma Ortamı | Başlatma |
|---------|---------------|----------|
| Rclone mount (OBS) | Host | Systemd |
| Rclone RC API | Host | Systemd |
| Samba (SMB) | Host | Systemd |
| Prometheus | Docker | Compose |
| Grafana | Docker | Compose |
| Alertmanager | Docker | Compose |
| Node Exporter | Docker | Compose |

### Veri Akışı

```
Huawei OBS → Rclone mount (/mnt/pacs-hot/archive) → Samba → Windows SMB (\\IP\PACS_Archive)
```

### İzleme ve Alarm Akışı

```
Rclone RC API (:5572/metrics) → Prometheus (scrape) → Grafana (görselleştirme) → Alertmanager (e-posta alarm)
```

### Klasör Yapısı

```
pacs-gateway/
├── config/
│   └── rclone.conf                # Rclone yapılandırması (OBS bağlantısı)
├── prometheus/
│   ├── prometheus.yml             # Prometheus ana config
│   └── alert.rules.yml            # Alarm kuralları
├── alertmanager/
│   └── alertmanager.yml           # Alertmanager config (SMTP)
├── grafana/
│   ├── grafana.ini                # Grafana config (SMTP)
│   └── dashboards/
│       └── rclone-dashboard.json  # Grafana dashboard (opsiyonel)
├── systemd/
│   ├── rclone-rcd.service
│   └── rclone-mount-obs.service
├── docker-compose.yml             # Docker servisleri
├── deploy.sh                      # Tek komutla kurulum script'i
├── README.md                      # Kurulum rehberi
└── requirements.txt               # Sistem gereksinimleri (opsiyonel)
```

---

## 📋 Gereksinimler

- Ubuntu **22.04** veya **24.04** (temiz kurulum önerilir)
- Root veya sudo erişimi
- İnternet bağlantısı (Docker imajları ve paketler için)
- Huawei Cloud OBS **Access Key** ve **Secret Key**
- OBS **bucket adı** ve **endpoint** bilgisi
- SMTP mail hesabı (alarm bildirimleri için)

---

## 🚀 Kurulum

### 1. Repoyu Klonla

```bash
git clone https://github.com/yigitfurkann/pacs-gateway.git /opt/pacs-gateway
cd /opt/pacs-gateway
```

### 2. Kurulum Script'ini Çalıştır

```bash
chmod +x deploy.sh
./deploy.sh
```

### 3. Script'in Sorduğu Bilgileri Gir

Script interaktif olarak aşağıdaki bilgileri soracaktır:

| Soru | Açıklama | Örnek |
|------|----------|-------|
| Huawei OBS Access Key | OBS erişim anahtarı | `YOUR_ACCES_KEY` |
| Huawei OBS Secret Key | OBS gizli anahtarı | `YOUR_SECRET_KEY` |
| OBS Endpoint | OBS bölge endpoint'i | `obs.tr-west-1.myhuaweicloud.com` |
| OBS Bucket Adı | Kullanılacak bucket | `bucket-name` |
| Samba Kullanıcı Adı | SMB kullanıcısı (varsayılan: pacsuser) | `pacsuser` |
| Samba Şifresi | SMB şifresi  | `` |
| SMTP Mail Adresi | Alarm gönderen mail | `admin@hastane.com` |
| SMTP Uygulama Şifresi | Gmail uygulama şifresi | `YOUR_APP_PASSWORD` |
| Alert E-posta Adresi | Alarm alan mail | `pacs-admin@hastane.com` |
| Mount Dizini | Mount noktası (varsayılan: /mnt/pacs-hot/archive) | `[Enter]` |

Kurulum tamamlandığında aşağıdaki gibi bir çıktı alacaksınız:

```
==============================================
Kurulum tamamlandı!
SMB Paylaşımı: \\172.31.254.86\PACS_Archive
Grafana: http://172.31.254.86:3000 (admin/admin)
Prometheus: http://172.31.254.86:9090
==============================================
```

> `deploy.sh` tüm systemd servislerini ve Docker container'larını otomatik olarak başlatır. Kurulumdan sonra ekstra bir işlem yapmanız gerekmez — sistem doğrudan çalışır durumda olacaktır.

---

## ▶️ Uygulama Nasıl Çalıştırılır

Kurulum tamamlandıktan sonra servisler otomatik başlar ve sunucu her yeniden başlatıldığında (systemd + Docker restart policy sayesinde) kendiliğinden ayağa kalkar. Manuel müdahale sadece servisleri durdurmak, güncellemek veya sorun gidermek istediğinizde gerekir.

### Systemd Servisleri (Rclone ve Samba)

```bash
# Servisleri başlat
sudo systemctl start rclone-mount-obs rclone-rcd smbd

# Servisleri durdur
sudo systemctl stop rclone-mount-obs rclone-rcd smbd

# Servis durumunu kontrol et
sudo systemctl status rclone-mount-obs rclone-rcd smbd

# Servis loglarını izle
sudo journalctl -u rclone-mount-obs -f
sudo journalctl -u rclone-rcd -f
sudo journalctl -u smbd -f
```

### Docker Servisleri (Prometheus, Grafana, Alertmanager, Node Exporter)

```bash
cd /opt/pacs-gateway

# Tüm container'ları başlat
docker compose up -d

# Container'ları durdur
docker compose down

# Container'ları yeniden başlat
docker compose restart

# Logları izle
docker compose logs -f
docker compose logs -f prometheus
docker compose logs -f grafana
```

---

## 🌐 Erişim Noktaları

| Servis | URL / Bilgi |
|--------|-------------|
| SMB Paylaşımı | `\\<SUNUCU_IP>\PACS_Archive`<br>Kullanıcı: `pacsuser`<br>Şifre: `` |
| Grafana | `http://<SUNUCU_IP>:3000`<br>Kullanıcı: `admin`<br>Şifre: `admin` |
| Prometheus | `http://<SUNUCU_IP>:9090` |
| Rclone Web GUI | `http://<SUNUCU_IP>:5572`<br>Kullanıcı: `monitor`<br>Şifre: `` |
| Alertmanager | `http://<SUNUCU_IP>:9393` |

---

## 🪟 Windows Makineden Erişim (SMB)

### 1. Erişimi Kontrol Et

```cmd
ping ECS_PRIVATE
```

### 2. SMB Paylaşımına Bağlan

```cmd
net use Z: \\172.31.254.86\PACS_Archive /user:pacsuser "password" /persistent:yes
dir Z:\
```

Bu komut `Z:` sürücüsünü kalıcı olarak (`/persistent:yes`) bağlar; Windows her açıldığında otomatik olarak yeniden bağlanır.

### 3. Bağlantı Sorunları

**Hata 53 (Network path not found):**
- Güvenlik grubunda 445 portu kapalı olabilir.
- Huawei Cloud konsolunda sunucunun güvenlik grubuna **Inbound TCP 445** ekleyip kaynağı Windows sunucusunun özel IP'si (ör. `172.31.254.120/32`) veya gerekirse `0.0.0.0/0` yapın.

**Hata 5 (Access denied):**
- Kullanıcı adı veya şifre yanlış olabilir.
- Samba kullanıcısını doğrulayın: `sudo pdbedit -L` ile `pacsuser` var mı kontrol edin.
- Şifreyi sıfırlayın: `sudo smbpasswd -a pacsuser`

### 4. Samba Yapılandırmasını Kontrol Et (Sunucu Tarafı)

```bash
sudo cat /etc/samba/smb.conf | grep -A 10 "PACS_Archive"
```

Çıktıda şu satırlar olmalı:

```ini
[PACS_Archive]
    path = /mnt/pacs-hot/archive
    browseable = yes
    read only = no
    guest ok = no
    valid users = pacsuser
    force user = pacsuser
    create mask = 0644
    directory mask = 0755
```

### 5. Güvenlik Grubu Ayarları

Huawei Cloud konsolunda sunucunun güvenlik grubuna aşağıdaki kuralları ekleyin:

| Yön | Protokol | Port | Kaynak | Açıklama |
|-----|----------|------|--------|----------|
| Inbound | TCP | 445 | Windows sunucusunun özel IP'si (ör. `172.31.254.120/32`) | SMB erişimi |
| Inbound | TCP | 139 | Windows sunucusunun özel IP'si | NetBIOS/SMB |

### 6. Farklı Bölge / Public IP ile Erişim

Windows sunucusu farklı bir ağdaysa ve public IP üzerinden erişecekse:

1. Sunucunun güvenlik grubuna public IP'den 445 portuna izin verin.
2. Samba config dosyasını düzenleyin:

```bash
sudo nano /etc/samba/smb.conf
```

`[global]` bölümüne şunu ekleyin (eğer yoksa):

```ini
interfaces = 0.0.0.0/0
bind interfaces only = no
```

3. Samba'yı yeniden başlatın:

```bash
sudo systemctl restart smbd
```

### 7. Test Dosyası Oluşturma

Windows'tan `Z:` sürücüsüne bir test dosyası oluşturun:

```cmd
echo "Windows test" > Z:\win_test2.txt
```

Sunucuda kontrol edin:

```bash
ls -la /mnt/pacs-hot/archive/
```

### 8. Sorun Devam Ederse — Logları İncele

```bash
sudo tail -f /var/log/samba/log.smbd
```

---

## ⚠️ Alarm Kuralları (Alert Rules)

Sistem aşağıdaki durumlar için alarm gönderir:

| Alarm | Açıklama |
|-------|----------|
| RcloneServiceDown | Rclone servisi çöktü |
| SambaServiceDown | Samba servisi çalışmıyor |
| RcloneTransferStalled | Transfer 5 dakikadır durmuş |
| RcloneLowThroughput | Transfer hızı 1 MB/s altında |
| RcloneHighErrorRate | Yüksek hata oranı |
| HotStorageDiskSpaceWarning | Disk %80 dolu (uyarı) |
| HotStorageDiskSpaceCritical | Disk %90 dolu (kritik) |
| RcloneBufferUsageHigh | VFS buffer %85 dolu |
| SambaConnectionFailed | SMB bağlantı hatası |

Tüm alarmlar, Alertmanager üzerinden yapılandırılan e-posta adresine gönderilir.

---

## 🛠️ Sorun Giderme (Troubleshooting)

### 1. Windows SMB'ye bağlanamıyorum

```bash
# Samba servisini kontrol et
sudo systemctl status smbd

# Güvenlik duvarını kontrol et
sudo ufw allow 139,445/tcp

# Yerel test
smbclient //localhost/PACS_Archive -U pacsuser
```

### 2. Mount noktasında dosya görünmüyor

```bash
# Rclone mount servisini kontrol et
sudo systemctl status rclone-mount-obs

# Logları incele
sudo journalctl -u rclone-mount-obs -f

# Rclone config'i kontrol et
rclone config show obs
```

### 3. Grafana'da metrik gelmiyor

```bash
# Prometheus target'larını kontrol et
http://<SUNUCU_IP>:9090/targets

# Rclone RC API'yi test et
curl -u monitor:"password" http://localhost:5572/metrics
```

### 4. Alarm e-postası gelmiyor

```bash
# Alertmanager config'ini kontrol et
cat /opt/pacs-gateway/alertmanager/alertmanager.yml

# Grafana SMTP ayarlarını kontrol et
cat /opt/pacs-gateway/grafana/grafana.ini

# Grafana container'ından SMTP testi
docker exec -it pacs-grafana curl -v smtp.gmail.com:587
```

---

## 🗑️ Tamamen Kaldırma

```bash
# 1. Systemd servislerini durdur ve devre dışı bırak
sudo systemctl disable --now rclone-mount-obs rclone-rcd smbd

# 2. Docker container'larını kaldır
cd /opt/pacs-gateway && docker compose down -v

# 3. Tüm dosyaları sil
sudo rm -rf /opt/pacs-gateway /mnt/pacs-hot /etc/rclone
```

---

## 🤝 Katkıda Bulunma

Pull request'ler ve issue'lar açıktır. Lütfen katkıda bulunmaktan çekinmeyin.

---

## 📄 Lisans

MIT License
