#!/usr/bin/env bash
# Создаёт двухуровневый УЦ: Root CA -> Intermediate CA.
# Повторный запуск ничего не портит: если УЦ уже есть, скрипт выходит.
set -euo pipefail

PKI_DIR="${PKI_DIR:-/pki}"
CA_CNF="${CA_CNF:-/etc/lab-ca/openssl.cnf}"
CA_PASSPHRASE="${CA_PASSPHRASE:-labpass}"
ORG="${CA_ORG:-InfoSec HomeLab}"
COUNTRY="${CA_COUNTRY:-RU}"

ROOT_DIR="$PKI_DIR/root"
INT_DIR="$PKI_DIR/intermediate"
ISSUED_DIR="$PKI_DIR/issued"

if [ -f "$INT_DIR/certs/ca.cert.pem" ]; then
  echo "[=] УЦ уже инициализирован в $PKI_DIR. Удали каталог, если нужно с нуля."
  exit 0
fi

make_ca_dirs() {
  local d="$1"
  mkdir -p "$d/certs" "$d/crl" "$d/newcerts" "$d/private"
  chmod 700 "$d/private"
  : > "$d/index.txt"
  echo "unique_subject = no" > "$d/index.txt.attr"
  echo 1000 > "$d/serial"
  echo 1000 > "$d/crlnumber"
}

echo "[*] Каталоги PKI в $PKI_DIR"
make_ca_dirs "$ROOT_DIR"
make_ca_dirs "$INT_DIR"
mkdir -p "$ISSUED_DIR"

# ---------- Root CA ----------
echo "[*] Ключ корневого УЦ (4096 бит, зашифрован)"
openssl genrsa -aes256 -passout "pass:$CA_PASSPHRASE" -out "$ROOT_DIR/private/ca.key.pem" 4096 2>/dev/null
chmod 400 "$ROOT_DIR/private/ca.key.pem"

echo "[*] Самоподписанный сертификат корневого УЦ (20 лет)"
CA_DIR="$ROOT_DIR" openssl req -config "$CA_CNF" \
  -key "$ROOT_DIR/private/ca.key.pem" -passin "pass:$CA_PASSPHRASE" \
  -new -x509 -days 7300 -sha256 -extensions v3_ca \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ORG Root CA" \
  -out "$ROOT_DIR/certs/ca.cert.pem"
chmod 444 "$ROOT_DIR/certs/ca.cert.pem"

# ---------- Intermediate CA ----------
echo "[*] Ключ и запрос промежуточного УЦ"
openssl genrsa -aes256 -passout "pass:$CA_PASSPHRASE" -out "$INT_DIR/private/ca.key.pem" 4096 2>/dev/null
chmod 400 "$INT_DIR/private/ca.key.pem"

CA_DIR="$INT_DIR" openssl req -config "$CA_CNF" -new -sha256 \
  -key "$INT_DIR/private/ca.key.pem" -passin "pass:$CA_PASSPHRASE" \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ORG Intermediate CA" \
  -out "$INT_DIR/certs/ca.csr.pem"

echo "[*] Подпись промежуточного УЦ корневым (10 лет)"
CA_DIR="$ROOT_DIR" openssl ca -config "$CA_CNF" -batch -notext -md sha256 \
  -extensions v3_intermediate_ca -days 3650 \
  -passin "pass:$CA_PASSPHRASE" \
  -in "$INT_DIR/certs/ca.csr.pem" -out "$INT_DIR/certs/ca.cert.pem"
chmod 444 "$INT_DIR/certs/ca.cert.pem"

echo "[*] Проверка: intermediate подписан root"
openssl verify -CAfile "$ROOT_DIR/certs/ca.cert.pem" "$INT_DIR/certs/ca.cert.pem"

echo "[*] Сборка цепочки доверия (intermediate + root)"
cat "$INT_DIR/certs/ca.cert.pem" "$ROOT_DIR/certs/ca.cert.pem" > "$INT_DIR/certs/ca-chain.cert.pem"
chmod 444 "$INT_DIR/certs/ca-chain.cert.pem"

echo "[*] Первый (пустой) CRL промежуточного УЦ"
CA_DIR="$INT_DIR" openssl ca -config "$CA_CNF" -gencrl \
  -passin "pass:$CA_PASSPHRASE" -out "$INT_DIR/crl/intermediate.crl.pem"

# Раздаём корневой сертификат и цепочку наружу (каталог issued примонтирован в app-01)
cp "$ROOT_DIR/certs/ca.cert.pem" "$ISSUED_DIR/lab-root-ca.crt"
cp "$INT_DIR/certs/ca-chain.cert.pem" "$ISSUED_DIR/lab-ca-chain.crt"
cp "$INT_DIR/crl/intermediate.crl.pem" "$ISSUED_DIR/lab-intermediate.crl"
chmod 644 "$ISSUED_DIR"/lab-*

echo
echo "[+] Готово."
echo "    Root CA:         $ROOT_DIR/certs/ca.cert.pem"
echo "    Intermediate CA: $INT_DIR/certs/ca.cert.pem"
echo "    Цепочка:         $INT_DIR/certs/ca-chain.cert.pem"
echo "    Для клиентов:    $ISSUED_DIR/lab-root-ca.crt"
echo
echo "    Дальше: ca-issue.sh app-01.lab localhost 127.0.0.1"
