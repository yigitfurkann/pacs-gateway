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

## 🏗️ Sistem Mimarisi

| Bileşen | Çalışma Ortamı | Başlatma |
|---------|---------------|----------|
| Rclone mount (OBS) | Host | Systemd |
| Rclone RC API | Host | Systemd |
| Samba (SMB) | Host | Systemd |
| Prometheus | Docker | Compose |
| Grafana | Docker | Compose |
| Alertmanager | Docker | Compose |
| Node Exporter | Docker | Compose |

> Rclone ve Samba host'ta (systemd) çalışır. İzleme araçları Docker container'da çalışır.

---

## 📋 Gereksinimler

- Ubuntu **22.04** veya **24.04** (temiz kurulum önerilir)
- Root veya sudo erişimi
- İnternet bağlantısı (Docker imajları ve paketler için)
- Huawei Cloud OBS **Access Key** ve **Secret Key**
- OBS **bucket adı** ve **endpoint** bilgisi
- SMTP mail hesabı (alarm bildirimleri için)

---

## 🚀 Hızlı Kurulum

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
| Huawei OBS Access Key | OBS erişim anahtarı | `HPUAQ9P9NVALTGSWIWF9` |
| Huawei OBS Secret Key | OBS gizli anahtarı | `YOUR_SECRET_KEY` |
| OBS Endpoint | OBS bölge endpoint'i | `obs.tr-west-1.myhuaweicloud.com` |
| OBS Bucket Adı | Kullanılacak bucket | `furkan-test` |
| Samba Kullanıcı Adı | SMB kullanıcısı (varsayılan: pacsuser) | `pacsuser` |
| Samba Şifresi | SMB şifresi (varsayılan: 1Huawei9) | `1Huawei9` |
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

---

## 🔧 Servis Yönetimi

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
| SMB Paylaşımı | `\\<SUNUCU_IP>\PACS_Archive`<br>Kullanıcı: `pacsuser`<br>Şifre: `1Huawei9` |
| Grafana | `http://<SUNUCU_IP>:3000`<br>Kullanıcı: `admin`<br>Şifre: `admin` |
| Prometheus | `http://<SUNUCU_IP>:9090` |
| Rclone Web GUI | `http://<SUNUCU_IP>:5572`<br>Kullanıcı: `monitor`<br>Şifre: `1Huawei9` |
| Alertmanager | `http://<SUNUCU_IP>:9393` |

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
curl -u monitor:1Huawei9 http://localhost:5572/metrics
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
