#!/bin/bash

# === KONFIGURASI AWAL ===
DOMAIN="vpn.domainkamu.com"   # Ganti dengan domain kamu
EMAIL="emailkamu@gmail.com"   # Email untuk Let's Encrypt
TROJAN_DIR="/etc/trojan-go"
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)

# === UPDATE DAN INSTAL DEPENDENSI ===
apt update -y && apt upgrade -y
apt install -y curl unzip nginx socat cron certbot python3-certbot-nginx

# === SETUP NGINX UNTUK VERIFIKASI SSL ===
echo "Konfigurasi Nginx sementara untuk SSL..."
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# === DAPATKAN SSL VIA LET'S ENCRYPT ===
echo "Request SSL dari Let's Encrypt..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL

# === INSTALL TROJAN-GO ===
mkdir -p $TROJAN_DIR
cd /tmp
VERSION=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" | grep tag_name | cut -d '"' -f4)
curl -L -o trojan-go.zip https://github.com/p4gefau1t/trojan-go/releases/download/${VERSION}/trojan-go-linux-amd64.zip
unzip trojan-go.zip -d $TROJAN_DIR

# === BUAT KONFIGURASI STEALTH ===
echo "Buat config Trojan-Go (stealth mode)..."
cat > $TROJAN_DIR/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": $PORT,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$UUID"],
  "ssl": {
    "cert": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
    "key": "/etc/letsencrypt/live/$DOMAIN/privkey.pem",
    "sni": "www.cloudflare.com",
    "alpn": ["h2", "http/1.1"],
    "session_ticket": true,
    "reuse_session": true
  },
  "websocket": {
    "enabled": true,
    "path": "/vpnstealth",
    "host": "www.cloudflare.com"
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": true
  }
}
EOF

# === BUAT SYSTEMD SERVICE ===
echo "Buat service systemd untuk Trojan-Go..."
cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go Stealth Service
After=network.target

[Service]
Type=simple
ExecStart=$TROJAN_DIR/trojan-go -config "$TROJAN_DIR/config.json"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# === AKTIFKAN DAN JALANKAN ===
systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

# === OUTPUT ===
echo ""
echo "✅ Trojan-Go berhasil diinstal!"
echo "🔐 UUID: $UUID"
echo "🌐 Domain: $DOMAIN"
echo "🔗 Link (salin untuk user):"
echo "trojan-go://$UUID@$DOMAIN:$PORT?type=ws&path=%2Fvpnstealth&host=www.cloudflare.com&sni=www.cloudflare.com#VPN-Stealth"
