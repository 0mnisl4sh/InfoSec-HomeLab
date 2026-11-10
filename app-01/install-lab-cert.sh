#!/usr/bin/env bash
# Ставит в nginx сертификат, выпущенный лабораторным УЦ, и перечитывает конфиг.
# Использование (внутри app-01): install-lab-cert [CN]
set -euo pipefail

CN="${1:-${LAB_FQDN:-app-01.lab}}"
SRC="/etc/nginx/certs/$CN"
DST="/etc/nginx/ssl"

if [ ! -f "$SRC/fullchain.pem" ]; then
  echo "[!] Нет $SRC/fullchain.pem" >&2
  echo "    Сначала в контейнере ca: ca-issue $CN localhost 127.0.0.1" >&2
  exit 1
fi

cp "$SRC/fullchain.pem" "$DST/fullchain.pem"
cp "$SRC/privkey.pem"   "$DST/privkey.pem"
chmod 600 "$DST/privkey.pem"

nginx -t
nginx -s reload

echo "[+] Сертификат $CN установлен. Проверка:"
echo "    openssl s_client -connect localhost:443 -servername $CN </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates"
