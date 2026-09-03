# PACS Gateway - One-Click Deployment

Bu repo, hastane PACS verilerini Huawei Cloud OBS'ye taşıyan, izlenebilir ve alarmlı bir gateway sisteminin kurulumunu otomatikleştirir.

## Özellikler
- Rclone ile OBS mount
- Samba ile Windows SMB paylaşımı
- Prometheus + Grafana ile izleme
- Alertmanager ile e-posta alarmı
- Tek script ile kurulum

## Gereksinimler
- Ubuntu 22.04 veya 24.04
- Internet bağlantısı
- Huawei OBS Access Key ve Secret Key

## Kurulum
```bash
cd /opt/pacs-gateway
chmod +x deploy.sh
./deploy.sh
