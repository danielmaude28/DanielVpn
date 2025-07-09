#!/bin/bash

# === Cek apakah whiptail tersedia ===
if ! command -v whiptail &> /dev/null; then
    apt update && apt install -y whiptail
fi

# === Fungsi Install Trojan-Go ===
install_trojan() {
    DOMAIN=$(whiptail --inputbox "Masukkan domain (sudah diarahkan ke IP server):" 10 60 --title "Domain" 3>&1 1>&2 2>&3)
    EMAIL=$(whiptail --inputbox "Masukkan email untuk SSL Let's Encrypt:" 10 60 --title "Email" 3>&1 1>&2 2>&3)

    TROJAN_DIR="/etc/trojan-go"
    PORT=443
    UUID=$(cat /proc/sys/kernel/random/uuid)

    if ! ping -c1 $DOMAIN &>/dev/null; then
        whiptail --msgbox "❌ Domain $DOMAIN tidak resolve ke IP server. Periksa DNS!" 10 60
        return
    fi

    apt update -y && apt upgrade -y
    apt install -y curl unzip nginx socat cron certbot python3-certbot-nginx

    rm -f /etc/nginx/sites-enabled/default
    mkdir -p /var/www/html
    echo "<h1>SSL OK</h1>" > /var/www/html/index.html

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

    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL

    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        whiptail --msgbox "❌ Gagal mendapatkan SSL. Pastikan port 80 terbuka dan domain valid." 10 60
        return
    fi

    mkdir -p $TROJAN_DIR
    cd /tmp
    VERSION=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" | grep tag_name | cut -d '"' -f4)
    curl -L -o trojan-go.zip https://github.com/p4gefau1t/trojan-go/releases/download/${VERSION}/trojan-go-linux-amd64.zip
    unzip trojan-go.zip -d $TROJAN_DIR

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

    systemctl daemon-reload
    systemctl enable trojan-go
    systemctl restart trojan-go

    if command -v ufw &> /dev/null; then
        ufw allow 80
        ufw allow 443
        ufw reload
    fi

    LINK="trojan-go://$UUID@$DOMAIN:$PORT?type=ws&path=%2Fvpnstealth&host=www.cloudflare.com&sni=www.cloudflare.com#VPN-Stealth"

    whiptail --title "✅ Trojan-Go Berhasil Terpasang" --msgbox "UUID : $UUID\nDomain: $DOMAIN\n\nConfig:\n$LINK" 15 70
}

# === Fungsi Uninstall ===
uninstall_trojan() {
    systemctl stop trojan-go
    systemctl disable trojan-go
    rm -f /etc/systemd/system/trojan-go.service
    rm -rf /etc/trojan-go
    rm -rf /etc/nginx/sites-available/*
    rm -rf /etc/nginx/sites-enabled/*
    systemctl reload nginx
    whiptail --msgbox "✅ Trojan-Go berhasil dihapus." 10 50
}

# === Restart Trojan ===
restart_trojan() {
    systemctl restart trojan-go
    whiptail --msgbox "🔄 Trojan-Go berhasil direstart." 10 50
}

# === Lihat Log ===
view_log() {
    journalctl -u trojan-go -n 50 --no-pager > /tmp/trojanlog
    whiptail --textbox /tmp/trojanlog 20 70
}

# === Menu ===
while true; do
    CHOICE=$(whiptail --title "Trojan-Go Stealth Manager" --menu "Pilih aksi:" 15 60 5 \
        1 "Install Trojan-Go" \
        2 "Uninstall Trojan-Go" \
        3 "Restart Trojan-Go" \
        4 "Lihat Log Trojan-Go" \
        5 "Keluar" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) install_trojan ;;
        2) uninstall_trojan ;;
        3) restart_trojan ;;
        4) view_log ;;
        5) clear; exit ;;
    esac
done
