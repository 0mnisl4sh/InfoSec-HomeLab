#!/usr/bin/env bash
set -euo pipefail

LAB_FQDN="${LAB_FQDN:-app-01.lab}"
LAB_ADMIN_USER="${LAB_ADMIN_USER:-labadmin}"
LAB_ADMIN_PASSWORD="${LAB_ADMIN_PASSWORD:-labadmin}"
LAB_ADMIN_PUBKEY="${LAB_ADMIN_PUBKEY:-}"
CA_CERTS_DIR=/etc/nginx/certs   # сюда примонтирован каталог issued из УЦ (ro)
SSL_DIR=/etc/nginx/ssl

echo "[app-01] старт, FQDN=$LAB_FQDN"

# ---------- журналирование ----------
# Без rsyslog в контейнере не будет /var/log/auth.log, а он нужен
# для разбора SSH-логинов и для агента Wazuh.
rsyslogd || echo "[app-01] rsyslogd не стартовал, /var/log/auth.log будет пустым"

# ---------- SSH ----------
ssh-keygen -A >/dev/null
mkdir -p /run/sshd

if ! id "$LAB_ADMIN_USER" >/dev/null 2>&1; then
  echo "[app-01] создаю администратора $LAB_ADMIN_USER"
  useradd -m -s /bin/bash -G sudo "$LAB_ADMIN_USER"
  echo "$LAB_ADMIN_USER:$LAB_ADMIN_PASSWORD" | chpasswd
fi

if [ -n "$LAB_ADMIN_PUBKEY" ]; then
  home="/home/$LAB_ADMIN_USER"
  install -d -m 700 -o "$LAB_ADMIN_USER" -g "$LAB_ADMIN_USER" "$home/.ssh"
  echo "$LAB_ADMIN_PUBKEY" > "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
  chown "$LAB_ADMIN_USER:$LAB_ADMIN_USER" "$home/.ssh/authorized_keys"
  echo "[app-01] публичный ключ администратора установлен"
fi

# ---------- доверие лабораторному УЦ ----------
if [ -f "$CA_CERTS_DIR/lab-root-ca.crt" ]; then
  cp "$CA_CERTS_DIR/lab-root-ca.crt" /usr/local/share/ca-certificates/lab-root-ca.crt
  update-ca-certificates >/dev/null 2>&1 || true
  echo "[app-01] корневой сертификат лабы добавлен в доверенные"
fi

# ---------- TLS для nginx ----------
mkdir -p "$SSL_DIR"
if [ ! -f "$SSL_DIR/privkey.pem" ]; then
  if [ -f "$CA_CERTS_DIR/$LAB_FQDN/fullchain.pem" ]; then
    echo "[app-01] беру сертификат, выпущенный УЦ"
    cp "$CA_CERTS_DIR/$LAB_FQDN/fullchain.pem" "$SSL_DIR/fullchain.pem"
    cp "$CA_CERTS_DIR/$LAB_FQDN/privkey.pem"   "$SSL_DIR/privkey.pem"
  else
    echo "[app-01] сертификата от УЦ нет — генерирую самоподписанный (браузер будет ругаться, так и задумано)"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 \
      -subj "/C=RU/O=InfoSec HomeLab/CN=$LAB_FQDN" \
      -addext "subjectAltName=DNS:$LAB_FQDN,DNS:localhost,IP:127.0.0.1" \
      -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem" 2>/dev/null
  fi
  chmod 600 "$SSL_DIR/privkey.pem"
fi

# ---------- контент ----------
if [ ! -f /var/www/html/index.html ]; then
  cat > /var/www/html/index.html <<EOF
<!doctype html>
<meta charset="utf-8">
<title>app-01</title>
<h1>app-01.lab</h1>
<p>Учебный сервер. SSH: порт 2222 на хосте. HTTP: 8080. HTTPS: 8443.</p>
EOF
fi

echo "[app-01] запускаю nginx"
nginx -t
nginx

echo "[app-01] запускаю sshd (foreground)"
# Без -e: sshd пишет в syslog (→ /var/log/auth.log), а не в stderr контейнера
exec /usr/sbin/sshd -D
