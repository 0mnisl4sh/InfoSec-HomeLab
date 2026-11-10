#!/usr/bin/env bash
# Отзывает ранее выпущенный сертификат и пересобирает CRL.
# Использование: ca-revoke.sh <CN> [причина]
#   причины: unspecified keyCompromise CACompromise affiliationChanged
#            superseded cessationOfOperation certificateHold
set -euo pipefail

PKI_DIR="${PKI_DIR:-/pki}"
CA_CNF="${CA_CNF:-/etc/lab-ca/openssl.cnf}"
CA_PASSPHRASE="${CA_PASSPHRASE:-labpass}"

INT_DIR="$PKI_DIR/intermediate"
ISSUED_DIR="$PKI_DIR/issued"

if [ $# -lt 1 ]; then
  echo "Использование: $(basename "$0") <CN> [причина]" >&2
  exit 1
fi

CN="$1"
REASON="${2:-keyCompromise}"
CERT="$ISSUED_DIR/$CN/cert.pem"

if [ ! -f "$CERT" ]; then
  echo "[!] Нет сертификата $CERT" >&2
  exit 1
fi

echo "[*] Отзыв $CN (причина: $REASON)"
CA_DIR="$INT_DIR" openssl ca -config "$CA_CNF" \
  -revoke "$CERT" -crl_reason "$REASON" \
  -passin "pass:$CA_PASSPHRASE"

echo "[*] Пересборка CRL"
CA_DIR="$INT_DIR" openssl ca -config "$CA_CNF" -gencrl \
  -passin "pass:$CA_PASSPHRASE" -out "$INT_DIR/crl/intermediate.crl.pem"
cp "$INT_DIR/crl/intermediate.crl.pem" "$ISSUED_DIR/lab-intermediate.crl"
chmod 644 "$ISSUED_DIR/lab-intermediate.crl"

echo
echo "[*] Текущий список отозванных:"
openssl crl -in "$INT_DIR/crl/intermediate.crl.pem" -noout -text | \
  grep -A3 "Serial Number" || echo "    (пусто)"

echo
echo "[*] Проверка с учётом CRL (должна упасть с 'certificate revoked'):"
cat "$INT_DIR/certs/ca-chain.cert.pem" "$INT_DIR/crl/intermediate.crl.pem" > /tmp/verify-bundle.pem
openssl verify -crl_check -CAfile /tmp/verify-bundle.pem "$CERT" || true
rm -f /tmp/verify-bundle.pem

echo
echo "[i] Статус в базе УЦ (R = revoked):"
grep -F "CN=$CN" "$INT_DIR/index.txt" | awk '{print $1, $2, $3}'
