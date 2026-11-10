#!/usr/bin/env bash
# Выпускает серверный сертификат промежуточным УЦ.
# Использование: ca-issue.sh <CN> [доп-SAN ...]
#   ca-issue.sh app-01.lab localhost 127.0.0.1
# Срок по умолчанию 397 дней (максимум, который принимают браузеры).
set -euo pipefail

PKI_DIR="${PKI_DIR:-/pki}"
CA_CNF="${CA_CNF:-/etc/lab-ca/openssl.cnf}"
CA_PASSPHRASE="${CA_PASSPHRASE:-labpass}"
ORG="${CA_ORG:-InfoSec HomeLab}"
COUNTRY="${CA_COUNTRY:-RU}"
DAYS="${CERT_DAYS:-397}"

INT_DIR="$PKI_DIR/intermediate"
# Конфиг УЦ читает каталог из $ENV::CA_DIR — нужен всем вызовам openssl ниже.
export CA_DIR="$INT_DIR"

if [ $# -lt 1 ]; then
  echo "Использование: $(basename "$0") <CN> [доп-SAN ...]" >&2
  exit 1
fi
if [ ! -f "$INT_DIR/certs/ca.cert.pem" ]; then
  echo "[!] УЦ не инициализирован. Сначала: ca-init.sh" >&2
  exit 1
fi

CN="$1"; shift
OUT="$PKI_DIR/issued/$CN"
mkdir -p "$OUT"

# Собираем subjectAltName: CN всегда внутри, плюс всё, что передали аргументами.
# Значения вида 1.2.3.4 уходят в IP:, остальное в DNS:.
san_entry() {
  case "$1" in
    *[!0-9.]*) echo "DNS:$1" ;;
    *)         echo "IP:$1"  ;;
  esac
}
SAN="$(san_entry "$CN")"
for extra in "$@"; do
  SAN="$SAN,$(san_entry "$extra")"
done

echo "[*] CN=$CN"
echo "[*] SAN=$SAN"

echo "[*] Приватный ключ (2048 бит, без пароля — nginx должен стартовать без ввода пароля)"
openssl genrsa -out "$OUT/privkey.pem" 2048 2>/dev/null
chmod 600 "$OUT/privkey.pem"

echo "[*] CSR"
openssl req -config "$CA_CNF" -new -sha256 \
  -key "$OUT/privkey.pem" \
  -subj "/C=$COUNTRY/O=$ORG/CN=$CN" \
  -out "$OUT/request.csr.pem"

# Расширения для конкретного сертификата
EXT="$(mktemp)"
trap 'rm -f "$EXT"' EXIT
cat > "$EXT" <<EOF
basicConstraints       = CA:FALSE
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = $SAN
EOF

echo "[*] Подпись промежуточным УЦ на $DAYS дней"
openssl ca -config "$CA_CNF" -batch -notext -md sha256 \
  -extfile "$EXT" -days "$DAYS" \
  -passin "pass:$CA_PASSPHRASE" \
  -in "$OUT/request.csr.pem" -out "$OUT/cert.pem"

# chain    = intermediate + root  (для проверки клиентом)
# fullchain= сертификат + intermediate (именно это отдаёт nginx)
cp "$INT_DIR/certs/ca-chain.cert.pem" "$OUT/chain.pem"
cat "$OUT/cert.pem" "$INT_DIR/certs/ca.cert.pem" > "$OUT/fullchain.pem"
chmod 644 "$OUT/cert.pem" "$OUT/chain.pem" "$OUT/fullchain.pem"

echo "[*] Проверка цепочки"
openssl verify -CAfile "$INT_DIR/certs/ca-chain.cert.pem" "$OUT/cert.pem"

echo "[*] Сверка ключа и сертификата (хэши должны совпасть)"
k=$(openssl rsa -in "$OUT/privkey.pem" -noout -modulus | openssl sha256 | awk '{print $NF}')
c=$(openssl x509 -in "$OUT/cert.pem" -noout -modulus | openssl sha256 | awk '{print $NF}')
[ "$k" = "$c" ] && echo "    OK: $k" || { echo "    НЕ СОВПАДАЮТ"; exit 1; }

echo
openssl x509 -in "$OUT/cert.pem" -noout -subject -issuer -dates -ext subjectAltName
echo
echo "[+] Файлы в $OUT:"
echo "    privkey.pem   — приватный ключ (ssl_certificate_key)"
echo "    cert.pem      — только сертификат"
echo "    fullchain.pem — сертификат + intermediate (ssl_certificate)"
echo "    chain.pem     — intermediate + root (для openssl verify / клиентов)"
