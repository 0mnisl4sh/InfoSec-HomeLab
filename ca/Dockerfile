FROM alpine:3.20

RUN apk add --no-cache openssl bash ca-certificates

COPY etc/openssl.cnf /etc/lab-ca/openssl.cnf
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/ca-*.sh && \
    ln -s /usr/local/bin/ca-init.sh   /usr/local/bin/ca-init && \
    ln -s /usr/local/bin/ca-issue.sh  /usr/local/bin/ca-issue && \
    ln -s /usr/local/bin/ca-revoke.sh /usr/local/bin/ca-revoke

ENV PKI_DIR=/pki \
    CA_CNF=/etc/lab-ca/openssl.cnf

WORKDIR /pki

# Контейнер сам ничего не делает — это рабочее место администратора УЦ.
# Заходим внутрь: docker compose exec ca bash
CMD ["sleep", "infinity"]
